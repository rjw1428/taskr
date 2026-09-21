import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_detail_page.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late GoalService svc;
  setUp(() async {
    env = await TestEnv.create();
    svc = GoalService();
  });
  tearDown(() => env.dispose());

  // Calendar-day arithmetic: adding a Duration crosses the DST change an hour short.
  String day(int offset) {
    final now = DateTime.now();
    return DateService().getString(DateTime(now.year, now.month, now.day + offset));
  }

  Future<String> seedGoal({
    String title = 'Learn piano',
    String? description,
    int startOffset = -10,
    int endOffset = 20,
    GoalStatus status = GoalStatus.active,
  }) =>
      svc.addGoal(Goal(
        title: title,
        description: description,
        timeframe: GoalTimeframe.oneMonth,
        frequency: GoalFrequency.nTimesWeek,
        frequencyCount: 3,
        startDate: day(startOffset),
        endDate: day(endOffset),
        status: status,
        createdAt: 1,
        modifiedAt: 1,
      ));

  Future<void> seedTask(String goalId, String id, {required bool completed}) =>
      env.col('tasks').doc(day(-1)).collection('items').doc(id).set({
        'title': id, 'completed': completed, 'userId': env.uid, 'goalId': goalId, 'dueDate': day(-1),
      });

  Future<Map<String, dynamic>?> goalDoc(String id) async => (await env.col('goals').doc(id).get()).data();

  /// Mounts a host page and pushes the detail page from it, so a `pop()` from
  /// the page has somewhere to land.
  Future<void> openDetail(WidgetTester tester, String goalId) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GoalDetailPage(goalId: goalId, goalService: svc)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(400, 1400),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    await settle(tester, frames: 10);
  }

  testWidgets('a missing goal pops the page', (tester) async {
    await openDetail(tester, 'nope');
    expect(find.text('open'), findsOneWidget);
    expect(find.byType(GoalDetailPage), findsNothing);
  });

  testWidgets('an active goal shows its description, dates, live stats and time progress', (tester) async {
    final id = await seedGoal(description: 'Because music');
    await seedTask(id, 'a', completed: true);
    await seedTask(id, 'b', completed: true);
    await seedTask(id, 'c', completed: false);
    await svc.addGeneration(id, Generation(generatedAt: 1, weekStart: 'a', weekEnd: 'b', prompt: '', response: ''));

    await openDetail(tester, id);

    expect(find.widgetWithText(AppBar, 'Learn piano'), findsOneWidget);
    expect(find.text('Because music'), findsOneWidget);
    expect(find.text('1 Month'), findsOneWidget);
    expect(find.text('3x / week'), findsOneWidget);
    expect(find.text(day(-10)), findsOneWidget);
    expect(find.text(day(20)), findsOneWidget);
    expect(find.text('Time Progress'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
    expect(find.text('67%'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Regenerate This Week\'s Tasks'), findsOneWidget);
    expect(find.byTooltip('Pause goal'), findsOneWidget);
    expect(find.text('Goal Complete!'), findsNothing);
  });

  testWidgets('an active goal past its end date is marked completed on open', (tester) async {
    final id = await seedGoal(startOffset: -40, endOffset: -2);
    await openDetail(tester, id);

    expect(find.text('Goal Complete!'), findsOneWidget);
    expect(find.text('0 of 0 tasks completed over 0 weeks (0%)'), findsOneWidget);
    expect(find.text('Time Progress'), findsNothing);
    expect(find.text('Regenerate This Week\'s Tasks'), findsNothing);
    expect(find.byTooltip('Pause goal'), findsNothing);
    expect(find.byIcon(FontAwesomeIcons.penToSquare), findsOneWidget, reason: 'still editable');
    expect((await goalDoc(id))!['status'], 'completed');
  });

  testWidgets('a deleted goal has no actions', (tester) async {
    final id = await seedGoal(status: GoalStatus.deleted);
    await openDetail(tester, id);
    expect(find.byIcon(FontAwesomeIcons.trashCan), findsNothing);
    expect(find.byIcon(FontAwesomeIcons.penToSquare), findsNothing);
    expect(find.byTooltip('Pause goal'), findsNothing);
    expect(find.text('Regenerate This Week\'s Tasks'), findsNothing);
    expect(find.text('Time Progress'), findsNothing);
  });

  testWidgets('pause and resume toggle the goal and show a snackbar', (tester) async {
    final id = await seedGoal(status: GoalStatus.paused);
    await openDetail(tester, id);

    expect(find.text('Goal paused — no new tasks will be generated until you resume.'), findsOneWidget);
    expect(find.text('Regenerate This Week\'s Tasks'), findsNothing);

    await tester.tap(find.byTooltip('Resume goal'));
    await settle(tester, frames: 10);
    expect(find.text('Goal resumed'), findsOneWidget);
    expect((await goalDoc(id))!['status'], 'active');
    expect(find.text('Goal paused — no new tasks will be generated until you resume.'), findsNothing);
    await tester.pump(const Duration(seconds: 5)); // let the first snackbar go, they queue

    await tester.tap(find.byTooltip('Pause goal'));
    await settle(tester, frames: 10);
    expect(find.text('Goal paused — no new tasks will be generated'), findsOneWidget);
    expect(find.text('Goal paused — no new tasks will be generated until you resume.'), findsOneWidget);
    expect((await goalDoc(id))!['status'], 'paused');
    expect(find.byTooltip('Resume goal'), findsOneWidget);
  });

  testWidgets('regenerate creates this week\'s tasks and records a generation', (tester) async {
    final id = await seedGoal();
    svc.llm = (_) async => [
          {'title': 'Practice scales', 'dayOffset': 6, 'effort': 'medium'},
        ];
    await openDetail(tester, id);

    await tester.tap(find.text('Regenerate This Week\'s Tasks'));
    await settle(tester, frames: 12);

    expect(find.text('Tasks regenerated!'), findsOneWidget);
    final gens = await svc.getGenerations(id);
    expect(gens, hasLength(1));
    expect(gens.single.taskIds, hasLength(1));
    expect(find.text('1/1').evaluate().isEmpty, isTrue);
    expect(find.text('0/1'), findsOneWidget, reason: 'stats reload after regeneration');
  });

  testWidgets('while regenerating the button shows a spinner and is disabled', (tester) async {
    final id = await seedGoal();
    final gate = Completer<List<Map<String, dynamic>>>();
    svc.llm = (_) => gate.future;
    await openDetail(tester, id);

    await tester.tap(find.text('Regenerate This Week\'s Tasks'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(FontAwesomeIcons.arrowsRotate), findsNothing);
    final button = find.ancestor(of: find.text('Regenerate This Week\'s Tasks'), matching: find.byWidgetPredicate((w) => w is ElevatedButton));
    expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

    gate.complete([
      {'title': 'Practice scales', 'dayOffset': 6, 'effort': 'medium'},
    ]);
    await settle(tester, frames: 12);
    expect(find.text('Tasks regenerated!'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(FontAwesomeIcons.arrowsRotate), findsOneWidget);
  });

  testWidgets('a goal that starts and ends on the same day shows full time progress', (tester) async {
    final id = await seedGoal(startOffset: 1, endOffset: 1);
    await openDetail(tester, id);
    expect(find.text('Time Progress'), findsOneWidget);
    expect(tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).value, 1.0);
  });

  testWidgets('a failed regeneration reports the error', (tester) async {
    final id = await seedGoal();
    svc.llm = (_) async => throw Exception('model down');
    await openDetail(tester, id);

    await tester.tap(find.text('Regenerate This Week\'s Tasks'));
    await settle(tester, frames: 12);

    expect(find.textContaining('Regeneration failed: Exception: model down'), findsOneWidget);
    expect(await svc.getGenerations(id), isEmpty);
    expect(find.text('Regenerate This Week\'s Tasks'), findsOneWidget, reason: 'button re-enabled');
  });

  testWidgets('delete asks for confirmation, then marks the goal deleted and pops', (tester) async {
    final id = await seedGoal();
    await openDetail(tester, id);

    await tester.tap(find.byIcon(FontAwesomeIcons.trashCan));
    await settle(tester);
    expect(find.text('Delete Goal'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect((await goalDoc(id))!['status'], 'active');
    expect(find.byType(GoalDetailPage), findsOneWidget);

    await tester.tap(find.byIcon(FontAwesomeIcons.trashCan));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester, frames: 10);
    expect((await goalDoc(id))!['status'], 'deleted');
    expect(find.text('Goal deleted'), findsOneWidget);
    expect(find.byType(GoalDetailPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('the edit button opens the goal form in a sheet and reloads on close', (tester) async {
    final id = await seedGoal();
    await openDetail(tester, id);

    await tester.tap(find.byIcon(FontAwesomeIcons.penToSquare));
    await settle(tester);
    expect(find.text('Edit Goal'), findsOneWidget);

    await env.col('goals').doc(id).update({'title': 'Renamed elsewhere'});
    await tester.tap(find.text('Close'));
    await settle(tester, frames: 10);
    expect(find.text('Edit Goal'), findsNothing);
    expect(find.widgetWithText(AppBar, 'Renamed elsewhere'), findsOneWidget);
  });
}
