import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    test('maps every well-known Firestore code to a sentence', () {
      String of(String code, [String? message]) =>
          describeError(FirebaseException(plugin: 'cloud_firestore', code: code, message: message));
      expect(of('unauthenticated'), contains('signed out'));
      expect(of('unavailable'), contains('unavailable'));
      expect(of('deadline-exceeded'), contains('too long'));
      expect(of('not-found'), contains('no longer exists'));
      expect(of('failed-precondition'), 'Save failed (failed-precondition)');
      expect(of('failed-precondition', 'needs index'), contains('needs index'));
      expect(of('resource-exhausted'), contains('Quota'));
      // Every sentence quotes the code verbatim, so a field report is actionable.
      for (final code in ['permission-denied', 'unavailable', 'deadline-exceeded', 'not-found', 'resource-exhausted']) {
        expect(of(code), contains('($code)'));
      }
      expect(of('aborted'), 'Save failed (aborted)');
    });

    test('describes callable, platform, socket and timeout failures', () {
      expect(describeError(FirebaseFunctionsException(code: 'internal', message: 'oops')),
          'Server call failed (internal): oops');
      expect(describeError(PlatformException(code: 'chan', message: 'no channel')), 'Save failed (chan): no channel');
      expect(describeError(PlatformException(code: 'chan')), 'Save failed (chan)');
      expect(describeError(const SocketException('down')), contains('check your connection'));
      expect(describeError(TimeoutException('slow')), contains('too long'));
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

    // Every showSnackBar call puts a distinct SnackBar on screen (the
    // messenger keys each one), so "still the same snackbar" is the
    // observable difference between a collapsed repeat and a re-show.
    Key? visibleSnackBar(WidgetTester tester) => tester.widget<SnackBar>(find.byType(SnackBar)).key;

    testWidgets('collapses the same error repeated in a batch', (tester) async {
      await pumpApp(tester);
      final now = DateTime(2026, 1, 1, 12);
      showErrorSnack('boom', action: 'Save failed', now: now);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final first = visibleSnackBar(tester);

      showErrorSnack('boom', action: 'Save failed', now: now.add(const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('boom'), findsOneWidget);
      expect(visibleSnackBar(tester), first);
    });

    testWidgets('shows it again once the window has passed', (tester) async {
      await pumpApp(tester);
      final now = DateTime(2026, 1, 1, 12);
      showErrorSnack('boom', action: 'Save failed', now: now);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final first = visibleSnackBar(tester);

      showErrorSnack('boom', action: 'Save failed', now: now.add(const Duration(seconds: 10)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('boom'), findsOneWidget);
      expect(visibleSnackBar(tester), isNot(first));
    });

    testWidgets('a different message inside the window is not collapsed', (tester) async {
      await pumpApp(tester);
      final now = DateTime(2026, 1, 1, 12);
      showErrorSnack('boom', action: 'Save failed', now: now);
      await tester.pump();
      showErrorSnack('bang', action: 'Save failed', now: now.add(const Duration(seconds: 1)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('bang'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  group('snackbar plumbing', () {
    testWidgets('a notice is neutral and dismissable', (tester) async {
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ));
      showNoticeSnack('Queued offline');
      await tester.pump();
      expect(find.text('Queued offline'), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.backgroundColor, isNull);
      expect(bar.duration, const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Queued offline'), findsNothing);
    });

    testWidgets('reportError logs the stack and shows the snackbar', (tester) async {
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ));
      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        reportError('boom', StackTrace.current, 'Saving');
      } finally {
        debugPrint = previous;
      }
      await tester.pump();
      expect(find.text('Saving — boom'), findsOneWidget);
      expect(logs.first, 'ERROR (Saving): boom');
      // The stack trace follows the error line.
      expect(logs.length, greaterThan(1));
    });

    test('without a mounted messenger the message is only logged', () {
      final logs = <String>[];
      final previous = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = previous);
      showErrorSnack('orphan');
      expect(logs, contains(contains('No messenger available for: orphan')));
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
