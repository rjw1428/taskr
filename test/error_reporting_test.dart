import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/error_reporting.dart';

void main() {
  setUp(resetErrorSnackDedupe);

  group('describeError', () {
    test('explains a permission-denied write', () {
      final msg = describeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
      expect(msg, contains('permission-denied'));
      expect(msg, contains("wasn't stored"));
    });

    test('includes the code and message for unmapped Firebase errors', () {
      final msg = describeError(
          FirebaseException(plugin: 'cloud_firestore', code: 'aborted', message: 'too much contention'));
      expect(msg, contains('aborted'));
      expect(msg, contains('too much contention'));
    });

    test('falls back to the error text', () {
      expect(describeError('boom'), 'boom');
    });
  });

  group('showErrorSnack', () {
    Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
          scaffoldMessengerKey: scaffoldMessengerKey,
          home: const Scaffold(body: SizedBox()),
        ));

    testWidgets('shows the action and the underlying error', (tester) async {
      await pumpApp(tester);
      showErrorSnack(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
          action: "Couldn't save task");
      await tester.pump();

      expect(find.textContaining("Couldn't save task"), findsOneWidget);
      expect(find.textContaining('unavailable'), findsOneWidget);
    });

    testWidgets('collapses the same error repeated in a batch', (tester) async {
      await pumpApp(tester);
      final now = DateTime(2026, 1, 1, 12);
      showErrorSnack('boom', action: 'Save failed', now: now);
      showErrorSnack('boom', action: 'Save failed', now: now.add(const Duration(seconds: 1)));
      await tester.pump();

      expect(find.textContaining('boom'), findsOneWidget);
    });

    testWidgets('shows it again once the window has passed', (tester) async {
      await pumpApp(tester);
      final now = DateTime(2026, 1, 1, 12);
      showErrorSnack('boom', action: 'Save failed', now: now);
      await tester.pump();
      showErrorSnack('boom', action: 'Save failed', now: now.add(const Duration(seconds: 10)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('boom'), findsOneWidget);
    });
  });

  group('guardWrite', () {
    testWidgets('reports the failure and returns null', (tester) async {
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ));

      final result = await guardWrite<String>(
        () async => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        action: "Couldn't save task",
      );
      await tester.pump();

      expect(result, isNull);
      expect(find.textContaining('permission-denied'), findsOneWidget);
    });

    testWidgets('passes the value through on success', (tester) async {
      expect(await guardWrite<String>(() async => 'ok'), 'ok');
    });
  });
}
