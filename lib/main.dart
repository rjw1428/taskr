import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as local_notifications;
import 'package:provider/provider.dart';
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
import 'package:taskr/services/recurring_series.service.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/services/theme.provider.dart';
import 'package:taskr/about/about.dart';
import 'package:taskr/notifications/notification_center.dart';
import 'package:taskr/settings/settings.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/theme.dart';
import 'package:taskr/services/task.service.dart';

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

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This isolate starts cold — main() has not run in it. Without a binding
  // there are no platform channels, and without a Firebase app the handler
  // throws before reaching any of our code, silently drawing nothing.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('Firebase already initialized in background isolate: $e');
  }

  debugPrint('Handling a background message: ${message.data}');

  // The prompt has to be drawn locally even with the app terminated, because
  // FCM cannot render the Yes/No action buttons itself. The push is data-only,
  // so if this does not draw it, nothing does.
  if (message.data['type'] == parkingPromptType) {
    try {
      await _initLocalNotifications();
      await showParkingPrompt(message.data);
    } catch (e, s) {
      // A throw here is invisible in release, and the symptom is simply no
      // notification — the hardest possible thing to diagnose from a phone.
      debugPrint('Failed to draw parking prompt: $e\n$s');
    }
  }

  // The result push carries a `notification` block, so Android has already
  // drawn it by the time this runs — nothing to display, but this is the only
  // Dart that sees it while the app is backgrounded, and so the only chance to
  // get the confirmation into the notification centre.
  if (message.data['type'] == parkingResultType) {
    try {
      await recordParkingResult(message.data);
    } catch (e, s) {
      debugPrint('Failed to record parking result: $e\n$s');
    }
  }
}

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
  await _initLocalNotifications();
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
}

/// Initializes the local notifications plugin and its channel. Safe to call
/// from a background isolate, where `main()` has not run.
Future<void> _initLocalNotifications() async {
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

void main() async {
  // Everything runs inside a guarded zone so a write that fails without a local
  // try/catch (most `await service.x()` calls in button handlers) surfaces as an
  // error snackbar instead of dying silently in the console.
  runZonedGuarded(_bootstrap, (error, stack) => reportError(error, stack));
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter error: ${details.exception}');
  };
  // Errors from platform callbacks that never reach the zone handler.
  PlatformDispatcher.instance.onError = (error, stack) {
    reportError(error, stack);
    return true;
  };
  await dotenv.load(fileName: ".env");
  await Workmanager().initialize(parkingCallbackDispatcher);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase already initialized: $e');
  }

  // if (kDebugMode) {
  //   try {
  //     debugPrint('Using local setup');
  //     FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
  //     await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  //   } catch (e) {
  //     debugPrint(e.toString());
  //   }
  // }

  // Handle background messages
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize local notifications for foreground display
  if (!kIsWeb) {
    await _initLocalNotifications();
  }

  runApp(const MyApp());
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

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
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
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message == null) return;
      if (message.data['type'] == parkingPromptType) return;
      if (message.data.containsKey('actions')) {
        _showWindTaskDialog(message);
      }
    });

    // Handle when the app is opened from background by tapping on a notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
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
