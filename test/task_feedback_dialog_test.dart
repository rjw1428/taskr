import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/task_feedback_dialog.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  /// Opens the dialog the way task_item does and captures what it pops with.
  Future<Future<String?>> open(WidgetTester tester, {String? existing}) async {
    late Future<String?> result;
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => result = showDialog<String>(
            context: context,
            builder: (_) => TaskFeedbackDialog(existingFeedback: existing),
          ),
          child: const Text('open'),
        ),
      ),
      wrapInScaffold: true,
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('How was this task?'), findsOneWidget);
    return result;
  }

  testWidgets('chip plus comment submits chip|comment', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Too easy'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  breezed through it ');
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(await result, 'too_easy|breezed through it');
    expect(find.text('How was this task?'), findsNothing);
  });

  testWidgets('chip alone submits the chip id', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Enjoyed this'));
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(await result, 'enjoyed');
  });

  testWidgets('comment alone submits the comment', (tester) async {
    final result = await open(tester);
    await tester.enterText(find.byType(TextField), 'just a note');
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(await result, 'just a note');
  });

  testWidgets('nothing selected submits null; tapping a chip twice deselects it', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Too hard'));
    await tester.pump();
    await tester.tap(find.text('Too hard'));
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(await result, isNull);
  });

  testWidgets('cancel pops with null', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text('Not relevant'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await result, isNull);
  });

  testWidgets('existing chip|comment feedback pre-fills both', (tester) async {
    final result = await open(tester, existing: 'too_hard|a|b');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'a|b');
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(await result, 'too_hard|a|b');
  });

  testWidgets('existing chip-only feedback pre-selects the chip', (tester) async {
    final result = await open(tester, existing: 'enjoyed');
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(await result, 'enjoyed');
  });

  testWidgets('existing free-form feedback lands in the comment box', (tester) async {
    final result = await open(tester, existing: 'no chip here');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'no chip here');
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(await result, 'no chip here');
  });

  testWidgets('the submitted feedback is persisted by GoalService.submitTaskFeedback', (tester) async {
    await env.col('tasks').doc('2026-09-19').collection('items').doc('t1').set({
      'title': 'Run', 'completed': false, 'priority': 'low', 'added': 1, 'tags': [], 'userId': env.uid,
      'dueDate': '2026-09-19', 'type': 'task', 'goalId': 'g1',
    });
    await env.col('goals').doc('g1').collection('generations').doc('gen1').set({
      'generatedAt': 1, 'weekStart': '2026-09-14', 'weekEnd': '2026-09-20', 'taskIds': ['t1'],
      'prompt': 'p', 'response': 'r',
    });
    final result = await open(tester);
    await tester.tap(find.text('Too easy'));
    await tester.pump();
    await tester.tap(find.text('Submit'));
    await settle(tester);
    final feedback = await result;
    final task = Task(id: 't1', title: 'Run', dueDate: '2026-09-19', goalId: 'g1', added: 1);
    await GoalService().submitTaskFeedback(task, feedback!);

    final item = await env.col('tasks').doc('2026-09-19').collection('items').doc('t1').get();
    expect(item.data()!['feedback'], 'too_easy');
    final gen = await env.col('goals').doc('g1').collection('generations').doc('gen1').get();
    expect(gen.data()!['taskFeedback'], {'t1': 'too_easy'});
  });
}
