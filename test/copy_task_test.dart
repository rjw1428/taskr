import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/copy_task.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  // A Wednesday, so the week row runs Mon 14 .. Sun 20.
  final selected = DateTime(2026, 1, 14);

  setUp(() async {
    env = await TestEnv.create();
    DateService().setSelectedDate(selected);
  });
  tearDown(() => env.dispose());

  Task source() => Task(
        id: 'src',
        added: 1,
        title: 'Water plants',
        description: 'Back porch',
        priority: Effort.medium,
        dueDate: '2026-01-14',
        startTime: '08:00',
        tags: [Tag(id: 't1', label: 'home')],
      );

  Future<void> openDialog(WidgetTester tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog(context: context, builder: (_) => CopyTaskScreen(task: source())),
          child: const Text('launch'),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(800, 1200),
    );
    await tester.tap(find.text('launch'));
    await settle(tester);
  }

  Future<List<Map<String, dynamic>>> itemsOn(String date) async =>
      (await env.col('tasks').doc(date).collection('items').get()).docs.map((d) => d.data()).toList();

  testWidgets('the dialog shows the form for the selected day and closes', (tester) async {
    await openDialog(tester);
    expect(find.text('Copy Task'), findsOneWidget);
    expect(find.text('Water plants'), findsOneWidget);
    expect(find.text('2026-01-14'), findsOneWidget);
    expect(find.text('Repeat:'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('01/12'), findsOneWidget);
    expect(find.text('01/18'), findsOneWidget);
    // Nothing is pre-selected.
    expect(tester.widgetList<Checkbox>(find.byType(Checkbox)).every((c) => c.value == false), isTrue);

    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.byType(CopyTaskScreen), findsNothing);
  });

  testWidgets('a blank title fails validation and writes nothing', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(find.text('Please enter the title'), findsOneWidget);
    expect(find.byType(CopyTaskScreen), findsOneWidget);
    expect(await itemsOn('2026-01-13'), isEmpty);
  });

  testWidgets('submitting copies the task onto every ticked day and closes', (tester) async {
    await openDialog(tester);
    await tester.enterText(find.byType(TextFormField), 'Water plants twice');
    await tester.tap(find.byType(Checkbox).at(1)); // Tue 01/13
    await tester.tap(find.byType(Checkbox).at(4)); // Fri 01/16
    await settle(tester);
    await tester.tap(find.text('Submit'));
    await settle(tester, frames: 8);

    expect(find.byType(CopyTaskScreen), findsNothing);
    final tue = await itemsOn('2026-01-13');
    final fri = await itemsOn('2026-01-16');
    expect(tue.single['title'], 'Water plants twice');
    expect(tue.single['description'], 'Back porch');
    expect(tue.single['priority'], 'medium');
    expect(tue.single['startTime'], '08:00');
    expect(tue.single['tags'], ['t1']);
    expect(tue.single['completed'], false);
    expect(fri.single['dueDate'], '2026-01-16');
    expect(await itemsOn('2026-01-14'), isEmpty);
  });

  testWidgets('picking a due date moves the week and pre-ticks that day; cancelling keeps it', (tester) async {
    await openDialog(tester);

    await tester.tap(find.text('Set a due date'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('2026-01-14'), findsOneWidget);

    await tester.tap(find.text('Set a due date'));
    await settle(tester);
    // Move to the 21st (next Wednesday) so the week row shifts.
    await tester.tap(find.text('21'));
    await tester.tap(find.text('OK'));
    await settle(tester);

    expect(find.text('2026-01-21'), findsOneWidget);
    expect(find.text('01/19'), findsOneWidget);
    expect(find.text('01/25'), findsOneWidget);
    final boxes = tester.widgetList<Checkbox>(find.byType(Checkbox)).toList();
    expect(boxes[2].value, isTrue);
    expect(boxes.where((c) => c.value == true), hasLength(1));

    await tester.tap(find.text('Submit'));
    await settle(tester, frames: 8);
    expect((await itemsOn('2026-01-21')).single['title'], 'Water plants');
  });
}
