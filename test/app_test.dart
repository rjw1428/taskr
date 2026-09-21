import 'dart:convert';

// The core mocks ship inside the platform interface, which this app only
// depends on transitively; the public `test.dart` entry point is not in the
// pinned version.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/app.dart';
import 'package:taskr/notifications/notification_center.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/settings/settings.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/about/about.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import 'helpers/android_notifications.dart';
import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late FakeAndroidNotifications notifications;

  setUpAll(setupFirebaseCoreMocks);
  setUp(() async {
    env = await TestEnv.create();
    notifications = FakeAndroidNotifications.install();
  });
  tearDown(() => env.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp());
    await settle(tester);
  }

  group('home-screen shortcuts', () {
    testWidgets('the three shortcuts are registered with the launcher', (tester) async {
      await mount(tester);
      expect(FakeQuickActions.current.items.map((i) => i.type),
          [addTaskShortcutType, addBacklogShortcutType, notificationsShortcutType]);
      expect(FakeQuickActions.current.handler, isNotNull);
    });

    testWidgets('add-task and add-to-backlog open the form for the right list', (tester) async {
      await mount(tester);
      FakeQuickActions.current.fire(addTaskShortcutType);
      await settle(tester);
      expect(tester.widget<AddTaskScreen>(find.byType(AddTaskScreen)).isBacklog, isFalse);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      FakeQuickActions.current.fire(addBacklogShortcutType);
      await settle(tester);
      expect(tester.widget<AddTaskScreen>(find.byType(AddTaskScreen)).isBacklog, isTrue);
    });

    testWidgets('the notifications shortcut opens the inbox', (tester) async {
      await mount(tester);
      FakeQuickActions.current.fire(notificationsShortcutType);
      await settle(tester);
      expect(find.byType(NotificationCenterPage), findsOneWidget);
    });

    testWidgets('an unknown shortcut type does nothing', (tester) async {
      await mount(tester);
      FakeQuickActions.current.fire('bogus');
      await settle(tester);
      expect(find.byType(AddTaskScreen), findsNothing);
      expect(find.byType(NotificationCenterPage), findsNothing);
    });
  });

  group('shell', () {
    testWidgets('mounts the home screen and runs the launch pass once auth resolves', (tester) async {
      // A series created today is materialized to the horizon; a launch pass
      // that sees a later "today" has to extend it. Nothing else does.
      final written = await TaskService().createRecurringSeries(
        RecurringTask(
          recurrenceType: 'Daily',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 365)),
        ),
        Task(added: 1, title: 'standup', completed: false),
      );
      Future<Set<String?>> datesCovered() async =>
          (await TaskService().seriesInstances(written.templateId))!.map((t) => t.dueDate).toSet();
      final before = await datesCovered();
      RecurringSeriesService().clock = () => DateTime.now().add(const Duration(days: 10));

      await mount(tester);
      expect(find.text('List'), findsWidgets);
      expect(AuthService().user?.uid, env.uid);
      expect((await env.userDoc())!['fcmToken'], 'fcm-token');
      final after = await datesCovered();
      expect(after.length, before.length + 10);
      expect(after.containsAll(before), isTrue);
    });

    testWidgets('the route table resolves every named page', (tester) async {
      await mount(tester);
      final nav = navigatorKey.currentState!;

      nav.pushNamed('/settings');
      await settle(tester);
      expect(find.byType(SettingsPage), findsOneWidget);

      nav.pushNamed('/about');
      await settle(tester);
      expect(find.byType(AboutPage), findsOneWidget);

      nav.pushNamed('/notifications');
      await settle(tester);
      expect(find.byType(NotificationCenterPage), findsOneWidget);

      nav.pushNamed('/nowhere');
      await settle(tester);
      expect(find.text('Unknown main route'), findsOneWidget);
    });

    testWidgets('follows the persisted theme mode', (tester) async {
      await env.col('settings').doc('preferences').set({'themeMode': 'dark'});
      await mount(tester);
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.title, 'Taskr: To-Do App');
    });
  });

  group('foreground messages', () {
    testWidgets('a task reminder opens a dialog that can be dismissed', (tester) async {
      await mount(tester);
      env.push.onMessageController.add(const RemoteMessage(data: {'type': 'task_reminder', 'title': 'Call mum'}));
      await settle(tester);
      expect(find.text('Reminder'), findsOneWidget);
      expect(find.text('Call mum'), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await settle(tester);
      expect(find.text('Reminder'), findsNothing);

      env.push.onMessageController.add(const RemoteMessage(data: {'type': 'task_reminder'}));
      await settle(tester);
      expect(find.text('You have a task reminder'), findsOneWidget);
    });

    testWidgets('a parking prompt is drawn as an actionable notification', (tester) async {
      await mount(tester);
      env.push.onMessageController.add(const RemoteMessage(data: {
        'type': parkingPromptType,
        'title': 'Pay?',
        'body': 'Train leaving',
        'actions': '[]',
      }));
      await settle(tester);
      expect(notifications.shown, hasLength(1));
      final shown = notifications.shown.single;
      expect(shown.title, 'Pay?');
      expect(shown.body, 'Train leaving');
      expect(shown.payload, parkingPromptPayload);
      expect(shown.details?.actions?.map((a) => a.id), [payParkingAction, dismissParkingAction]);
      // Not a wind task, so no dialog.
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a parking result is drawn and recorded in the inbox', (tester) async {
      await mount(tester);
      env.push.onMessageController.add(const RemoteMessage(data: {'type': parkingResultType, 'status': 'paid'}));
      await settle(tester);
      expect(notifications.shown.single.title, 'Parking paid');
      final rows = (await env.col('notifications').get()).docs;
      expect(rows.single.data()['title'], 'Parking paid');
      expect(rows.single.data()['type'], 'parking_result');
    });

    testWidgets('a wind alert with JSON actions offers to add the task', (tester) async {
      await mount(tester);
      env.push.onMessageController.add(RemoteMessage(data: {
        'title': 'Wind Alert',
        'body': 'Gusts to 50mph',
        'date': '2026-09-20',
        'startHour': '08:00',
        'endHour': '10:00',
        'actions': jsonEncode([
          {'title': 'Add task', 'action': 'add-wind-task'},
          {'title': 'Ignore', 'action': 'ignore'},
        ]),
      }));
      await settle(tester);
      expect(find.text('Wind Alert'), findsOneWidget);
      expect(find.text('Gusts to 50mph'), findsOneWidget);

      await tester.tap(find.text('Add task'));
      await settle(tester);
      expect(find.text('Wind Alert'), findsNothing);
      final items = (await env.col('tasks').doc('2026-09-20').collection('items').get()).docs;
      expect(items.single.data()['title'], 'Batten Down Christmas Decorations');
      expect(items.single.data()['description'], 'Gusts to 50mph');
      expect(items.single.data()['startTime'], '08:00');
    });

    testWidgets('a wind alert with list actions falls back to defaults and ignores other actions', (tester) async {
      await mount(tester);
      env.push.onMessageController.add(const RemoteMessage(data: {
        'actions': [
          {'action': 'ignore'},
        ],
      }));
      await settle(tester);
      expect(find.text('Wind Alert'), findsOneWidget);
      await tester.tap(find.text('Action'));
      await settle(tester);
      expect(find.text('Wind Alert'), findsNothing);
      expect((await env.db.collectionGroup('items').get()).docs, isEmpty);
    });

    testWidgets('malformed or non-list actions still show the alert without buttons', (tester) async {
      await mount(tester);
      env.push.onMessageController.add(const RemoteMessage(data: {'title': 'Storm', 'actions': 'not json'}));
      await settle(tester);
      expect(find.text('Storm'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);

      env.push.onMessageController.add(const RemoteMessage(data: {'title': 'Storm 2', 'actions': '{"a":1}'}));
      await settle(tester);
      expect(find.text('Storm 2'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('a plain notification is shown through the system tray', (tester) async {
      await mount(tester);
      env.push.onMessageController.add(const RemoteMessage(
        data: {'foo': 'bar'},
        notification: RemoteNotification(title: 'Hello', body: 'World'),
      ));
      await settle(tester);
      expect(notifications.shown.single.title, 'Hello');
      expect(notifications.shown.single.body, 'World');
      // The launcher icon is an Android resource name; a wrong one draws nothing.
      expect(notifications.shown.single.details?.icon, '@mipmap/ic_launcher');

      env.push.onMessageController.add(const RemoteMessage(data: {'foo': 'bar'}));
      await settle(tester);
      expect(notifications.shown, hasLength(1));
    });
  });

  group('opened from a notification', () {
    testWidgets('an initial wind message shows the dialog on launch', (tester) async {
      env.push.initialMessage = const RemoteMessage(data: {
        'title': 'Launch wind',
        'actions': [
          {'title': 'Ok', 'action': 'ignore'},
        ],
      });
      await mount(tester);
      expect(find.text('Launch wind'), findsOneWidget);
    });

    testWidgets('an initial parking prompt or plain message does nothing', (tester) async {
      env.push.initialMessage = const RemoteMessage(data: {'type': parkingPromptType, 'actions': '[]'});
      await mount(tester);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('onMessageOpenedApp shows wind dialogs and skips parking prompts', (tester) async {
      await mount(tester);
      env.push.onMessageOpenedAppController.add(const RemoteMessage(data: {'type': parkingPromptType, 'actions': '[]'}));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);

      env.push.onMessageOpenedAppController.add(const RemoteMessage(data: {'title': 'Opened wind', 'actions': '[]'}));
      await settle(tester);
      expect(find.text('Opened wind'), findsOneWidget);

      env.push.onMessageOpenedAppController.add(const RemoteMessage(data: {'x': 'y'}));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('a cold start from the parking prompt body asks again in-app', (tester) async {
      notifications.launchDetails = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: parkingPromptPayload,
        ),
      );
      await mount(tester);
      expect(find.text('Pay for parking?'), findsOneWidget);
      await tester.tap(find.text('No'));
      await settle(tester);
      expect(find.text('Pay for parking?'), findsNothing);
    });

    testWidgets('a cold start from a parking action button is not re-asked', (tester) async {
      notifications.launchDetails = const NotificationAppLaunchDetails(
        true,
        notificationResponse: NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          payload: parkingPromptPayload,
          actionId: payParkingAction,
        ),
      );
      await mount(tester);
      expect(find.text('Pay for parking?'), findsNothing);
    });
  });

  group('notification responses', () {
    testWidgets('initLocalNotifications registers the handlers and channel', (tester) async {
      await initLocalNotifications();
      expect(notifications.initializeCalls, 1);
      expect(notifications.channels.single.id, 'fcm_default_channel');
      expect(notifications.onResponse, isNotNull);
      expect(notifications.onBackgroundResponse, same(notificationBackgroundResponseHandler));
    });

    testWidgets('a foreground Yes queues the purchase; No does nothing', (tester) async {
      await mount(tester);
      await initLocalNotifications();
      final work = WorkmanagerPlatform.instance as FakeWorkmanager;

      notifications.onResponse!(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: payParkingAction,
      ));
      await settle(tester);
      expect(work.registered.single.taskName, 'parking-pay');

      notifications.onResponse!(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: dismissParkingAction,
      ));
      await settle(tester);
      expect(work.registered, hasLength(1));
      await settle(tester);
      expect(find.text('Pay for parking?'), findsNothing);
    });

    testWidgets('a foreground body tap re-asks in-app and Yes triggers the purchase', (tester) async {
      await mount(tester);
      await initLocalNotifications();

      notifications.onResponse!(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: parkingPromptPayload,
      ));
      // The dialog is deferred to the next frame; nothing else is dirty, so
      // ask for one the way the foregrounding app would.
      await tester.pump();
      tester.binding.scheduleFrame();
      await settle(tester);
      expect(find.text('Pay for parking?'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      // The service is unreachable under test; the retries are backed off, so
      // step through until the outcome snackbar appears.
      var sawSnack = false;
      for (var i = 0; i < 40 && !sawSnack; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        sawSnack = find.byType(SnackBar).evaluate().isNotEmpty;
      }
      expect(sawSnack, isTrue);
      final rows = (await env.col('notifications').get()).docs;
      expect(rows.single.data()['title'], 'Parking NOT paid');
    });

    testWidgets('a body tap before the app has a navigator is logged and dropped', (tester) async {
      await initLocalNotifications();
      final logs = <String>[];
      final previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      try {
        notifications.onResponse!(const NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotification,
          payload: parkingPromptPayload,
        ));
        await tester.pump();
        tester.binding.scheduleFrame();
        await settle(tester);
      } finally {
        // Foundation debug variables must be back to normal before the test ends.
        debugPrint = previousPrint;
      }
      expect(logs, contains('Cannot show parking dialog without a context'));
    });

    testWidgets('a body tap with another payload is ignored', (tester) async {
      await mount(tester);
      await initLocalNotifications();
      notifications.onResponse!(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'something-else',
      ));
      await tester.pump();
      tester.binding.scheduleFrame();
      await settle(tester);
      expect(find.text('Pay for parking?'), findsNothing);
    });

    testWidgets('the background handler bootstraps and queues the purchase', (tester) async {
      final work = WorkmanagerPlatform.instance as FakeWorkmanager;
      await notificationBackgroundResponseHandler(const NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: payParkingAction,
      ));
      expect(work.initialized, isTrue);
      expect(notifications.initializeCalls, 1);
      expect(work.registered.single.taskName, 'parking-pay');
    });
  });
}
