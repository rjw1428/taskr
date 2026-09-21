import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/goals/goal_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

/// Holds `addGoal` until [gate] completes so the in-flight state is visible.
class _GatedGoalService extends GoalService {
  final gate = Completer<void>();
  @override
  Future<String> addGoal(Goal goal) async {
    await gate.future;
    return super.addGoal(goal);
  }
}

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

  Future<List<Map<String, dynamic>>> goals() async =>
      (await env.col('goals').get()).docs.map((d) => {...d.data(), 'id': d.id}).toList();

  /// Pushes the form from a host page so its `pop()` has somewhere to land.
  Future<void> openForm(WidgetTester tester, {Goal? goal}) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(body: GoalForm(goal: goal, goalService: svc)),
            )),
            child: const Text('open'),
          ),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(400, 1400),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('validates the title and the times-per-week count', (tester) async {
    await openForm(tester);
    expect(find.text('New Goal'), findsOneWidget);
    expect(find.text('Times per week'), findsNothing);

    await tester.tap(find.text('Create Goal'));
    await settle(tester);
    expect(find.text('Please enter your goal'), findsOneWidget);
    expect(await goals(), isEmpty);

    await tester.enterText(field('What do you want to achieve?'), '  Learn piano ');
    await tester.tap(find.text('N/Week'));
    await settle(tester);
    expect(find.text('Times per week'), findsOneWidget);
    await tester.enterText(field('Times per week'), '9');
    await tester.tap(find.text('Create Goal'));
    await settle(tester);
    expect(find.text('1-7'), findsOneWidget);
    expect(await goals(), isEmpty);

    // Switching back to a frequency without a count clears that validation.
    await tester.tap(find.text('Auto'));
    await settle(tester);
    expect(find.text('Times per week'), findsNothing);
  });

  testWidgets('creates the goal, pops, and generates the first week of tasks', (tester) async {
    final prompts = <String>[];
    svc.llm = (p) async {
      prompts.add(p);
      return [
        {'title': 'Scales', 'dayOffset': 6}
      ];
    };
    await openForm(tester);

    await tester.enterText(field('What do you want to achieve?'), '  Learn piano ');
    await tester.enterText(field('Description (optional)'), ' Weekly lessons ');
    await tester.tap(find.text('1W'));
    await settle(tester);
    await tester.tap(find.text('N/Week'));
    await settle(tester);
    await tester.enterText(field('Times per week'), '4');
    await tester.tap(find.text('Create Goal'));
    await settle(tester, frames: 12);

    expect(find.text('Goal created! Generating tasks...'), findsOneWidget);
    expect(find.text('New Goal'), findsNothing, reason: 'form popped');

    final g = (await goals()).single;
    expect(g['title'], 'Learn piano');
    expect(g['description'], 'Weekly lessons');
    expect(g['timeframe'], '1_week');
    expect(g['frequency'], 'n_times_week');
    expect(g['frequencyCount'], 4);
    expect(g['startDate'], day(0));
    expect(g['endDate'], day(7));
    expect(g['status'], 'active');

    expect(prompts.single, contains('Generate 4 tasks'));
    expect((await svc.getGenerations(g['id'] as String)).single.taskIds, hasLength(1));
  });

  testWidgets('an empty description is stored as absent, and a failed generation still keeps the goal',
      (tester) async {
    svc.llm = (_) async => throw Exception('model down');
    await openForm(tester);

    await tester.enterText(field('What do you want to achieve?'), 'Run');
    await tester.enterText(field('Description (optional)'), '   ');
    await tester.tap(find.text('3M'));
    await settle(tester);
    await tester.tap(find.text('Create Goal'));
    await settle(tester, frames: 12);

    final g = (await goals()).single;
    expect(g.containsKey('description'), isFalse);
    expect(g['timeframe'], '3_months');
    expect(g['frequency'], 'daily');
    expect(g.containsKey('frequencyCount'), isFalse);
    expect(find.text('New Goal'), findsNothing);
    expect(await svc.getGenerations(g['id'] as String), isEmpty);
    expect(find.textContaining("Couldn't generate tasks for the goal"), findsOneWidget);
  });

  testWidgets('while the goal is being saved the button shows a spinner and is disabled', (tester) async {
    final gated = _GatedGoalService();
    svc = gated;
    await openForm(tester);
    await tester.enterText(field('What do you want to achieve?'), 'Run');
    await tester.tap(find.text('Create Goal'));
    await tester.pump();

    expect(find.text('Create Goal'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(await goals(), isEmpty);

    gated.llm = (_) async => [];
    gated.gate.complete();
    await settle(tester, frames: 12);
    expect(find.text('New Goal'), findsNothing, reason: 'popped once the save finished');
    expect((await goals()).single['title'], 'Run');
  });

  testWidgets('a save failure is shown and leaves the form open', (tester) async {
    await openForm(tester);
    await tester.enterText(field('What do you want to achieve?'), 'Run');
    AuthService().user = null;

    await tester.tap(find.text('Create Goal'));
    await settle(tester, frames: 12);

    expect(find.text('Error: Exception: No user logged in'), findsOneWidget);
    expect(find.text('New Goal'), findsOneWidget);
    expect(find.text('Create Goal'), findsOneWidget, reason: 'button re-enabled');
  });

  testWidgets('editing prefills the fields and updates the stored goal', (tester) async {
    final id = await svc.addGoal(Goal(
      title: 'Old title',
      description: 'Old desc',
      timeframe: GoalTimeframe.oneMonth,
      frequency: GoalFrequency.nTimesWeek,
      frequencyCount: 2,
      startDate: '2026-09-01',
      endDate: '2026-10-01',
      createdAt: 1,
      modifiedAt: 1,
    ));
    final goal = (await svc.getGoal(id))!;
    await openForm(tester, goal: goal);

    expect(find.text('Edit Goal'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Old title'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Old desc'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '2'), findsOneWidget);

    await tester.enterText(field('What do you want to achieve?'), 'New title');
    await tester.tap(find.text('1Y'));
    await settle(tester);
    await tester.tap(find.text('Daily'));
    await settle(tester);
    await tester.tap(find.text('Update'));
    await settle(tester, frames: 12);

    expect(find.text('Goal updated'), findsOneWidget);
    expect(find.text('Edit Goal'), findsNothing);
    final g = (await goals()).single;
    expect(g['title'], 'New title');
    expect(g['description'], 'Old desc');
    expect(g['timeframe'], '1_year');
    expect(g['frequency'], 'daily');
    expect(g['startDate'], '2026-09-01', reason: 'start is kept');
    expect(g['endDate'], '2027-09-01', reason: 'end recomputed from the original start');
    expect(g['modifiedAt'], greaterThan(1));
  });

  testWidgets('editing a goal without a count keeps the default, and Close discards', (tester) async {
    final id = await svc.addGoal(Goal(
      title: 'Auto goal',
      timeframe: GoalTimeframe.sixMonths,
      frequency: GoalFrequency.auto,
      startDate: '2026-09-01',
      endDate: '2027-03-01',
      createdAt: 1,
      modifiedAt: 1,
    ));
    await openForm(tester, goal: (await svc.getGoal(id))!);

    await tester.enterText(field('What do you want to achieve?'), 'Changed');
    await tester.tap(find.text('Close'));
    await settle(tester);

    expect(find.text('Edit Goal'), findsNothing);
    expect((await goals()).single['title'], 'Auto goal');
  });
}
