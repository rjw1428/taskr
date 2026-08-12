import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/error_reporting.dart';
import 'package:taskr/shared/write_ack.dart';

void main() {
  setUp(resetErrorSnackDedupe);

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: const Scaffold(body: SizedBox()),
      ));

  testWidgets('a server-acknowledged write is confirmed, with no snackbar', (tester) async {
    await pumpApp(tester);
    final ack = await ackWrite(Future<void>.value(), action: "Couldn't save task");
    await tester.pump();

    expect(ack, WriteAck.confirmed);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a failing write reports the error and does not hang', (tester) async {
    await pumpApp(tester);
    final ack = await ackWrite(
      Future<void>.error(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied')),
      action: "Couldn't save task",
    );
    await tester.pump();

    expect(ack, WriteAck.failed);
    expect(find.textContaining("Couldn't save task"), findsOneWidget);
    expect(find.textContaining('permission-denied'), findsOneWidget);
  });

  testWidgets('an unacknowledged write returns queued instead of hanging forever', (tester) async {
    await pumpApp(tester);
    // Offline, Firestore leaves the write future pending indefinitely.
    final never = Completer<void>();
    WriteAck? ack;
    unawaited(ackWrite(never.future, action: "Couldn't save task", timeout: const Duration(seconds: 5))
        .then((v) => ack = v));

    await tester.pump(const Duration(seconds: 4));
    expect(ack, isNull, reason: 'should still be waiting for the server');

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(ack, WriteAck.queued);
    expect(find.textContaining("sync when you're back online"), findsOneWidget);
  });

  testWidgets('a late failure still raises a snackbar after the timeout', (tester) async {
    await pumpApp(tester);
    final pending = Completer<void>();
    unawaited(ackWrite(pending.future, action: "Couldn't save task", timeout: const Duration(seconds: 5)));

    await tester.pump(const Duration(seconds: 6));
    resetErrorSnackDedupe();
    pending.completeError(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('permission-denied'), findsOneWidget);
  });

  testWidgets('a non-queueable write reports a timeout as a real failure', (tester) async {
    await pumpApp(tester);
    final never = Completer<void>();
    WriteAck? ack;
    unawaited(ackWrite(never.future,
            action: "Couldn't update subtask", queueable: false, timeout: const Duration(seconds: 5))
        .then((v) => ack = v));

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();

    expect(ack, WriteAck.failed);
    expect(find.textContaining("Couldn't update subtask"), findsOneWidget);
    expect(find.textContaining("sync when you're back online"), findsNothing);
  });
}
