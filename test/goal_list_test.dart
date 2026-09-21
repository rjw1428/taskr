import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_list.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  // Calendar-day arithmetic: adding a Duration crosses the DST change an hour short.
  String day(int offset) {
    final now = DateTime.now();
    return DateService().getString(DateTime(now.year, now.month, now.day + offset));
  }

  Future<String> seedGoal(String title, {required int endOffset, GoalStatus status = GoalStatus.active}) =>
      GoalService().addGoal(Goal(
        title: title,
        timeframe: GoalTimeframe.oneMonth,
        frequency: GoalFrequency.daily,
        startDate: day(-10),
        endDate: day(endOffset),
        status: status,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        modifiedAt: DateTime.now().millisecondsSinceEpoch,
      ));

  Future<void> seedHabit(String id, Map<String, dynamic> data) => env.col('habits').doc(id).set({
        'title': id,
        'startDate': day(0),
        'status': 'active',
        'recurrenceType': 'Daily',
        'createdAt': 1,
        ...data,
      });

  Future<Map<String, dynamic>?> habitDoc(String id) async => (await env.col('habits').doc(id).get()).data();

  Future<int> instanceCount(String habitId) async {
    var n = 0;
    for (final d in (await env.col('tasks').get()).docs) {
      n += (await env.col('tasks').doc(d.id).collection('items').where('habitId', isEqualTo: habitId).get()).size;
    }
    return n;
  }

  Finder menuFor(String habitTitle) => find.descendant(
        of: find.ancestor(of: find.text(habitTitle), matching: find.byType(ListTile)),
        matching: find.byType(PopupMenuButton<String>),
      );

  /// Color of the flame icon in the habit tile titled [habitTitle].
  Color? fireColor(WidgetTester tester, String habitTitle) => tester
      .widget<Icon>(find.descendant(
        of: find.ancestor(of: find.text(habitTitle), matching: find.byType(ListTile)),
        matching: find.byIcon(FontAwesomeIcons.fire),
      ))
      .color;

  Future<void> pumpList(WidgetTester tester) async {
    await pumpApp(tester, const GoalListPage(), wrapInScaffold: true, size: const Size(400, 2400));
    await settle(tester, frames: 12);
  }

  testWidgets('shows a spinner until the streams deliver, then the empty state', (tester) async {
    // The very first frame, before the fake streams have delivered.
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GoalListPage())));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No goals or habits yet'), findsNothing);
    await settle(tester, frames: 12);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('No goals or habits yet'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no goals or habits', (tester) async {
    await pumpList(tester);
    expect(find.text('No goals or habits yet'), findsOneWidget);
    expect(find.text('Tap + to set a goal or start a habit.'), findsOneWidget);
  });

  testWidgets('groups goals by status and shows each habit cadence and streak', (tester) async {
    await seedGoal('Months goal', endOffset: 70);
    await seedGoal('Weeks goal', endOffset: 21);
    await seedGoal('Days goal', endOffset: 4);
    await seedGoal('Last day goal', endOffset: 1);
    await seedGoal('Expired goal', endOffset: -1);
    await seedGoal('Paused goal', endOffset: 20, status: GoalStatus.paused);
    await seedGoal('Done goal', endOffset: 20, status: GoalStatus.completed);
    await seedGoal('Gone goal', endOffset: 20, status: GoalStatus.deleted);

    await seedHabit('Daily habit', {'currentStreak': 4, 'status': 'paused'});
    await seedHabit('Weekly habit', {
      'recurrenceType': 'Weekly',
      'daysOfWeek': {'Mo': true, 'We': true, 'Fr': false},
      'currentStreak': 2,
    });
    await seedHabit('Weekly none', {'recurrenceType': 'Weekly', 'status': 'paused'});
    await seedHabit('Monthly habit', {'recurrenceType': 'Monthly', 'dayOfMonth': 5, 'status': 'paused'});
    await seedHabit('Yearly habit', {'recurrenceType': 'Yearly', 'status': 'paused'});
    await seedHabit('Fresh habit', {'currentStreak': 0});

    await pumpList(tester);

    // Only a completed goal gets the check icon and a struck-through title.
    expect(find.byIcon(FontAwesomeIcons.circleCheck), findsOneWidget);
    expect(tester.widget<Text>(find.text('Done goal')).style?.decoration, TextDecoration.lineThrough);
    expect(tester.widget<Text>(find.text('Months goal')).style?.decoration, isNot(TextDecoration.lineThrough));

    // The flame lights up only for an active habit with a streak.
    final tokens = Theme.of(tester.element(find.text('Habits'))).appTokens;
    expect(fireColor(tester, 'Weekly habit'), tokens.goal);
    expect(fireColor(tester, 'Daily habit'), tokens.textFaint, reason: 'paused, even with a streak');
    expect(fireColor(tester, 'Fresh habit'), tokens.textFaint, reason: 'active but no streak');
    expect(fireColor(tester, 'Weekly none'), tokens.textFaint);

    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Active Goals'), findsOneWidget);
    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.text('Gone goal'), findsNothing, reason: 'deleted goals are not listed');

    expect(find.text('Daily · 2 months left'), findsOneWidget);
    expect(find.text('Daily · 3 weeks left'), findsNWidgets(2), reason: 'a completed goal keeps its countdown');
    expect(find.text('Daily · 3 days left'), findsOneWidget);
    expect(find.text('Daily · Last day'), findsOneWidget);
    expect(find.text('Daily · Expired'), findsOneWidget);
    expect(find.text('Daily · Paused'), findsOneWidget);

    expect(find.text('Daily · paused'), findsOneWidget);
    expect(find.text('Mo We'), findsOneWidget);
    expect(find.text('2'), findsOneWidget, reason: 'active streak shown');
    expect(find.text('4'), findsNothing, reason: 'paused habits hide their streak');
    expect(find.text('Weekly · paused'), findsOneWidget);
    expect(find.text('Monthly · day 5 · paused'), findsOneWidget);
    expect(find.text('Yearly · paused'), findsOneWidget);

    // Only the active habit was topped up with instances.
    expect(await instanceCount('Weekly habit'), greaterThan(0));
    expect(await instanceCount('Fresh habit'), greaterThan(0));
    expect(await instanceCount('Daily habit'), 0);
  });

  testWidgets('habit menu pauses, resumes, edits and deletes', (tester) async {
    await seedHabit('Shave', {'status': 'active'});
    await seedHabit('Floss', {'status': 'paused'});
    await pumpList(tester);

    await tester.tap(menuFor('Shave'));
    await settle(tester);
    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect((await habitDoc('Shave'))!['status'], 'paused');
    expect(find.text('Daily · paused'), findsNWidgets(2));

    await tester.tap(menuFor('Floss'));
    await settle(tester);
    await tester.tap(find.text('Resume'));
    await settle(tester);
    expect((await habitDoc('Floss'))!['status'], 'active');
    expect(await instanceCount('Floss'), greaterThan(0));

    // Delete, cancelled.
    await tester.tap(menuFor('Shave'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete "Shave"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(await habitDoc('Shave'), isNotNull);

    // Delete, confirmed.
    await tester.tap(menuFor('Shave'));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(await habitDoc('Shave'), isNull);
    expect(find.text('Shave'), findsNothing);

    // Edit opens the habit form.
    await tester.tap(menuFor('Floss'));
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.text('Edit Habit'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Floss'), findsOneWidget);
  });

  testWidgets('tapping a habit card opens its editor; tapping a goal opens its detail page', (tester) async {
    await seedHabit('Journal', {'status': 'paused'});
    await seedGoal('Learn piano', endOffset: 30);
    await pumpList(tester);

    await tester.tap(find.text('Journal'));
    await settle(tester);
    expect(find.text('Edit Habit'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('Learn piano'));
    await settle(tester, frames: 12);
    expect(find.text('Time Progress'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Learn piano'), findsOneWidget);
  });
}
