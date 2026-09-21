import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/task_list/coaching.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> open(WidgetTester tester, String response) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog(context: context, builder: (_) => CoachingDialog(response: response)),
          child: const Text('open'),
        ),
      ),
      wrapInScaffold: true,
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('shows the coach response and closes on Close', (tester) async {
    await open(tester, 'Keep going, one task at a time.');
    expect(find.text('Words from your coach'), findsOneWidget);
    expect(find.text('Keep going, one task at a time.'), findsOneWidget);

    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.text('Words from your coach'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('renders in dark theme and with an empty response', (tester) async {
    await pumpApp(tester, const CoachingDialog(response: ''), wrapInScaffold: true, themeMode: ThemeMode.dark);
    await settle(tester);
    expect(find.text('Words from your coach'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
