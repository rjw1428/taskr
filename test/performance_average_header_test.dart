import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taskr/performance/performance_average_header.dart';
import 'package:taskr/performance/performance_history.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  Map<String, dynamic> doc(DateTime day, int all) => {'date': Timestamp.fromDate(day), 'completed': {'ALL': all}};

  Future<void> mount(WidgetTester tester, PerformanceHistory? history) async {
    await pumpApp(
      tester,
      PerformanceAverageHeader(userId: env.uid),
      wrapInScaffold: true,
      extraProviders: [Provider<PerformanceHistory?>.value(value: history)],
    );
    await settle(tester);
  }

  Future<void> select(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await settle(tester);
  }

  testWidgets('shows a 7-day average by default and recomputes for each window', (tester) async {
    // 10 today + 4 six days ago = 14 in the 7-day window; 20 more 40 days ago.
    await mount(
      tester,
      PerformanceHistory([
        doc(today, 10),
        doc(today.subtract(const Duration(days: 6)), 4),
        doc(today.subtract(const Duration(days: 40)), 20),
      ]),
    );

    expect(find.text('THIS PERIOD'), findsOneWidget);
    expect(find.text('avg points / day'), findsOneWidget);
    expect(find.text('2.0'), findsOneWidget); // 14 / 7

    await select(tester, '30d');
    expect(find.text('0.5'), findsOneWidget); // 14 / 30

    await select(tester, '90d');
    expect(find.text((34 / 90).toStringAsFixed(1)), findsOneWidget); // 34 / 90 = 0.4

    // 1y: the oldest doc is 40 days back, so the divisor is 41 days, not 365.
    await select(tester, '1y');
    expect(find.text((34 / 41).toStringAsFixed(1)), findsOneWidget); // 0.8
  });

  testWidgets('a window covers exactly its last N days: the day before it is left out', (tester) async {
    // 7d spans today and the six days before it; the doc seven days back must
    // not leak in, while 30d picks it up.
    await mount(
      tester,
      PerformanceHistory([
        doc(today, 7),
        doc(today.subtract(const Duration(days: 6)), 7),
        doc(today.subtract(const Duration(days: 7)), 70),
        doc(today.subtract(const Duration(days: 8)), 70),
      ]),
    );

    expect(find.text('2.0'), findsOneWidget); // 14 / 7
    await select(tester, '30d');
    expect(find.text((154 / 30).toStringAsFixed(1)), findsOneWidget); // 5.1
  });

  testWidgets('the yearly window caps the divisor at 365 days', (tester) async {
    await mount(
      tester,
      PerformanceHistory([
        doc(today.subtract(const Duration(days: 364)), 365),
        doc(today, 365),
      ]),
    );

    await select(tester, '1y');
    expect(find.text('2.0'), findsOneWidget); // 730 / 365
  });

  testWidgets('docs dated in the future or before the stream start are ignored', (tester) async {
    await mount(
      tester,
      PerformanceHistory([
        doc(today.add(const Duration(days: 2)), 100),
        doc(today.subtract(const Duration(days: 400)), 100),
        doc(today, 7),
      ]),
    );

    expect(find.text('1.0'), findsOneWidget); // 7 / 7
    await select(tester, '1y');
    expect(find.text('7.0'), findsOneWidget); // only today counts, 1 effective day
  });

  testWidgets('an empty history reads 0.0 in every window', (tester) async {
    await mount(tester, const PerformanceHistory([]));
    for (final label in ['7d', '30d', '90d', '1y']) {
      await select(tester, label);
      expect(find.text('0.0'), findsOneWidget);
    }
  });

  testWidgets('renders before the history arrives', (tester) async {
    await mount(tester, null);
    expect(find.text('0.0'), findsOneWidget);
    expect(find.byType(SegmentedButton<int>), findsOneWidget);
  });
}
