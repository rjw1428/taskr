import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taskr/performance/performance_heatmap.dart';
import 'package:taskr/performance/performance_history.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/theme.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  Map<String, dynamic> doc(DateTime day, int all) => {'date': Timestamp.fromDate(day), 'completed': {'ALL': all}};

  Future<void> mount(WidgetTester tester, PerformanceHistory? history,
      {ThemeMode themeMode = ThemeMode.light, Size size = const Size(400, 800)}) async {
    await pumpApp(
      tester,
      PerformanceHeatmap(userId: env.uid),
      wrapInScaffold: true,
      themeMode: themeMode,
      size: size,
      extraProviders: [Provider<PerformanceHistory?>.value(value: history)],
    );
    await settle(tester);
  }

  /// Every 14x14-ish square drawn for a day (past days only; future days are
  /// blank SizedBoxes and the legend swatches are 12x12).
  Iterable<Container> dayCells(WidgetTester tester) => tester
      .widgetList<Container>(find.byType(Container))
      .where((c) => c.decoration is BoxDecoration && (c.constraints?.maxWidth ?? 0) > 12);

  testWidgets('draws 13 weeks, blanking days after today', (tester) async {
    await mount(tester, const PerformanceHistory([]));

    expect(find.text('Consistency'), findsOneWidget);
    expect(find.text('Daily points earned · last 13 weeks'), findsOneWidget);
    expect(find.text('Less'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.text('W'), findsOneWidget);
    expect(find.text('F'), findsOneWidget);

    // 12 full weeks plus today's week up to and including today.
    final expectedPast = 12 * 7 + today.weekday;
    expect(dayCells(tester).length, expectedPast);

    // With no data every cell is the raised surface colour.
    final raised = lightTheme.appTokens.surfaceRaised;
    expect(dayCells(tester).every((c) => (c.decoration as BoxDecoration).color == raised), isTrue);
  });

  testWidgets('colours cells by score level and outlines scores over 10', (tester) async {
    DateTime d(int back) => today.subtract(Duration(days: back));
    await mount(
      tester,
      PerformanceHistory([
        doc(d(0), 12), // > 10: bordered, full primary
        doc(d(1), 9), // level 1.0
        doc(d(2), 6), // level 0.75
        doc(d(3), 3), // level 0.5
        doc(d(4), 1), // level 0.25
        doc(d(5), 0), // raised surface
        doc(today.add(const Duration(days: 30)), 50), // beyond the window, ignored
        doc(today.subtract(const Duration(days: 200)), 50), // before the window, ignored
      ]),
    );

    final theme = lightTheme;
    Color level(double l) => Color.lerp(theme.colorScheme.surface, theme.colorScheme.primary, l)!;
    final decorations = dayCells(tester).map((c) => c.decoration as BoxDecoration).toList();
    final colours = decorations.map((d) => d.color).toList();

    expect(colours.where((c) => c == level(1.0)).length, 2); // scores 12 and 9
    expect(colours.where((c) => c == level(0.75)).length, 1);
    expect(colours.where((c) => c == level(0.5)).length, 1);
    expect(colours.where((c) => c == level(0.25)).length, 1);
    expect(decorations.where((d) => d.border != null).length, 1); // only the 12
  });

  testWidgets('renders month labels for the window and a legend gradient', (tester) async {
    await mount(tester, null);

    // The window spans 13 Mondays; at least three distinct months appear.
    final monthAbbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final shown = monthAbbr.where((m) => find.text(m).evaluate().isNotEmpty).length;
    expect(shown, greaterThanOrEqualTo(3));

    // Five legend swatches of 12x12.
    final swatches = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.constraints?.maxWidth == 12 && c.constraints?.maxHeight == 12);
    expect(swatches.length, 5);
  });

  testWidgets('labels the first week and each month change exactly once', (tester) async {
    await mount(tester, null);

    // Mirror the widget's window: 13 weeks ending with the current one.
    const abbr = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final windowStart = today.subtract(Duration(days: today.weekday - 1)).subtract(const Duration(days: 12 * 7));
    final expected = <String>[];
    int? prevMonth;
    for (var i = 0; i < 13; i++) {
      final monday = windowStart.add(Duration(days: i * 7));
      expected.add(monday.month == prevMonth ? '' : abbr[monday.month]);
      prevMonth = monday.month;
    }

    // The first column is always labelled, and every month in the window
    // appears once, at the week it starts.
    expect(expected.first, isNotEmpty);
    final months = expected.where((l) => l.isNotEmpty).toList();
    expect(months.toSet().length, months.length);
    for (final m in months) {
      expect(find.text(m), findsOneWidget, reason: m);
    }
    // Weeks that do not start a month keep an empty slot so the labels stay
    // aligned with their columns. Four of the empty texts are the blank
    // weekday labels (Tue, Thu, Sat, Sun).
    expect(find.text(''), findsNWidgets(4 + 13 - months.length));

    // Labels are laid out left to right in week order.
    final xs = months.map((m) => tester.getTopLeft(find.text(m)).dx).toList();
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]));
    }
  });

  testWidgets('legend swatches run from the raised surface through the four score levels', (tester) async {
    await mount(tester, null);

    final theme = lightTheme;
    Color level(double l) => Color.lerp(theme.colorScheme.surface, theme.colorScheme.primary, l)!;
    final swatches = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.constraints?.maxWidth == 12 && c.constraints?.maxHeight == 12)
        .map((c) => (c.decoration as BoxDecoration).color)
        .toList();
    expect(swatches, [theme.appTokens.surfaceRaised, level(0.25), level(0.5), level(0.75), level(1.0)]);
    expect(theme.appTokens.surfaceRaised, isNot(theme.colorScheme.surface));
  });

  testWidgets('cells shrink to fit a narrow grid', (tester) async {
    // The grid gets the body width minus the 10px weekday gutter and 4px gap:
    // 192 - 14 = 178, which fits 13 columns of 10px with 12 gaps of 4px.
    await mount(tester, const PerformanceHistory([]), size: const Size(192, 800));

    final cells = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration && c.constraints?.maxWidth != 12)
        .toList();
    expect(cells.length, 12 * 7 + today.weekday);
    for (final c in cells) {
      expect(c.constraints?.maxWidth, closeTo(10, 0.001));
      expect(c.constraints?.maxHeight, closeTo(10, 0.001));
    }
  });

  testWidgets('renders in the dark theme', (tester) async {
    await mount(tester, PerformanceHistory([doc(today, 5)]), themeMode: ThemeMode.dark);
    expect(find.text('Consistency'), findsOneWidget);
    final level = Color.lerp(darkTheme.colorScheme.surface, darkTheme.colorScheme.primary, 0.75)!;
    expect(dayCells(tester).where((c) => (c.decoration as BoxDecoration).color == level).length, 1);
  });
}
