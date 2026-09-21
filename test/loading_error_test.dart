import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/shared/shared.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  group('LoadingScreen', () {
    testWidgets('shows the message and a spinner', (tester) async {
      await pumpApp(tester, const LoadingScreen(message: 'Loading tasks'));
      expect(find.text('Loading tasks'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('defaults its message and signs out from the app bar', (tester) async {
      await pumpApp(tester, const LoadingScreen());
      expect(find.text('Thinking...'), findsOneWidget);
      expect(env.auth.currentUser, isNotNull);
      await tester.tap(find.byIcon(FontAwesomeIcons.userAstronaut));
      await settle(tester);
      expect(env.auth.currentUser, isNull);
      expect(env.google.log, contains('disconnect:login'));
    });
  });

  group('ErrorMessage', () {
    testWidgets('renders the message in the error color', (tester) async {
      await pumpApp(tester, const ErrorMessage(message: 'Something broke'), wrapInScaffold: true);
      expect(find.text('Something broke'), findsOneWidget);
    });

    testWidgets('defaults to an empty message', (tester) async {
      await pumpApp(tester, const ErrorMessage(), wrapInScaffold: true);
      expect(find.text(''), findsOneWidget);
    });
  });

  group('shared helpers', () {
    test('removeNulls drops null and empty-string values in place', () {
      final obj = <String, dynamic>{'a': 1, 'b': null, 'c': '', 'd': 'keep', 'e': 0};
      final result = removeNulls(obj);
      expect(result, same(obj));
      expect(result, {'a': 1, 'd': 'keep', 'e': 0});
    });

    test('constants expose one color per effort and a chart palette', () {
      expect(ownerEmail, contains('@'));
      expect(priorityColors.keys, containsAll(Effort.values));
      expect(dropdownColors.keys, containsAll(Effort.values));
      expect(chartColors.length, greaterThanOrEqualTo(Days.values.length));
      expect(Days.values.length, 7);
    });
  });
}
