import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/parking.service.dart';
import 'package:taskr/services/parking_notifications.dart';
import 'package:taskr/shared/error_reporting.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import 'helpers/android_notifications.dart';
import 'helpers/harness.dart';

/// The default [HttpOverrides] builds a real client, which is what the dialog
/// needs inside a widget test (flutter_test's zone-level override answers 400).
class _RealHttp extends HttpOverrides {}

/// Stands in for the parking service's /status and /park routes.
class _StubParking {
  late HttpServer _server;
  final List<String> paths = [];
  int parkStatus = 200;
  List<Map<String, dynamic>> active = const [];

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach((request) {
      paths.add(request.uri.path);
      if (request.uri.path == '/status') {
        request.response.write(jsonEncode({'active': active}));
      } else {
        request.response.statusCode = parkStatus;
        request.response.write(jsonEncode({'success': true, 'requestId': 'req-1'}));
      }
      request.response.close();
    }));
    return 'http://${_server.address.host}:${_server.port}';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late TestEnv env;
  late _StubParking stub;
  late FakeAndroidNotifications notifications;

  setUp(() async {
    env = await TestEnv.create();
    notifications = FakeAndroidNotifications.install();
    // The widget binding installs a stub HttpClient that answers 400; the
    // parking stub below is a real local server.
    HttpOverrides.global = null;
    stub = _StubParking();
    final url = await stub.start();
    parkingServiceFactory = () => ParkingService()
      ..baseUrl = url
      ..token = 'tok'
      ..retryBackoff = const [Duration.zero];
  });
  tearDown(() async {
    parkingServiceFactory = ParkingService.new;
    await stub.stop();
    env.dispose();
  });

  Future<List<Map<String, dynamic>>> inbox() async =>
      (await env.col('notifications').get()).docs.map((d) => d.data()).toList();

  FakeWorkmanager workmanager() => WorkmanagerPlatform.instance as FakeWorkmanager;

  group('showParkingPrompt', () {
    test('is suppressed while a session is active', () async {
      stub.active = [
        {'plate': 'ZXC9751'}
      ];
      await showParkingPrompt();
      expect(stub.paths, ['/status']);
      expect(notifications.shown, isEmpty);
    });

    test('is drawn when nothing covers the car', () async {
      await showParkingPrompt({'title': 'Train at 7:40', 'body': 'Pay?'});
      await showParkingPrompt();
      expect(stub.paths, ['/status', '/status']);

      expect(notifications.shown, hasLength(2));
      final custom = notifications.shown.first;
      expect(custom.title, 'Train at 7:40');
      expect(custom.body, 'Pay?');
      final fallback = notifications.shown.last;
      expect(fallback.title, 'Pay for parking?');
      expect(fallback.body, contains('pay for parking'));
      for (final shown in notifications.shown) {
        // The body tap is recognised by its payload, and the Yes/No buttons
        // are the whole point of drawing this locally.
        expect(shown.payload, parkingPromptPayload);
        expect(shown.details?.actions?.map((a) => a.id), [payParkingAction, dismissParkingAction]);
        expect(shown.details?.actions?.map((a) => a.title), ['Yes', 'No']);
        expect(shown.details?.icon, '@mipmap/ic_launcher');
      }
    });
  });

  group('handleParkingAction', () {
    test('Yes queues the purchase with WorkManager', () async {
      expect(await handleParkingAction(payParkingAction), isTrue);
      final job = workmanager().registered.single;
      expect(job.uniqueName, 'parking-pay-work');
      expect(job.taskName, 'parking-pay');
      expect(job.inputData!['queuedAt'], isA<int>());
      expect(stub.paths, isEmpty);
    });

    test('No does nothing, and other actions are not handled', () async {
      expect(await handleParkingAction(dismissParkingAction), isTrue);
      expect(await handleParkingAction('something'), isFalse);
      expect(await handleParkingAction(null), isFalse);
      expect(workmanager().registered, isEmpty);
    });
  });

  group('runParkingPurchase', () {
    test('an accepted request is reported and recorded', () async {
      expect(await runParkingPurchase(), isTrue);
      final row = (await inbox()).single;
      expect(row['title'], 'Parking requested');
      expect(row['data'], containsPair('outcome', 'accepted'));
      expect(row['data'], containsPair('requestId', 'req-1'));
      expect(row['data']['detail'], contains('#1 '));
    });

    test('a dead upstream session asks for sign-in', () async {
      stub.parkStatus = 409;
      expect(await runParkingPurchase(), isTrue);
      expect((await inbox()).single['title'], 'Parking needs sign-in');
    });

    test('a rejected token says parking was not paid', () async {
      stub.parkStatus = 401;
      expect(await runParkingPurchase(), isTrue);
      expect((await inbox()).single['title'], 'Parking NOT paid');
    });

    test('a retryable failure stays quiet and asks for a retry', () async {
      stub.parkStatus = 503;
      expect(await runParkingPurchase(), isFalse);
      expect(await inbox(), isEmpty);
    });
  });

  test('reportParkingAbandoned records the give-up', () async {
    await reportParkingAbandoned();
    final row = (await inbox()).single;
    expect(row['title'], 'Parking NOT paid');
    expect(row['data'], {'outcome': 'abandoned'});
  });

  test('showParkingResult and recordParkingResult both land in the inbox', () async {
    await showParkingResult({'status': 'needs-auth'});
    await recordParkingResult({'status': 'refused'});
    final titles = (await inbox()).map((r) => r['title']).toList();
    expect(titles, unorderedEquals(['Parking needs sign-in', 'Parking refused']));
    // Only showParkingResult draws; recordParkingResult is inbox-only.
    expect(notifications.shown.single.title, 'Parking needs sign-in');
    expect(notifications.shown.single.details?.icon, '@mipmap/ic_launcher');
  });

  group('parkingResultMessage', () {
    test('every status has truthful wording', () {
      expect(parkingResultMessage({'status': 'paid'}).title, 'Parking paid');
      expect(parkingResultMessage({'status': 'skipped'}).title, 'Parking already active');
      expect(parkingResultMessage({'status': 'needs-auth'}).title, 'Parking needs sign-in');
      expect(parkingResultMessage({'status': 'dry-run'}).body, 'Nothing was charged.');
      expect(parkingResultMessage({'status': 'refused'}).title, 'Parking refused');
      expect(parkingResultMessage({}).title, 'Parking failed');
    });

    test('prefers the wording the service composed', () {
      final m = parkingResultMessage({'status': 'paid', 'title': 'T', 'body': 'B'});
      expect(m, (title: 'T', body: 'B'));
    });
  });

  group('showParkingPromptDialog', () {
    /// Lets real socket I/O and the fake-async microtasks it schedules take
    /// turns until the purchase round trip has finished.
    Future<void> settleIo(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
    }

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: scaffoldMessengerKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => HttpOverrides.runWithHttpOverrides(() => showParkingPromptDialog(context), _RealHttp()),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pay for parking?'), findsOneWidget);
    }

    testWidgets('No closes the dialog and buys nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(find.text('Pay for parking?'), findsNothing);
      expect(stub.paths, isEmpty);
    });

    testWidgets('Yes triggers the purchase, records it and shows a snackbar', (tester) async {
      await open(tester);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await settleIo(tester);
      expect(stub.paths, ['/park']);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Parking request sent'), findsOneWidget);
      final rows = await tester.runAsync(inbox);
      expect(rows!.single['title'], 'Parking requested');
      scaffoldMessengerKey.currentState?.clearSnackBars();
      // Let the HttpClient's idle keep-alive timer expire before teardown.
      await tester.pump(const Duration(seconds: 20));
    });

    testWidgets('a failed purchase is reported as not paid', (tester) async {
      stub.parkStatus = 401;
      await open(tester);
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await settleIo(tester);
      final rows = await tester.runAsync(inbox);
      expect(rows!.single['title'], 'Parking NOT paid');
      scaffoldMessengerKey.currentState?.clearSnackBars();
      // Let the HttpClient's idle keep-alive timer expire before teardown.
      await tester.pump(const Duration(seconds: 20));
    });
  });
}
