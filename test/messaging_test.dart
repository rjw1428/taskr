import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/services.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import 'helpers/harness.dart';

/// Answers the parking service's /status so the prompt path needs no network.
class _StubParking {
  late HttpServer _server;
  final List<String> paths = [];
  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach((request) {
      paths.add(request.uri.path);
      request.response.write(jsonEncode({'active': [], 'success': true}));
      request.response.close();
    }));
    return 'http://${_server.address.host}:${_server.port}';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late TestEnv env;
  late _StubParking stub;
  late FirebaseMessageService messaging;

  setUp(() async {
    env = await TestEnv.create();
    // The widget binding installs a stub HttpClient that answers 400; the
    // parking stub below is a real local server.
    HttpOverrides.global = null;
    stub = _StubParking();
    final url = await stub.start();
    parkingServiceFactory = () => ParkingService()
      ..baseUrl = url
      ..token = 'tok';
    messaging = FirebaseMessageService();
  });
  tearDown(() async {
    parkingServiceFactory = ParkingService.new;
    await stub.stop();
    env.dispose();
  });

  Future<List<Map<String, dynamic>>> inbox() async =>
      (await env.col('notifications').get()).docs.map((d) => d.data()).toList();

  test('initNotifiactions asks for permission, reads the token and enables auto-init', () async {
    await messaging.initNotifiactions();
    expect(env.push.permissionRequests, 1);
    expect(env.push.autoInit, isTrue);
  });

  group('handleMessage', () {
    test('ignores a null message', () async {
      messaging.handleMessage(null);
      await Future<void>.delayed(Duration.zero);
      expect(await inbox(), isEmpty);
    });

    test('a parking result is recorded in the inbox', () async {
      messaging.handleMessage(const RemoteMessage(data: {'type': parkingResultType, 'status': 'paid'}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final rows = await inbox();
      expect(rows.single['title'], 'Parking paid');
      expect(rows.single['type'], 'parking_result');
    });

    test('a parking prompt is drawn, never acted on', () async {
      messaging.handleMessage(const RemoteMessage(
        data: {'type': parkingPromptType, 'title': 'Train at 7:40'},
        notification: RemoteNotification(title: 'n', body: 'b'),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(stub.paths, ['/status']);
      expect((WorkmanagerPlatform.instance as FakeWorkmanager).registered, isEmpty);
    });

    test('declared actions run the first one recognised', () async {
      env.functions['addWindTaskFromNotification'] = (_) => 'ok';
      messaging.handleMessage(RemoteMessage(data: {
        'actions': jsonEncode([
          'not-a-map',
          {'action': 'unknown'},
          {'action': 'add-wind-task'},
          {'action': 'dismiss-parking'},
        ]),
        'date': '2026-08-01',
        'body': 'Windy',
        'startHour': '9',
        'endHour': '11',
      }));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(env.functionCalls.single.name, 'addWindTaskFromNotification');
      expect(env.functionCalls.single.payload, {
        'uid': env.uid,
        'date': '2026-08-01',
        'body': 'Windy',
        'startHour': '9',
        'endHour': '11',
      });
    });
  });

  group('dispatchNotificationAction', () {
    test('null and unknown actions are not handled', () async {
      expect(await FirebaseMessageService.dispatchNotificationAction(null, {}), isFalse);
      expect(await FirebaseMessageService.dispatchNotificationAction('nope', {}), isFalse);
    });

    test('parking actions are delegated', () async {
      expect(await FirebaseMessageService.dispatchNotificationAction(dismissParkingAction, {}), isTrue);
      expect(await FirebaseMessageService.dispatchNotificationAction(payParkingAction, {}), isTrue);
      expect((WorkmanagerPlatform.instance as FakeWorkmanager).registered.single.taskName, 'parking-pay');
    });
  });

  group('initPushNotifications', () {
    testWidgets('handles the launch message and listens for later ones, once', (tester) async {
      env.push.initialMessage = const RemoteMessage(data: {'type': parkingResultType, 'status': 'paid'});
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));

      await messaging.initPushNotifications(context);
      expect(messaging.init, isTrue);
      await messaging.initPushNotifications(context);

      env.push.onMessageController.add(const RemoteMessage(data: {'type': parkingResultType, 'status': 'refused'}));
      env.push.onMessageOpenedAppController
          .add(const RemoteMessage(data: {'type': parkingResultType, 'status': 'dry-run'}));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));

      final titles = (await tester.runAsync(inbox))!.map((r) => r['title']).toList();
      expect(titles, unorderedEquals(['Parking paid', 'Parking refused', 'Parking dry run']));
    });
  });
}
