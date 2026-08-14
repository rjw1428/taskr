import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/services.dart';

class FirebaseMessageService {
  final _fbMessaging = FirebaseMessaging.instance;
  bool init = false;
  Future<void> initNotifiactions() async {
    final settings = await _fbMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: true,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('User granted permission: ${settings.authorizationStatus}');
    final fcmToken = await _fbMessaging.getToken();
    debugPrint("TOKEN: $fcmToken");

    await FirebaseMessaging.instance.setAutoInitEnabled(true);
  }

  void handleMessage(
    RemoteMessage? message,
  ) async {
    if (message == null) return;

    debugPrint("FCM Message Received: ${message.data}");
    debugPrint("FCM Notification: ${message.notification?.title} - ${message.notification?.body}");

    if (message.data['type'] == parkingResultType) {
      await showParkingResult(message.data);
      return;
    }

    // The parking prompt's Yes/No are real notification buttons. They must fire
    // only from an actual tap, so arrival does nothing but draw the prompt —
    // acting on the declared actions here would pay for parking unprompted.
    if (message.data['type'] == parkingPromptType) {
      await showParkingPrompt();
      return;
    }

    if (message.data.containsKey('actions')) {
      final actions = json.decode(message.data['actions']) as List;
      for (final entry in actions) {
        final action = entry is Map ? entry['action'] as String? : null;
        if (await dispatchNotificationAction(action, message.data)) break;
      }
    }
  }

  /// Runs the handler for a notification action the user selected.
  ///
  /// Dispatch is by action identifier rather than by position, so a
  /// notification carrying several actions runs the one that was chosen.
  /// Returns true when the action was recognised.
  static Future<bool> dispatchNotificationAction(
    String? action,
    Map<String, dynamic> data,
  ) async {
    if (action == null) return false;

    if (await handleParkingAction(action)) return true;

    if (action == 'add-wind-task') {
      final taskData = {
        'uid': AuthService().user!.uid,
        'date': data['date'],
        'body': data['body'],
        'startHour': data['startHour'],
        'endHour': data['endHour'],
      };
      await TaskService().callRemoteMethod('addWindTaskFromNotification', taskData);
      return true;
    }

    return false;
  }

  Future initPushNotifications(BuildContext c) async {
    if (init) return;
    RemoteMessage? initialMessage = await _fbMessaging.getInitialMessage();
    if (initialMessage != null) {
      handleMessage(initialMessage);
    }
    FirebaseMessaging.onMessageOpenedApp.listen((message) => handleMessage(message));
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      handleMessage(message);
    });

    FirebaseMessaging.onBackgroundMessage((message) async {
      handleMessage(message);
    });

    init = true;
  }
}
