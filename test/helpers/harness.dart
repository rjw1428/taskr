/// Shared test harness: fakes for every platform boundary the app touches, and
/// a `pumpApp` that mounts a screen with the same providers and theme as
/// production.
///
/// Typical use:
///
/// ```dart
/// late TestEnv env;
/// setUp(() async => env = await TestEnv.create());
/// tearDown(() => env.dispose());
///
/// testWidgets('...', (tester) async {
///   await env.db.collection('todos').doc(env.uid).collection('tasks')...;
///   await pumpApp(tester, const TaskListScreen());
///   ...
/// });
/// ```
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:quick_actions_platform_interface/quick_actions_platform_interface.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/firebase_refs.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/services/push_gateway.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/services/theme.provider.dart';
import 'package:taskr/shared/error_reporting.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/theme.dart';
import 'package:workmanager/workmanager.dart';

export 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
export 'package:firebase_auth_mocks/firebase_auth_mocks.dart';

/// Everything a test needs to stand in for the platform. [create] installs the
/// fakes into the app's override points and resets every singleton service so
/// no state leaks between tests.
class TestEnv {
  TestEnv._({required this.db, required this.auth, required this.uid, required this.push, required this.google});

  final FakeFirebaseFirestore db;
  final MockFirebaseAuth auth;
  final String uid;
  final FakePushGateway push;
  final FakeGoogleSignIn google;

  /// Cloud Functions calls made through [FirebaseRefs.callFunction], in order.
  final List<({String name, dynamic payload})> functionCalls = [];

  /// Handlers for named callables. A callable without a handler resolves to null.
  final Map<String, FutureOr<dynamic> Function(dynamic payload)> functions = {};

  static Future<TestEnv> create({
    String uid = 'u1',
    String email = 'test@example.com',
    bool signedIn = true,
    Map<String, String> env = const {},
  }) async {
    resetSingletons();
    final db = FakeFirebaseFirestore();
    final user = MockUser(uid: uid, email: email);
    final auth = MockFirebaseAuth(signedIn: signedIn, mockUser: user);
    final push = FakePushGateway();
    final google = FakeGoogleSignIn();
    final t = TestEnv._(db: db, auth: auth, uid: uid, push: push, google: google);

    FirebaseRefs.override(
      firestore: db,
      auth: auth,
      callFunction: (name, payload) async {
        t.functionCalls.add((name: name, payload: payload));
        final handler = t.functions[name];
        return handler == null ? null : await handler(payload);
      },
    );
    PushGateway.override = push;
    GoogleSignInGateway.override = google;
    FlutterLocalNotificationsPlatform.instance = FakeLocalNotifications();
    // The plugin's first construction installs the host platform implementation
    // over whatever is set, so trigger that once before installing the fake.
    Workmanager();
    WorkmanagerPlatform.instance = FakeWorkmanager();
    QuickActionsPlatform.instance = FakeQuickActions();
    dotenv.testLoad(fileInput: {
      'WEB_CLIENT_ID': 'web-client',
      'CALENDAR_WEB_CLIENT_ID': 'cal-client',
      'GEMINI_API_KEY': 'gemini-key',
      'PARKING_TRIGGER_TOKEN': 'parking-token',
      ...env,
    }.entries.map((e) => '${e.key}=${e.value}').join('\n'));
    GoogleFonts.config.allowRuntimeFetching = false;
    resetErrorSnackDedupe();

    if (signedIn) {
      // Mirrors what a real first login writes; screens read the user doc.
      await db.collection('todos').doc(uid).set({'email': email, 'currentScore': 0});
    }
    return t;
  }

  /// A user doc field, for asserting on writes such as the FCM token.
  Future<Map<String, dynamic>?> userDoc() async => (await db.collection('todos').doc(uid).get()).data();

  CollectionReference<Map<String, dynamic>> col(String name) => db.collection('todos').doc(uid).collection(name);

  void dispose() {
    FirebaseRefs.reset();
    PushGateway.override = null;
    GoogleSignInGateway.override = null;
    resetSingletons();
  }

  /// Drops every singleton service's state so a `late` field bound to a previous
  /// test's fake is not reused.
  static void resetSingletons() {
    AuthService.resetInstance();
    DateService.resetInstance();
    JournalService.resetInstance();
    AIService.resetInstance();
    PerformanceService.resetInstance();
    CalendarService.resetInstance();
    RecurringSeriesService.resetInstance();
    ReminderService.resetInstance();
    HealthService.resetInstance();
    RecurringSeriesService.resetPassGuard();
    HabitService.resetLaunchGuard();
  }
}

