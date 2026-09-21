import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/view_series.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  final today = DateService().getString(DateTime.now());

  setUp(() async {
    env = await TestEnv.create();
    DateService().setSelectedDate(DateTime(2026, 9, 19));
  });
  tearDown(() => env.dispose());

  Future<Map<String, dynamic>?> item(String date, String id) async =>
      (await env.col('tasks').doc(date).collection('items').doc(id).get()).data();

  /// Mounts a launcher page and pushes [ViewSeries] from it, so the page has a
  /// route to pop back to.
  Future<void> open(WidgetTester tester, Task task) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ViewSeries(task: task))),
          child: const Text('launch'),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(800, 1200),
    );
    await tester.tap(find.text('launch'));
    await tester.pump();
  }

  Future<Task> seedSeries({DateTime? endDate}) async {
    await env.col('recurring').doc('r1').set({
      'recurrenceType': 'Daily',
      'frequency': 1,
      'startDate': DateTime.now().toIso8601String(),
      if (endDate != null) 'endDate': endDate.toIso8601String(),
      'dayOfMonth': 1,
    });
    final task = Task(added: 1, title: 'Standup', dueDate: today, recurringTemplateId: 'r1');
    task.id = await TaskService().addTask(task);
    return task;
  }

  testWidgets('shows the series form once the template loads', (tester) async {
    final task = await seedSeries(endDate: DateTime.now().add(const Duration(days: 10)));
    await open(tester, task);
    await settle(tester, frames: 8);

    expect(find.text('View Recurring Task'), findsOneWidget);
    expect(find.text('Daily'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Delete Series'), findsOneWidget);
  });

  testWidgets('cancel pops back without touching the series', (tester) async {
    final task = await seedSeries(endDate: DateTime.now().add(const Duration(days: 10)));
    await open(tester, task);
    await settle(tester, frames: 8);
    await tester.tap(find.text('Cancel'));
    await settle(tester, frames: 8);
    expect(find.byType(ViewSeries), findsNothing);
    expect((await env.col('recurring').doc('r1').get()).exists, isTrue);
  });

  testWidgets('update with an invalid form shows the validation message', (tester) async {
    final task = await seedSeries();
    await open(tester, task);
    await settle(tester, frames: 8);
    await tester.tap(find.text('Update'));
    await settle(tester);
    expect(find.text('Please fix the errors above.'), findsOneWidget);
    expect(find.byType(ViewSeries), findsOneWidget);
  });

  testWidgets('update rewrites the series and pops', (tester) async {
    final task = await seedSeries(endDate: DateTime.now().add(const Duration(days: 3)));
    await open(tester, task);
    await settle(tester, frames: 8);

    // Touch the form so the page holds an edited template.
    await tester.tap(find.text('Daily'));
    await settle(tester);
    await tester.tap(find.text('Weekly').last);
    await settle(tester);
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);

    await tester.tap(find.text('Update'));
    await settle(tester, frames: 10);

    expect(find.text('Recurring task updated'), findsOneWidget);
    expect(find.byType(ViewSeries), findsNothing);
    final templates = await env.col('recurring').get();
    expect(templates.docs.single.data()['recurrenceType'], 'Weekly');
    expect(templates.docs.single.id, isNot('r1'));
  });

  testWidgets('delete series asks first; cancel keeps everything', (tester) async {
    final task = await seedSeries(endDate: DateTime.now().add(const Duration(days: 3)));
    await open(tester, task);
    await settle(tester, frames: 8);
    await tester.tap(find.text('Delete Series'));
    await settle(tester);
    expect(find.textContaining('Are you sure'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await settle(tester);
    expect(find.byType(ViewSeries), findsOneWidget);
    expect((await env.col('recurring').doc('r1').get()).exists, isTrue);
  });

  testWidgets('confirming delete removes the template and its occurrences, then pops', (tester) async {
    final task = await seedSeries(endDate: DateTime.now().add(const Duration(days: 3)));
    await open(tester, task);
    await settle(tester, frames: 8);
    await tester.tap(find.text('Delete Series'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester, frames: 10);

    expect(find.text('Recurring task series deleted'), findsOneWidget);
    expect(find.byType(ViewSeries), findsNothing);
    expect((await env.col('recurring').doc('r1').get()).exists, isFalse);
    expect(await item(today, task.id!), isNull);
  });

  testWidgets('an orphaned occurrence can be deleted on its own', (tester) async {
    final task = Task(added: 1, title: 'Ghost', dueDate: today, recurringTemplateId: 'gone');
    task.id = await TaskService().addTask(task);
    await open(tester, task);
    await settle(tester, frames: 8);

    expect(find.textContaining('no longer has a template'), findsOneWidget);
    await tester.tap(find.text('Delete This Occurrence'));
    await settle(tester, frames: 8);
    expect(find.text('Occurrence deleted'), findsOneWidget);
    expect(find.byType(ViewSeries), findsNothing);
    expect(await item(today, task.id!), isNull);
  });
}
