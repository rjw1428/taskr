import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/task_list/health_page.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  const date = '2026-09-19';

  Future<void> open(WidgetTester tester) async {
    await pumpApp(tester, const HealthPage(date: date), size: const Size(400, 1400));
  }

  testWidgets('shows the empty state when there is no entry', (tester) async {
    await open(tester);
    await settle(tester);
    expect(find.text('Health — $date'), findsOneWidget);
    expect(find.text('No health data for this day'), findsOneWidget);
  });

  testWidgets('an entry with no headline metrics is treated as empty', (tester) async {
    await env.col('health').doc(date).set({'date': date, 'sleepScore': 90, 'updatedAt': 5});
    await open(tester);
    await settle(tester);
    expect(find.text('No health data for this day'), findsOneWidget);
  });

  testWidgets('renders every card for a full entry', (tester) async {
    await env.col('health').doc(date).set({
      'date': date,
      'sleepScore': 85,
      'sleepSeconds': 7 * 3600 + 30 * 60,
      'deepSeconds': 3600,
      'lightSeconds': 3 * 3600,
      'remSeconds': 2 * 3600 + 30 * 60,
      'awakeSeconds': 0,
      'bodyBatteryHigh': 95,
      'bodyBatteryLow': 20,
      'bodyBatteryCharged': 60,
      'bodyBatteryDrained': 70,
      'stressAvg': 20,
      'stressMax': 80,
      'steps': 12345,
      'floorsClimbed': 12,
      'activeCalories': 400,
      'restingHeartRate': 52,
    });
    await open(tester);
    await settle(tester);

    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
    expect(find.text('7h 30m'), findsOneWidget);
    // Stage legend: awake is dropped because it is zero.
    expect(find.text('Deep 1h 0m (15%)'), findsOneWidget);
    expect(find.text('Light 3h 0m (46%)'), findsOneWidget);
    expect(find.text('REM 2h 30m (38%)'), findsOneWidget);
    expect(find.textContaining('Awake'), findsNothing);

    expect(find.text('Body Battery'), findsOneWidget);
    expect(find.text('95'), findsOneWidget);
    expect(find.text('20'), findsNWidgets(2)); // battery low and stress average
    expect(find.text('+60'), findsOneWidget);
    expect(find.text('-70'), findsOneWidget);

    expect(find.text('Stress'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);

    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('12345'), findsOneWidget);
    expect(find.text('52 bpm'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
  });

  testWidgets('a sparse entry shows dashes and skips the cards it has no data for', (tester) async {
    await env.col('health').doc(date).set({'date': date, 'sleepSeconds': 5 * 3600, 'restingHeartRate': 60});
    await open(tester);
    await settle(tester);

    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('5h 0m'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(4)); // sleep score, steps, floors, active cal
    expect(find.text('Body Battery'), findsNothing);
    expect(find.text('Stress'), findsNothing);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('60 bpm'), findsOneWidget);
  });

  testWidgets('score and stress colors cover the middle and low bands', (tester) async {
    await env.col('health').doc(date).set({'date': date, 'sleepScore': 65, 'sleepSeconds': 100, 'stressAvg': 40});
    await open(tester);
    await settle(tester);
    expect(tester.widget<Text>(find.text('65')).style!.color, Colors.orangeAccent);
    expect(tester.widget<Text>(find.text('40')).style!.color, Colors.orangeAccent);

    await env.col('health').doc(date).set({'date': date, 'sleepScore': 30, 'sleepSeconds': 100, 'stressAvg': 90});
    await settle(tester);
    expect(tester.widget<Text>(find.text('30')).style!.color, Colors.redAccent);
    expect(tester.widget<Text>(find.text('90')).style!.color, Colors.redAccent);

    await env.col('health').doc(date).set({'date': date, 'sleepScore': 80, 'sleepSeconds': 100, 'stressAvg': 25});
    await settle(tester);
    expect(tester.widget<Text>(find.text('80')).style!.color, Colors.lightGreenAccent);
    expect(tester.widget<Text>(find.text('25')).style!.color, Colors.lightGreenAccent);
  });

  testWidgets('score and stress colors change exactly at the band thresholds', (tester) async {
    await env.col('health').doc(date).set({'date': date, 'sleepScore': 60, 'sleepSeconds': 100, 'stressAvg': 50});
    await open(tester);
    await settle(tester);
    expect(tester.widget<Text>(find.text('60')).style!.color, Colors.orangeAccent, reason: '60 is still orange');
    expect(tester.widget<Text>(find.text('50')).style!.color, Colors.orangeAccent, reason: '50 is still orange');

    await env.col('health').doc(date).set({'date': date, 'sleepScore': 90, 'sleepSeconds': 100, 'stressAvg': 10});
    await settle(tester);
    expect(tester.widget<Text>(find.text('90')).style!.color, Colors.lightGreenAccent);
    expect(tester.widget<Text>(find.text('10')).style!.color, Colors.lightGreenAccent);

    await env.col('health').doc(date).set({'date': date, 'sleepScore': 59, 'sleepSeconds': 100, 'stressAvg': 51});
    await settle(tester);
    expect(tester.widget<Text>(find.text('59')).style!.color, Colors.redAccent);
    expect(tester.widget<Text>(find.text('51')).style!.color, Colors.redAccent);
  });

  testWidgets('the activity card shows for steps alone and hides without steps or resting HR', (tester) async {
    await env.col('health').doc(date).set({'date': date, 'steps': 500});
    await open(tester);
    await settle(tester);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Sleep'), findsNothing);

    await env.col('health').doc(date).set({'date': date, 'stressAvg': 30, 'stressMax': 70});
    await settle(tester);
    expect(find.text('Stress'), findsOneWidget);
    expect(find.text('Activity'), findsNothing);
  });

  testWidgets('signed out shows the empty state', (tester) async {
    env.dispose();
    env = await TestEnv.create(signedIn: false);
    await open(tester);
    await settle(tester);
    expect(find.text('No health data for this day'), findsOneWidget);
  });
}
