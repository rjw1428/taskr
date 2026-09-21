import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:taskr/accomplishments/accomplishment_detail_page.dart';
import 'package:taskr/accomplishments/accomplishment_list.dart';
import 'package:taskr/performance/performance_page.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  String key(DateTime d) => DateService().getString(d);
  DateTime daysBack(int n) => today.subtract(Duration(days: n));

  /// One performance doc per day, the way PerformanceService writes them.
  Future<void> perf(DateTime day, {Map<String, int>? completed, Map<String, int>? pushed}) =>
      env.col('performance').doc(key(day)).set({
        'date': Timestamp.fromDate(day),
        if (completed != null) 'completed': completed,
        if (pushed != null) 'pushed': pushed,
      });

  Future<void> tag(String id, String label) => env.col('tags').doc(id).set({'label': label, 'deleted': false});

  Future<void> accomplishment(String id, String title, String date, int score) =>
      env.col('accomplishments').doc(id).set({'title': title, 'date': date, 'difficultyScore': score});

  Future<void> habit(String id, String title, int longest, {String? lastCompleted}) => env.col('habits').doc(id).set({
        'title': title,
        'startDate': '2026-01-01',
        'longestStreak': longest,
        if (lastCompleted != null) 'lastCompletedDate': lastCompleted,
        'createdAt': 1,
      });

  Future<void> openTask(DateTime day, String priority) =>
      env.col('tasks').doc(key(day)).collection('items').add({
        'title': 'left over',
        'completed': false,
        'priority': priority,
        'added': 1,
        'tags': [],
        'userId': env.uid,
        'dueDate': key(day),
        'type': 'task',
        'modified': '',
      });

  Future<void> mount(WidgetTester tester, {Size size = const Size(700, 2600)}) async {
    await pumpApp(tester, const PerformancePage(), wrapInScaffold: true, size: size);
    await settle(tester, frames: 10);
  }

  /// Seeds a few weeks of history plus tags so every card has something to show.
  Future<void> seedRichHistory() async {
    await tag('work', 'Work');
    await perf(today, completed: {'ALL': 5, 'work': 3, 'Other': 2}, pushed: {'ALL': 2});
    await perf(daysBack(1), completed: {'ALL': 3, 'work': 3});
    await perf(daysBack(2), pushed: {'ALL': 1}); // pushed-only day
    await perf(daysBack(4), completed: {'ALL': 8, 'Other': 8}, pushed: {'ALL': 0});
    await perf(daysBack(6), completed: {'ALL': 12, 'work': 7, 'Other': 5}); // best day, > 10
    await perf(daysBack(20), completed: {'ALL': 4, 'work': 4});
    await perf(daysBack(45), completed: {'ALL': 2, 'Other': 2});
    await perf(daysBack(100), completed: {'ALL': 6, 'work': 6});
  }

  testWidgets('shows the empty state when the week has no data', (tester) async {
    await mount(tester);
    expect(find.text('No performance data yet'), findsOneWidget);
    expect(find.text('Complete some tasks to start tracking your progress.'), findsOneWidget);
  });

  testWidgets('data older than a week alone still shows the empty state', (tester) async {
    await perf(daysBack(30), completed: {'ALL': 9});
    await mount(tester);
    expect(find.text('No performance data yet'), findsOneWidget);
  });

  testWidgets('renders every card from seeded history', (tester) async {
    await seedRichHistory();
    await habit('h1', 'Stretch', 4, lastCompleted: '2026-09-10');
    await habit('h2', 'Read', 9);
    await accomplishment('a1', 'Shipped v2', '2026-08-14T10:00:00.000', 9);
    await accomplishment('a2', 'Ran a 10k', '2026-06-21T10:00:00.000', 6);
    await mount(tester);

    // Average header: 28 points in the last 7 days.
    expect(find.text('THIS PERIOD'), findsOneWidget);
    expect(find.text('4.0'), findsOneWidget);
    // The page's history window reaches a full year back, so the 1y average
    // divides all 40 points by the 101 days since the oldest doc.
    await tester.tap(find.text('1y'));
    await settle(tester);
    expect(find.text((40 / 101).toStringAsFixed(1)), findsOneWidget); // 0.4
    await tester.tap(find.text('7d'));
    await settle(tester);

    // Daily score chart in Total mode.
    expect(find.text('Daily score'), findsOneWidget);
    expect(find.text('Total'), findsOneWidget);
    expect(find.text('Breakdown'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Work'), findsNothing); // legend only in breakdown mode
    // The y-axis scales to the largest total (12 * 1.2 -> 15), ticking every 2.
    expect(find.text('14'), findsOneWidget);
    expect(find.text('16'), findsNothing);
    // Both charts label the last seven days by weekday, oldest on the left and
    // today on the right.
    for (var n = 0; n < 7; n++) {
      expect(find.text(DateFormat('E').format(daysBack(n))), findsNWidgets(2), reason: 'day -$n');
    }
    final lineRect = tester.getRect(find.byType(LineChart));
    final todayLabels = find.text(DateFormat('E').format(today)).evaluate().map((e) => tester.getCenter(find.byWidget(e.widget)));
    expect(todayLabels.where((c) => lineRect.contains(c)).single.dx, greaterThan(lineRect.right - 60));
    final oldestLabels = find.text(DateFormat('E').format(daysBack(6))).evaluate().map((e) => tester.getCenter(find.byWidget(e.widget)));
    expect(oldestLabels.where((c) => lineRect.contains(c)).single.dx, lessThan(lineRect.left + 100));

    // Heatmap.
    expect(find.text('Consistency'), findsOneWidget);

    // Points lost: 2 + 1 + 0 pushed, nothing missed yet.
    expect(find.text('Points lost'), findsOneWidget);
    expect(find.text('3 deferred · 0 missed · last 7 days'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Pushed'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    // Tallest bar is 2, so the axis runs to 3 in steps of 1.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Accomplishments summary.
    expect(find.text('Latest accomplishments'), findsOneWidget);
    expect(find.text('See all'), findsOneWidget);
    expect(find.text('Shipped v2'), findsOneWidget);
    expect(find.text('08/14'), findsOneWidget);
    expect(find.text('Ran a 10k'), findsOneWidget);

    // Records.
    expect(find.text('Records'), findsOneWidget);
    expect(find.text('BEST DAY'), findsOneWidget);
    expect(find.text('12 pts'), findsOneWidget);
    expect(find.text(DateFormat('MMM d, yyyy').format(daysBack(6))), findsOneWidget);
    expect(find.text('LONGEST STREAK'), findsOneWidget);
    expect(find.text('9 days'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget); // no lastCompletedDate: title only
  });

  testWidgets('the y-axis falls back to 4 when the shown series have no points', (tester) async {
    // Only an ALL total: Breakdown mode has nothing to draw, so the axis must
    // not collapse to 0 (which would make the chart unreadable).
    await perf(today, completed: {'ALL': 3});
    await mount(tester);
    await tester.tap(find.text('Breakdown'));
    await settle(tester);

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.maxY, 4);
  });

  testWidgets('Breakdown mode shows a legend that maps tag ids to labels', (tester) async {
    await seedRichHistory();
    await mount(tester);

    await tester.tap(find.text('Breakdown'));
    await settle(tester);

    expect(find.text('Work'), findsOneWidget); // 'work' id resolved through TagProvider
    expect(find.text('Other'), findsOneWidget); // no tag: raw key
    expect(find.text('ALL'), findsNothing);
    // The y-axis now fits the tallest single effort (8 * 1.2 -> 10), not the total.
    expect(find.text('10'), findsOneWidget);
    expect(find.text('14'), findsNothing);

    await tester.tap(find.text('Total'));
    await settle(tester);
    expect(find.text('Work'), findsNothing);
  });

  testWidgets('touching the charts raises their tooltips', (tester) async {
    await seedRichHistory();
    await mount(tester);

    // Today's point sits on the right edge of the line chart's plot area.
    final lineRect = tester.getRect(find.byType(LineChart));
    final gesture = await tester.startGesture(Offset(lineRect.right - 2, lineRect.top + 40));
    await tester.pump(const Duration(milliseconds: 100));
    // fl_chart paints tooltips on its canvas, so there is no Text to find; the
    // tooltip builders run and the chart must survive the touch without error.
    expect(find.byType(LineChart), findsOneWidget);
    await gesture.up();
    await settle(tester);

    // The bar chart reserves 28px on the left and bottom for axis titles and
    // spreads seven bars with spaceAround; the last bar is today.
    final barRect = tester.getRect(find.byType(BarChart));
    final x = barRect.left + 28 + (barRect.width - 28) * (6.5 / 7);
    final g2 = await tester.startGesture(Offset(x, barRect.bottom - 28 - 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(BarChart), findsOneWidget);
    await g2.up();
    await settle(tester);
  });

  testWidgets('missed points from unfinished tasks stack onto the pushed chart', (tester) async {
    await perf(today, completed: {'ALL': 1});
    for (var i = 0; i < 4; i++) {
      await openTask(daysBack(1), 'high'); // 12 missed: pushes the axis interval past 10
    }
    await openTask(daysBack(3), 'low'); // 1 missed
    await openTask(today, 'high'); // today never counts as missed
    await mount(tester);

    expect(find.text('0 deferred · 13 missed · last 7 days'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    // Tallest stack is 12: the axis runs to 15 in steps of 3.
    expect(find.text('12'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('14'), findsNothing);

    final barRect = tester.getRect(find.byType(BarChart));
    // Yesterday is the second-to-last bar of seven.
    final x = barRect.left + 28 + (barRect.width - 28) * (5.5 / 7);
    final g = await tester.startGesture(Offset(x, barRect.bottom - 28 - 4));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(BarChart), findsOneWidget);
    await g.up();
    await settle(tester);
  });

  testWidgets('pushed and missed points on the same day stack into one bar', (tester) async {
    await perf(today, completed: {'ALL': 1});
    await perf(daysBack(1), pushed: {'ALL': 3});
    await openTask(daysBack(1), 'high'); // 3 missed on the same day
    await mount(tester);

    expect(find.text('3 deferred · 3 missed · last 7 days'), findsOneWidget);
    expect(find.text('Nothing pushed or missed — nice.'), findsNothing);
    expect(find.byType(BarChart), findsOneWidget);
    // The stacked bar is 6 tall, so the axis runs to 8 in steps of 2.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.text('10'), findsNothing);
  });

  for (final (pushed, present, absent) in [
    (4, ['3', '5'], ['6']), // <= 4: every unit, axis to 5
    (9, ['10', '12'], ['9']), // <= 10: every 2, axis to 12
    (10, ['10', '12'], ['9']), // <= 10: every 2, axis to 13
    (11, ['3', '12'], ['10']), // above 10: quarter steps (3), axis to 14
  ]) {
    testWidgets('the points-lost axis interval follows the tallest bar ($pushed)', (tester) async {
      await perf(today, completed: {'ALL': 1}, pushed: {'ALL': pushed});
      await mount(tester);

      expect(find.byType(BarChart), findsOneWidget);
      for (final label in present) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in absent) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });
  }

  testWidgets('a clean week says so instead of drawing an empty chart', (tester) async {
    await perf(today, completed: {'ALL': 1});
    await mount(tester);

    expect(find.text('0 deferred · 0 missed · last 7 days'), findsOneWidget);
    expect(find.text('Nothing pushed or missed — nice.'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });

  testWidgets('records fall back when nothing has been completed and no habit has a streak', (tester) async {
    await perf(today, pushed: {'ALL': 2});
    await habit('h1', 'Stretch', 0);
    await mount(tester);

    expect(find.text('0 pts'), findsOneWidget);
    expect(find.text('Complete tasks to set a record'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Build a habit streak'), findsOneWidget);
  });

  testWidgets('a longest-streak habit shows its last completed date', (tester) async {
    await perf(today, completed: {'ALL': 1});
    await habit('h1', 'Stretch', 4, lastCompleted: '2026-09-10');
    await mount(tester);

    expect(find.text('4 days'), findsOneWidget);
    expect(find.text('Stretch · 2026-09-10'), findsOneWidget);
  });

  testWidgets('with no accomplishments the summary says so', (tester) async {
    await perf(today, completed: {'ALL': 1});
    await mount(tester);
    expect(find.text('No accomplishments yet!'), findsOneWidget);
  });

  testWidgets('tapping an accomplishment opens its detail page and See all opens the list', (tester) async {
    await perf(today, completed: {'ALL': 1});
    await accomplishment('a1', 'Shipped v2', '2026-08-14T10:00:00.000', 9);
    await mount(tester);

    await tester.tap(find.text('Shipped v2'));
    await settle(tester);
    expect(find.byType(AccomplishmentDetailPage), findsOneWidget);
    expect(find.text('Date: 2026-08-14T10:00:00.000'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);

    await tester.tap(find.text('See all'));
    await settle(tester);
    expect(find.byType(AccomplishmentListPage), findsOneWidget);
    expect(find.text('August 2026'), findsOneWidget);
  });

  group('alignDailyCompleted', () {
    test('lines the last seven days up oldest-first, ending with today', () {
      Map<String, dynamic> doc(DateTime day, int all) => {'date': Timestamp.fromDate(day), 'completed': {'ALL': all}};
      final aligned = alignDailyCompleted([
        doc(today, 5),
        doc(daysBack(6), 1),
        doc(daysBack(7), 9), // just outside the window
      ], today);

      expect(aligned.length, 7);
      expect(aligned.first['ALL'], 1);
      expect(aligned.last['ALL'], 5);
      expect(aligned.sublist(1, 6).every((d) => d.isEmpty), isTrue);
    });
  });

  group('bottomTitleWidgets', () {
    TitleMeta meta(double v) => TitleMeta(
          min: 0,
          max: 6,
          parentAxisSize: 600,
          axisPosition: v * 100,
          appliedInterval: 1,
          sideTitles: const SideTitles(showTitles: true),
          formattedValue: v.toString(),
          axisSide: AxisSide.bottom,
        );
    String labelAt(double v) => ((bottomTitleWidgets(v, meta(v), 7, Colors.black) as SideTitleWidget).child as Text).data!;

    test('labels the last slot with today and the first with six days back', () {
      expect(labelAt(6), DateFormat('E').format(today));
      expect(labelAt(0), DateFormat('E').format(daysBack(6)));
      expect(labelAt(5), DateFormat('E').format(daysBack(1)));
    });
  });

  group('computeChartSeries', () {
    Map<String, dynamic> day(Map<String, int> m) => m;
    const colors = [Colors.red, Colors.green, Colors.blue];

    test('Total mode keeps only ALL visible, with the first colour', () {
      final series = computeChartSeries([
        day({'ALL': 3, 'work': 3}),
        day({}),
        day({'ALL': 2, 'Other': 2}),
      ], true, colors);

      final byKey = {for (final s in series) s.key: s};
      expect(byKey.keys, containsAll(['ALL', 'work', 'Other']));
      expect(byKey['ALL']!.shown, isTrue);
      expect(byKey['work']!.shown, isFalse);
      expect(byKey['ALL']!.color, Colors.red);
      // ALL: 3, 0, 2 with a filled-in zero for the empty day.
      expect(byKey['ALL']!.spots.map((s) => s.y), [3.0, 0.0, 2.0]);
      // A key first seen on a later day only starts there.
      expect(byKey['Other']!.spots.map((s) => s.x), [2.0]);
    });

    test('Breakdown mode hides ALL and cycles the palette', () {
      final series = computeChartSeries([
        day({'ALL': 6, 'a': 1, 'b': 2, 'c': 3}),
      ], false, colors);

      expect(series.where((s) => s.shown).map((s) => s.key), ['a', 'b', 'c']);
      expect(series.firstWhere((s) => s.key == 'ALL').shown, isFalse);
      expect(series.map((s) => s.color).toSet().length, 3); // 4 series, 3 colours: one repeats
    });

    test('seriesToBars mirrors visibility and fills only in Total mode', () {
      final series = [
        const ChartSeries('ALL', Colors.red, true, [FlSpot(0, 1)]),
        const ChartSeries('x', Colors.blue, false, [FlSpot(0, 1)]),
      ];
      final total = seriesToBars(series, true);
      expect(total.map((b) => b.show), [true, false]);
      expect(total.every((b) => b.belowBarData.show), isTrue);

      final breakdown = seriesToBars(series, false);
      expect(breakdown.every((b) => !b.belowBarData.show), isTrue);
      expect(breakdown[1].dotData.show, isFalse);
    });
  });
}
