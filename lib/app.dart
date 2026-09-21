import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as local_notifications;
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:workmanager/workmanager.dart';
import 'package:taskr/firebase_options.dart';
import 'package:taskr/home/home.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/goal.service.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/parking_notifications.dart';
import 'package:taskr/services/parking_work.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/services/push_gateway.dart';
import 'package:taskr/services/recurring_series.service.dart';
import 'package:taskr/services/reminder.service.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/services/theme.provider.dart';
import 'package:taskr/about/about.dart';
import 'package:taskr/notifications/notification_center.dart';
import 'package:taskr/settings/settings.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/theme.dart';
import 'package:taskr/services/task.service.dart';
import 'package:taskr/task_list/add_task.dart';

/// The widget tree and the foreground notification plumbing. `main.dart` holds
/// only the process bootstrap (Firebase init, background isolates), so this
/// file can be mounted in a widget test against the fake gateways.

// Global navigator key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final local_notifications.FlutterLocalNotificationsPlugin
    flutterLocalNotificationsPlugin =
    local_notifications.FlutterLocalNotificationsPlugin();

const local_notifications.AndroidNotificationChannel _fcmChannel =
    local_notifications.AndroidNotificationChannel(
  'fcm_default_channel',
  'Taskr Notifications',
  description: 'Notifications from Taskr',
  importance: local_notifications.Importance.high,
);

/// Runs when the user taps a notification action while the app is not running.
///
/// Must be a top-level entry point: a closure or instance method would not
/// survive the isolate boundary. Like the FCM background handler, this isolate
/// starts cold — it needs a binding before any platform channel works, and the
/// returned future must be awaited by the caller or the isolate can be torn
/// down before the network call it starts has finished.
@pragma('vm:entry-point')
Future<void> notificationBackgroundResponseHandler(
  local_notifications.NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase already initialized in action isolate: $e');
  }
  // The plugin has never been initialized in this isolate, and the handler
  // reports its outcome by showing a notification.
  await initLocalNotifications();
  // The purchase itself is queued, not run here: this isolate is hosted by a
  // BroadcastReceiver with no guaranteed lifetime.
  await Workmanager().initialize(parkingCallbackDispatcher);
  debugPrint('Notification action (background): ${response.actionId}');
  await handleParkingAction(response.actionId);
}

Future<void> _onNotificationResponse(
  local_notifications.NotificationResponse response,
) async {
  debugPrint('Notification action (foreground): ${response.actionId}');
  if (await handleParkingAction(response.actionId)) return;

  // No action id means the body was tapped, which only opens the app. Ask the
  // question again in-app rather than stranding the user with no way to answer.
  if (response.payload == parkingPromptPayload) {
    _promptForParkingInApp();
  }
}

/// Home-screen shortcuts (long-press the app icon).
const addTaskShortcutType = 'add_task';
const addBacklogShortcutType = 'add_backlog';
const notificationsShortcutType = 'notifications';

/// Runs [action] once the user is signed in and a route exists to host it. A
/// cold launch from a shortcut fires before auth has resolved, so this waits
/// for the first signed-in user rather than acting over the loading/login
/// screen.
void _whenReadyForShortcut(void Function(BuildContext context) action) {
  // Not `firstWhere`: the auth stream replays its cached user synchronously on
  // subscribe, and `firstWhere`/`first` attach their data handler only after
  // subscribing, so on an already-running app the replayed user was dropped and
  // the shortcut silently did nothing. `take(1).listen` hands the handler in
  // with the subscription, so the replay is caught, and cancels itself after.
  AuthService().userStream.skipWhile((u) => u == null).take(1).listen((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context == null) {
        debugPrint('Cannot handle shortcut without a context');
        return;
      }
      action(context);
    });
    // A post-frame callback only runs when a frame runs; an idle app may not
    // have one coming, so ask for it.
    WidgetsBinding.instance.ensureVisualUpdate();
  });
}

