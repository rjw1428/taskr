/// An Android-flavoured local notifications fake.
///
/// Under `flutter test` the target platform is Android, and the plugin routes
/// `show` / `initialize` / launch details through
/// `resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()`,
/// which only resolves when the installed platform instance *is* the Android
/// plugin. The harness's base-interface fake therefore never sees those calls.
/// This subclass does, and records them instead of hitting the method channel.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class FakeAndroidNotifications extends AndroidFlutterLocalNotificationsPlugin with MockPlatformInterfaceMixin {
  final List<({int id, String? title, String? body, String? payload, AndroidNotificationDetails? details})> shown =
      [];
  final List<AndroidNotificationChannel> channels = [];
  final List<int> cancelled = [];
  int initializeCalls = 0;

  /// What [getNotificationAppLaunchDetails] reports.
  NotificationAppLaunchDetails? launchDetails;

  /// Makes [show] throw, for exercising callers' failure branches.
  Object? throwOnShow;

  /// The foreground response callback the app registered on [initialize].
  DidReceiveNotificationResponseCallback? onResponse;
  DidReceiveBackgroundNotificationResponseCallback? onBackgroundResponse;

  static FakeAndroidNotifications install() {
    final fake = FakeAndroidNotifications();
    FlutterLocalNotificationsPlatform.instance = fake;
    return fake;
  }

  @override
  Future<bool> initialize(
    AndroidInitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls++;
    onResponse = onDidReceiveNotificationResponse;
    onBackgroundResponse = onDidReceiveBackgroundNotificationResponse;
    return true;
  }

  @override
  Future<void> createNotificationChannel(AndroidNotificationChannel notificationChannel) async =>
      channels.add(notificationChannel);

  @override
  Future<NotificationAppLaunchDetails?> getNotificationAppLaunchDetails() async => launchDetails;

  @override
  Future<void> show(
    int id,
    String? title,
    String? body, {
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    if (throwOnShow != null) throw throwOnShow!;
    shown.add((id: id, title: title, body: body, payload: payload, details: notificationDetails));
  }

  @override
  Future<void> cancel(int id, {String? tag}) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelled.add(-1);
}
