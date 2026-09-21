// The core mocks ship inside the platform interface, which this app only
// depends on transitively; the public `test.dart` entry point is not in the
// pinned version.
// ignore: depend_on_referenced_packages, implementation_imports
import 'package:firebase_core_platform_interface/src/pigeon/mocks.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/main.dart' as app;
import 'package:taskr/services/parking_notifications.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import 'helpers/android_notifications.dart';
import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late FakeAndroidNotifications notifications;
  final messagingCalls = <String>[];

  setUpAll(() {
    setupFirebaseCoreMocks();
    const channel = MethodChannel('plugins.flutter.io/firebase_messaging');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      messagingCalls.add(call.method);
      return null;
    });
  });

  setUp(() async {
    env = await TestEnv.create();
    notifications = FakeAndroidNotifications.install();
    messagingCalls.clear();
  });
  tearDown(() => env.dispose());

  /// Runs the real `main()` and hands back a restorer for the framework error
  /// handler it installs, which must be put back before the test ends.
  Future<void Function()> bootstrap(WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      app.main();
      // .env is read from the asset bundle, which needs the real event loop.
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await settle(tester);
    return () => FlutterError.onError = originalOnError;
  }

  testWidgets('bootstraps the platform and mounts the app', (tester) async {
    final restore = await bootstrap(tester);

    expect(find.byType(app.MyApp), findsOneWidget);
    expect(app.navigatorKey.currentContext, isNotNull);
    expect((WorkmanagerPlatform.instance as FakeWorkmanager).initialized, isTrue);
    expect(notifications.initializeCalls, 1);
    expect(messagingCalls, contains('Messaging#startBackgroundIsolate'));
    expect(FirebaseMessagingPlatform.onBackgroundMessage, isNotNull);
    restore();
  });

  testWidgets('framework and platform errors are surfaced without crashing', (tester) async {
    final restore = await bootstrap(tester);
    final appOnError = FlutterError.onError!;
    final platformOnError = PlatformDispatcher.instance.onError!;
    restore();

    final logs = <String>[];
    final presented = <FlutterErrorDetails>[];
    final previousPrint = debugPrint;
    final previousPresent = FlutterError.presentError;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    FlutterError.presentError = presented.add;
    try {
      appOnError(FlutterErrorDetails(exception: Exception('render boom')));
    } finally {
      debugPrint = previousPrint;
      FlutterError.presentError = previousPresent;
    }
    expect(logs, contains(contains('Flutter error: Exception: render boom')));
    // The framework's own presenter still runs, so the red box / console dump
    // is not lost to the extra logging.
    expect(presented.single.exception.toString(), contains('render boom'));

    expect(platformOnError(Exception('platform boom'), StackTrace.current), isTrue);
    await settle(tester);
    expect(find.textContaining('platform boom'), findsOneWidget);
  });

  group('background message handler', () {
    Future<BackgroundMessageHandler> handler(WidgetTester tester) async {
      if (FirebaseMessagingPlatform.onBackgroundMessage == null) {
        (await bootstrap(tester))();
      }
      return FirebaseMessagingPlatform.onBackgroundMessage!;
    }

    testWidgets('draws the parking prompt for a data-only push', (tester) async {
      final handle = await handler(tester);
      notifications.shown.clear();
      await tester.runAsync(() => handle(const RemoteMessage(data: {'type': parkingPromptType, 'title': 'Pay?'})));
      expect(notifications.shown.single.title, 'Pay?');
      expect(notifications.shown.single.payload, parkingPromptPayload);
    });

    testWidgets('a failure to draw the prompt is swallowed', (tester) async {
      final handle = await handler(tester);
      notifications.throwOnShow = Exception('no channel');
      await tester.runAsync(() => handle(const RemoteMessage(data: {'type': parkingPromptType})));
      expect(notifications.shown, isEmpty);
    });

    testWidgets('records the parking result in the inbox without drawing', (tester) async {
      final handle = await handler(tester);
      notifications.shown.clear();
      await tester.runAsync(() => handle(const RemoteMessage(data: {'type': parkingResultType, 'status': 'skipped'})));
      final rows = (await env.col('notifications').get()).docs;
      expect(rows.single.data()['title'], 'Parking already active');
      expect(notifications.shown, isEmpty);
    });

    testWidgets('a malformed result push is swallowed', (tester) async {
      final handle = await handler(tester);
      await tester.runAsync(() => handle(const RemoteMessage(data: {'type': parkingResultType, 'title': 42})));
      expect((await env.col('notifications').get()).docs, isEmpty);
    });

    testWidgets('other pushes are ignored', (tester) async {
      final handle = await handler(tester);
      notifications.shown.clear();
      await tester.runAsync(() => handle(const RemoteMessage(data: {'type': 'task_reminder'})));
      expect(notifications.shown, isEmpty);
    });
  });
}