/// Mounts [child] the way production does: providers, theme, scaffold
/// messenger key. Pass [wrapInScaffold] for bare widgets that need a Material
/// ancestor.
Future<void> pumpApp(
  WidgetTester tester,
  Widget child, {
  bool wrapInScaffold = false,
  Size size = const Size(400, 800),
  List<SingleChildWidget> extraProviders = const [],
  ThemeMode themeMode = ThemeMode.light,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<TagProvider>(create: (_) => TagProvider()),
        ChangeNotifierProvider<AccomplishmentProvider>(create: (_) => AccomplishmentProvider()),
        ChangeNotifierProvider<GoalService>(create: (_) => GoalService()),
        ChangeNotifierProvider<PeopleProvider>(create: (_) => PeopleProvider()),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ...extraProviders,
      ],
      child: MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        home: wrapInScaffold ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}

/// Pumps a handful of frames so streams deliver and reveal animations finish,
/// without `pumpAndSettle`, which never returns while an indeterminate
/// progress indicator is on screen.
Future<void> settle(WidgetTester tester, {int frames = 6, Duration step = const Duration(milliseconds: 100)}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

class FakePushGateway implements PushGateway {
  String? token = 'fcm-token';
  int permissionRequests = 0;
  bool? autoInit;
  RemoteMessage? initialMessage;
  final onTokenRefreshController = StreamController<String>.broadcast();
  final onMessageController = StreamController<RemoteMessage>.broadcast();
  final onMessageOpenedAppController = StreamController<RemoteMessage>.broadcast();

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => onTokenRefreshController.stream;

  @override
  Stream<RemoteMessage> get onMessage => onMessageController.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => onMessageOpenedAppController.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initialMessage;

  @override
  Future<void> setAutoInitEnabled(bool enabled) async => autoInit = enabled;
}

class FakeGoogleSignIn implements GoogleSignInGateway {
  /// What [signIn] returns per profile; null means the user cancelled.
  final Map<GoogleSignInProfile, GoogleAuthResult?> interactive = {
    GoogleSignInProfile.login: const GoogleAuthResult(accessToken: 'at', idToken: 'it', email: 'test@example.com'),
    GoogleSignInProfile.calendar:
        const GoogleAuthResult(accessToken: 'cal-at', serverAuthCode: 'code', email: 'test@example.com'),
  };
  final Map<GoogleSignInProfile, GoogleAuthResult?> silent = {};
  final List<String> log = [];
  Object? throwOnDisconnect;
  Object? throwOnSignOut;

  @override
  Future<GoogleAuthResult?> signIn(GoogleSignInProfile profile) async {
    log.add('signIn:${profile.name}');
    return interactive[profile];
  }

  @override
  Future<GoogleAuthResult?> signInSilently(GoogleSignInProfile profile) async {
    log.add('silent:${profile.name}');
    return silent[profile];
  }

  @override
  Future<void> signOut(GoogleSignInProfile profile) async {
    log.add('signOut:${profile.name}');
    if (throwOnSignOut != null) throw throwOnSignOut!;
  }

  @override
  Future<void> disconnect(GoogleSignInProfile profile) async {
    log.add('disconnect:${profile.name}');
    if (throwOnDisconnect != null) throw throwOnDisconnect!;
  }
}

/// Records notifications instead of drawing them. Under `flutter test` the
/// target platform is Android, and the plugin's Android-only calls resolve to
/// null and no-op, so only the base interface needs a fake.
class FakeLocalNotifications extends FlutterLocalNotificationsPlatform with MockPlatformInterfaceMixin {
  final List<({int id, String? title, String? body, String? payload})> shown = [];
  final List<int> cancelled = [];

  @override
  Future<void> show(int id, String? title, String? body, {String? payload}) async =>
      shown.add((id: id, title: title, body: body, payload: payload));

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelled.add(-1);
}

class FakeWorkmanager extends WorkmanagerPlatform with MockPlatformInterfaceMixin {
  final List<({String uniqueName, String taskName, Map<String, dynamic>? inputData, Duration? backoffDelay})>
      registered = [];
  bool initialized = false;

  @override
  Future<void> initialize(Function callbackDispatcher, {bool isInDebugMode = false}) async => initialized = true;

  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async =>
      registered.add(
          (uniqueName: uniqueName, taskName: taskName, inputData: inputData, backoffDelay: backoffPolicyDelay));
}

/// Captures the home-screen shortcut handler so a test can fire a shortcut the
/// way the OS would, and records the items the app registers.
class FakeQuickActions extends QuickActionsPlatform with MockPlatformInterfaceMixin {
  static FakeQuickActions get current => QuickActionsPlatform.instance as FakeQuickActions;

  QuickActionHandler? handler;
  List<ShortcutItem> items = const [];

  @override
  Future<void> initialize(QuickActionHandler handler) async => this.handler = handler;

  @override
  Future<void> setShortcutItems(List<ShortcutItem> items) async => this.items = items;

  @override
  Future<void> clearShortcutItems() async => items = const [];

  /// Fires [type] as if the user tapped that shortcut on the launcher.
  void fire(String type) => handler!(type);
}
