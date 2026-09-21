import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// The slice of Firebase Cloud Messaging the app uses, behind an interface so
/// screens can be tested without the messaging plugin. [PushGateway.instance]
/// resolves to the Firebase implementation unless a test installs a fake.
abstract class PushGateway {
  static PushGateway? _override;
  static PushGateway get instance => _override ?? _FirebasePushGateway.shared;

  @visibleForTesting
  static set override(PushGateway? gateway) => _override = gateway;

  Future<void> requestPermission();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
  Stream<RemoteMessage> get onMessage;
  Stream<RemoteMessage> get onMessageOpenedApp;
  Future<RemoteMessage?> getInitialMessage();
  Future<void> setAutoInitEnabled(bool enabled);
}

class _FirebasePushGateway implements PushGateway {
  _FirebasePushGateway._();
  static final shared = _FirebasePushGateway._();

  FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  @override
  Future<void> requestPermission() => _fcm.requestPermission();

  @override
  Future<String?> getToken() => _fcm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fcm.onTokenRefresh;

  @override
  Stream<RemoteMessage> get onMessage => FirebaseMessaging.onMessage;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp;

  @override
  Future<RemoteMessage?> getInitialMessage() => _fcm.getInitialMessage();

  @override
  Future<void> setAutoInitEnabled(bool enabled) => _fcm.setAutoInitEnabled(enabled);
}
