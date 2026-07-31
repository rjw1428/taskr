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
import 'package:taskr/firebase_options.dart';
import 'package:taskr/home/home.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/goal.service.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
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
  debugPrint('Handling a background message: ${message.data}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
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
    const androidSettings =
        local_notifications.AndroidInitializationSettings('@mipmap/ic_launcher');
    await flutterLocalNotificationsPlugin.initialize(
      const local_notifications.InitializationSettings(android: androidSettings),
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            local_notifications.AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_fcmChannel);
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
      if (message != null && message.data.containsKey('actions')) {
        _showWindTaskDialog(message);
      }
    });

    // Handle when the app is opened from background by tapping on a notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('A new onMessageOpenedApp event was published!');
      if (message.data.containsKey('actions')) {
        _showWindTaskDialog(message);
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
