import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/parking.service.dart';
import 'package:taskr/services/parking_notifications.dart';
import 'package:taskr/services/parking_work.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

import 'helpers/harness.dart';

const _executeTaskChannel = 'dev.flutter.pigeon.workmanager_platform_interface.WorkmanagerFlutterApi.executeTask';

/// Answers /park so the worker's purchase needs no network.
class _StubParking {
  late HttpServer _server;
  final List<String> paths = [];
  int status = 200;

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach((request) {
      paths.add(request.uri.path);
      request.response.statusCode = status;
      request.response.write(jsonEncode({'success': true, 'requestId': 'req-1'}));
      request.response.close();
    }));
    return 'http://${_server.address.host}:${_server.port}';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late _StubParking stub;

  setUp(() async {
    env = await TestEnv.create();
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

  test('enqueueParkingPurchase registers one expedited, network-bound job', () async {
    await enqueueParkingPurchase();
    final job = (WorkmanagerPlatform.instance as FakeWorkmanager).registered.single;
    expect(job.uniqueName, 'parking-pay-work');
    expect(job.taskName, parkingPayTask);
    final queuedAt = job.inputData!['queuedAt'] as int;
    expect(DateTime.now().millisecondsSinceEpoch - queuedAt, lessThan(5000));
    expect(job.backoffDelay, const Duration(seconds: 10));
  });

  group('parkingCallbackDispatcher', () {
    /// Delivers a task to the handler the dispatcher registered, the way the
    /// WorkManager plugin does from the platform side.
    Future<bool?> execute(String taskName, Map<String, Object?>? inputData) async {
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final completer = Completer<ByteData?>();
      await messenger.handlePlatformMessage(
        _executeTaskChannel,
        WorkmanagerFlutterApi.pigeonChannelCodec.encodeMessage(<Object?>[taskName, inputData]),
        completer.complete,
      );
      final reply = WorkmanagerFlutterApi.pigeonChannelCodec.decodeMessage(await completer.future) as List<Object?>?;
      return reply?.first as bool?;
    }

    // The plugin keeps the handler in a `late final`, so register it once.
    setUpAll(parkingCallbackDispatcher);

    test('ignores tasks that are not the parking purchase', () async {
      expect(await execute('something-else', null), isTrue);
      expect(stub.paths, isEmpty);
    });

    test('runs a fresh purchase and reports the outcome', () async {
      final queuedAt = DateTime.now().millisecondsSinceEpoch;
      expect(await execute(parkingPayTask, {'queuedAt': queuedAt}), isTrue);
      expect(stub.paths, ['/park']);
      expect((await inbox()).single['title'], 'Parking requested');
    });

    test('asks for a retry when the service is down', () async {
      stub.status = 503;
      expect(await execute(parkingPayTask, null), isFalse);
      expect(await inbox(), isEmpty);
    });

    test('abandons a purchase queued too long ago', () async {
      final stale = DateTime.now().subtract(const Duration(hours: 3)).millisecondsSinceEpoch;
      expect(await execute(parkingPayTask, {'queuedAt': stale}), isTrue);
      expect(stub.paths, isEmpty);
      expect((await inbox()).single['data'], {'outcome': 'abandoned'});
    });
  });
}
