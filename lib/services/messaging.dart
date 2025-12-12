import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/coaching.dart';

class FirebaseMessageService {
  final _fbMessaging = FirebaseMessaging.instance;
  bool init = false;
  List<Task> _tasks = [];
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

    print('User granted permission: ${settings.authorizationStatus}');
    final fcmToken = await _fbMessaging.getToken();
    print("TOKEN: $fcmToken");

    await FirebaseMessaging.instance.setAutoInitEnabled(true);
  }

  void handleMessage(
    RemoteMessage? message,
    BuildContext? c,
  ) async {
    if (message == null) return;

    print("FCM Message Received: ${message.data}");
    print("FCM Notification: ${message.notification?.title} - ${message.notification?.body}");

    if (message.data.containsKey('actions')) {
      final actions = json.decode(message.data['actions']);
      final action = actions[0]['action'];
      if (action == 'add-wind-task') {
        final taskData = {
          'uid': AuthService().user!.uid,
          'date': message.data['date'],
          'body': message.data['body'],
          'startHour': message.data['startHour'],
          'endHour': message.data['endHour'],
        };
        await TaskService().addWindTask(taskData);
      }
    }
  }

  Future initPushNotifications(BuildContext c) async {
    if (init) return;
    RemoteMessage? initialMessage = await _fbMessaging.getInitialMessage();
    if (initialMessage != null) {
      handleMessage(initialMessage, c);
    }
    FirebaseMessaging.onMessageOpenedApp.listen((message) => handleMessage(message, c));
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      handleMessage(message, c);
    });

    FirebaseMessaging.onBackgroundMessage((message) async {
      handleMessage(message, null);
    });

    init = true;
  }
}
