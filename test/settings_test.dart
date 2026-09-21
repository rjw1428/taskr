import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/settings/settings.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> mount(WidgetTester tester) async {
    await pumpApp(tester, const SettingsPage(), size: const Size(400, 1000));
    await settle(tester);
  }

  testWidgets('shows the form when signed in and the login screen when signed out', (tester) async {
    await pumpApp(tester, const SettingsPage());
    await settle(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('No tags yet. Add one to label and group your tasks.'), findsOneWidget);

    env.dispose();
    env = await TestEnv.create(signedIn: false);
    await pumpApp(tester, const SettingsPage());
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the theme segment persists the choice', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Dark'));
    await settle(tester);
    expect((await env.col('settings').doc('preferences').get()).data()?['themeMode'], 'dark');
    await tester.tap(find.text('Light'));
    await settle(tester);
    expect((await env.col('settings').doc('preferences').get()).data()?['themeMode'], 'light');
    await tester.tap(find.text('System'));
    await settle(tester);
    expect((await env.col('settings').doc('preferences').get()).data()?['themeMode'], 'system');
  });

  testWidgets('goal reminders are written to the user doc and read back', (tester) async {
    await env.db.collection('todos').doc(env.uid).set({'goalReminderSchedule': '5pm'}, SetOptions(merge: true));
    await mount(tester);
    final seg = tester.widget<SegmentedButton<GoalReminderSchedule>>(find.byType(SegmentedButton<GoalReminderSchedule>));
    expect(seg.selected, {GoalReminderSchedule.eveningOnly});

    await tester.tap(find.text('Off'));
    await settle(tester);
    expect((await env.userDoc())?['goalReminderSchedule'], 'off');
    await tester.tap(find.text('5 & 9pm'));
    await settle(tester);
    expect((await env.userDoc())?['goalReminderSchedule'], 'both');
  });

  group('Google Calendar', () {
    testWidgets('connects through the calendar sign-in and the exchange callable', (tester) async {
      final exchange = Completer<void>();
      env.functions['exchangeCalendarAuthCode'] = (_) => exchange.future;
      await mount(tester);
      expect(find.text('Not connected'), findsOneWidget);
      await tester.tap(find.text('Connect'));
      await tester.pump();
      // Busy while the callable is in flight.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      exchange.complete();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(env.google.log, contains('signIn:calendar'));
      expect(env.functionCalls.map((c) => c.name), contains('exchangeCalendarAuthCode'));
      expect(find.text('Google Calendar connected'), findsOneWidget);
    });

    testWidgets('a cancelled sign-in is reported', (tester) async {
      env.google.interactive[GoogleSignInProfile.calendar] = null;
      await mount(tester);
      await tester.tap(find.text('Connect'));
      await settle(tester);
      expect(find.textContaining('Could not connect'), findsOneWidget);
      expect(env.functionCalls, isEmpty);
    });

    testWidgets('disconnect asks first, then revokes', (tester) async {
      await env.db.collection('todos').doc(env.uid).set({'calendarConnectedAt': 123}, SetOptions(merge: true));
      await mount(tester);
      expect(find.text('Connected'), findsOneWidget);

      await tester.tap(find.text('Disconnect'));
      await settle(tester);
      expect(find.text('Disconnect Google Calendar?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(env.functionCalls, isEmpty);

      await tester.tap(find.text('Disconnect'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Disconnect')));
      await settle(tester);
      expect(env.functionCalls.single.name, 'disconnectCalendar');
      expect(env.google.log, contains('disconnect:calendar'));
      expect(find.text('Google Calendar disconnected'), findsOneWidget);
    });

    testWidgets('disconnect shows a spinner while the revoke is in flight', (tester) async {
      await env.db.collection('todos').doc(env.uid).set({'calendarConnectedAt': 123}, SetOptions(merge: true));
      final gate = Completer<void>();
      env.functions['disconnectCalendar'] = (_) => gate.future;
      await mount(tester);
      await tester.tap(find.text('Disconnect'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Disconnect')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Disconnect'), findsNothing);

      gate.complete();
      await settle(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Google Calendar disconnected'), findsOneWidget);
    });

    testWidgets('a failed disconnect is reported', (tester) async {
      await env.db.collection('todos').doc(env.uid).set({'calendarConnectedAt': 123}, SetOptions(merge: true));
      env.functions['disconnectCalendar'] = (_) => throw Exception('nope');
      await mount(tester);
      await tester.tap(find.text('Disconnect'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Disconnect')));
      await settle(tester);
      expect(find.textContaining('Could not disconnect'), findsOneWidget);
    });
  });

  group('tags', () {
    setUp(() async {
      await env.col('tags').add({'label': 'Work', 'deleted': false, 'archived': false});
    });

    testWidgets('lists the tags and opens the add and edit dialogs', (tester) async {
      await mount(tester);
      expect(find.text('Work'), findsOneWidget);

      await tester.tap(find.text('Add'));
      await settle(tester);
      expect(find.text('Add tag'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);

      await tester.tap(find.text('Work'));
      await settle(tester);
      expect(find.text('Edit tag'), findsOneWidget);
    });

    testWidgets('deleting a tag asks first and then soft-deletes it', (tester) async {
      await mount(tester);
      await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
      await settle(tester);
      expect(find.text('Delete tag?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Work'), findsOneWidget);

      await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Deleted "Work"'), findsOneWidget);
      final rows = (await env.col('tags').get()).docs;
      expect(rows.single.data()['deleted'], isTrue);
      expect(find.byType(InputChip), findsNothing);
    });

    testWidgets('a failed delete is reported and the tag stays', (tester) async {
      await mount(tester);
      // Losing the session mid-flight makes the provider refuse the write.
      AuthService().user = null;
      await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.textContaining('Could not delete tag'), findsOneWidget);
      expect(find.byType(InputChip), findsOneWidget);
    });
  });
}