void _handleShortcut(String type) {
  switch (type) {
    case addTaskShortcutType:
    case addBacklogShortcutType:
      _whenReadyForShortcut((context) => showModalBottomSheet(
            isScrollControlled: true,
            useSafeArea: true,
            context: context,
            builder: (_) =>
                AddTaskScreen(isBacklog: type == addBacklogShortcutType),
          ));
    case notificationsShortcutType:
      _whenReadyForShortcut(
          (context) => Navigator.of(context).pushNamed('/notifications'));
  }
}

/// Shows the parking dialog once a route is available to host it.
void _promptForParkingInApp() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('Cannot show parking dialog without a context');
      return;
    }
    showParkingPromptDialog(context);
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// Initializes the local notifications plugin and its channel. Safe to call
/// from a background isolate, where `main()` has not run.
Future<void> initLocalNotifications() async {
  const androidSettings =
      local_notifications.AndroidInitializationSettings('@mipmap/ic_launcher');
  await flutterLocalNotificationsPlugin.initialize(
    const local_notifications.InitializationSettings(android: androidSettings),
    onDidReceiveNotificationResponse: _onNotificationResponse,
    onDidReceiveBackgroundNotificationResponse:
        notificationBackgroundResponseHandler,
  );
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          local_notifications.AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_fcmChannel);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Method to show the wind task dialog
  void _showWindTaskDialog(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint("Cannot show dialog without a context");
      return;
    }

    final data = message.data;
    List<Map<String, dynamic>> actions = [];

    // Try to parse 'actions' as a JSON string first
    if (data['actions'] is String) {
      try {
        final decodedActions = jsonDecode(data['actions'] as String);
        if (decodedActions is List) {
          actions = decodedActions.map((e) => e as Map<String, dynamic>).toList();
        }
      } catch (e) {
        debugPrint("Error parsing actions string: $e");
      }
    } else if (data['actions'] is List) {
      // If it's already a List (e.g., from a different source than FCM data messages)
      actions = (data['actions'] as List).map((e) => e as Map<String, dynamic>).toList();
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text(data['title'] ?? 'Wind Alert'),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(
                  data['body'] ?? '',
                  style: Theme.of(dialogContext).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          actions: actions.map((action) {
            return TextButton(
              child: Text(action['title'] ?? 'Action'),
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (action['action'] == 'add-wind-task') {
                  final payloadMap = Map<String, dynamic>.from(data);
                  final task = Task(
                      title: "Batten Down Christmas Decorations",
                      description: payloadMap['body'],
                      startTime: payloadMap['startHour'],
                      endTime: payloadMap['endHour'],
                      priority: Effort.low,
                      completed: false,
                      dueDate: payloadMap['date'],
                      pushCount: 0,
                      added: DateTime.now().millisecondsSinceEpoch,
                      tags: [],
                      );
                  await TaskService().addTask(task);
                }
              },
            );
          }).toList(),
        );
      },
    );
  }

  void _showReminderDialog(RemoteMessage message) {
    final context = navigatorKey.currentContext;
    if (context == null || !mounted) return;

    final data = message.data;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Reminder'),
          content: Text(data['title'] ?? 'You have a task reminder'),
          actions: [
            TextButton(
              child: const Text('Dismiss'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        );
      },
    );
  }

  void _showSystemNotification(RemoteNotification notification) {
    flutterLocalNotificationsPlugin.show(
      notification.hashCode,
      notification.title,
      notification.body,
      local_notifications.NotificationDetails(
        android: local_notifications.AndroidNotificationDetails(
          _fcmChannel.id,
          _fcmChannel.name,
          channelDescription: _fcmChannel.description,
          importance: local_notifications.Importance.high,
          priority: local_notifications.Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      debugPrint('Skipping cloud messaging for web');
      return;
    }

    const quickActions = QuickActions();
    quickActions.initialize(_handleShortcut);
    quickActions.setShortcutItems(const [
      ShortcutItem(
        type: addTaskShortcutType,
        localizedTitle: 'Add task',
        icon: 'ic_launcher',
      ),
      ShortcutItem(
        type: addBacklogShortcutType,
        localizedTitle: 'Add to backlog',
        icon: 'ic_launcher',
      ),
      ShortcutItem(
        type: notificationsShortcutType,
        localizedTitle: 'Notifications',
        icon: 'ic_launcher',
      ),
    ]);

    final push = PushGateway.instance;
    push.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.data['type'] == 'task_reminder') {
        _showReminderDialog(message);
      } else if (message.data['type'] == parkingPromptType) {
        // Checked before the generic `actions` branch below: the parking prompt
        // also carries an `actions` payload, but it is not a wind task.
        showParkingPrompt(message.data);
      } else if (message.data['type'] == parkingResultType) {
        showParkingResult(message.data);
      } else if (message.data.containsKey('actions')) {
        _showWindTaskDialog(message);
      } else {
        final notification = message.notification;
        if (notification != null) {
          debugPrint('Message also contained a notification: $notification');
          _showSystemNotification(notification);
        }
      }
    });

    // Handle when the app is opened from a terminated state via a notification
    push.getInitialMessage().then((RemoteMessage? message) {
      if (message == null) return;
      if (message.data['type'] == parkingPromptType) return;
      if (message.data.containsKey('actions')) {
        _showWindTaskDialog(message);
      }
    });

    // Handle when the app is opened from background by tapping on a notification
    push.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      if (message.data['type'] == parkingPromptType) return;
      if (message.data.containsKey('actions')) {
        _showWindTaskDialog(message);
      }
    });

    // Recurring series are materialized on a rolling 60-day horizon, so something
    // has to extend them. Recurring tasks have no owning screen (habits piggyback
    // on the goals tab), and the task list is the hot screen — so the pass runs
    // here, once, when auth resolves. It also enqueues reminders that have come
    // into the Cloud Tasks window.
    AuthService().userStream.listen((user) {
      if (user == null) return;
      RecurringSeriesService().runLaunchPass();
      // One-off tasks have no series to top them up, so their reminders get the
      // same treatment here: a reminder set further out than Cloud Tasks accepts
      // is scheduled by the first launch that finds it inside the window.
      ReminderService().topUpPendingReminders();
    });

    // Cold start: the app was launched by tapping the prompt itself, so the tap
    // arrives as launch details rather than a live callback. An actionId here
    // means a button was used, and that is queued as WorkManager work instead.
    flutterLocalNotificationsPlugin.getNotificationAppLaunchDetails().then((d) {
      final response = d?.notificationResponse;
      if (d?.didNotificationLaunchApp == true &&
          response?.payload == parkingPromptPayload &&
          response?.actionId == null) {
        _promptForParkingInApp();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        StreamProvider<User?>.value(
          value: AuthService().userStream,
          initialData: null,
        ),
        ChangeNotifierProvider<TagProvider>(
          create: (_) => TagProvider(),
        ),
        ChangeNotifierProvider<AccomplishmentProvider>(
          create: (_) => AccomplishmentProvider(),
        ),
        ChangeNotifierProvider<GoalService>(
          create: (_) => GoalService(),
        ),
        ChangeNotifierProvider<PeopleProvider>(
          create: (_) => PeopleProvider(),
        ),
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          navigatorKey: navigatorKey, // Set the navigator key
          scaffoldMessengerKey: scaffoldMessengerKey, // lets services surface write errors
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeProvider.mode,
          title: 'Taskr: To-Do App',
          initialRoute: '/',
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case '/':
                return MaterialPageRoute(builder: (_) => const HomeScreen());
              case '/settings':
                return MaterialPageRoute(builder: (_) => const SettingsPage());
              case '/about':
                return MaterialPageRoute(builder: (_) => const AboutPage());
              case '/notifications':
                return MaterialPageRoute(builder: (_) => const NotificationCenterPage());
              default:
                return MaterialPageRoute(builder: (_) => const Text("Unknown main route"));
            }
          },
        ),
      ),
    );
  }
}
