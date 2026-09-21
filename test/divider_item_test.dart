import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/task_list/divider_item.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Task divider(String label) => Task(id: 'd1', added: 1, title: label, type: 'divider', dueDate: '2026-09-19');

  Future<void> mount(WidgetTester tester, Task d, List<Task> deleted) async {
    await pumpApp(
      tester,
      Column(children: [DividerItem(divider: d, index: 0, onDelete: deleted.add)]),
      wrapInScaffold: true,
    );
    await settle(tester);
  }

  testWidgets('a labelled divider shows its label between two rules', (tester) async {
    await mount(tester, divider('Afternoon'), []);
    expect(find.text('Afternoon'), findsOneWidget);
    expect(find.byType(Divider), findsNWidgets(2));
    expect(find.byIcon(FontAwesomeIcons.gripLines), findsOneWidget);
  });

  testWidgets('an unlabelled divider is a single rule', (tester) async {
    await mount(tester, divider(''), []);
    expect(find.byType(Divider), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('tapping the x hands the divider to onDelete', (tester) async {
    final deleted = <Task>[];
    await mount(tester, divider('Evening'), deleted);
    await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
    await settle(tester);
    expect(deleted.single.title, 'Evening');
    expect(deleted.single.isDivider, isTrue);
  });
}
