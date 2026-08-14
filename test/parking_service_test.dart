import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/parking.service.dart';

/// A stand-in for the parking service. Real HTTP, so the bearer header and the
/// status-code handling are genuinely exercised rather than mocked away.
class _StubServer {
  late HttpServer _server;
  final List<String?> authHeaders = [];
  final List<String> paths = [];

  int status = 200;
  String body = '{"success": true, "requestId": "abc123"}';

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach((request) {
      authHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
      paths.add(request.uri.toString());
      request.response.statusCode = status;
      request.response.write(body);
      request.response.close();
    }));
    return 'http://${_server.address.host}:${_server.port}';
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  late _StubServer stub;
  late ParkingService service;

  setUp(() async {
    stub = _StubServer();
    final url = await stub.start();
    service = ParkingService()
      ..baseUrl = url
      ..token = 'test-token';
  });

  tearDown(() async => stub.stop());

  group('triggerParking', () {
    test('sends the token as a bearer header, never in the query string', () async {
      await service.triggerParking();

      expect(stub.authHeaders.single, 'Bearer test-token');
      expect(stub.paths.single, '/park');
      expect(stub.paths.single, isNot(contains('test-token')));
    });

    test('a 200 is reported as sent, never as paid', () async {
      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.accepted);
      expect(result.requestId, 'abc123');
      // The endpoint is fire-and-forget: 200 means accepted, not paid. Copy that
      // claims payment here would be actively misleading.
      expect(result.message.toLowerCase(), isNot(contains('paid')));
      expect(result.message.toLowerCase(), contains('sent'));
    });

    test('a 200 with an unparseable body is still accepted', () async {
      stub.body = 'not json';

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.accepted);
      expect(result.requestId, isNull);
    });

    test('a 401 is reported without retrying', () async {
      stub.status = 401;

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.unauthorized);
      expect(stub.paths.length, 1);
    });

    test('a 500 says nothing was paid for', () async {
      stub.status = 500;

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.failed);
      expect(result.message.toLowerCase(), contains('nothing was paid'));
    });

    test('an unreachable service reports that the request was not sent', () async {
      await stub.stop();

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.failed);
    });

    test('a missing token makes no request at all', () async {
      service.token = '';

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.unconfigured);
      expect(stub.paths, isEmpty);
    });
  });

  group('hasActiveSession', () {
    test('true when a session is active', () async {
      stub.body = jsonEncode({
        'active': [
          {'plate': 'ZXC9751', 'lot': 'Somerton Station'}
        ]
      });

      expect(await service.hasActiveSession(), isTrue);
      expect(stub.authHeaders.single, 'Bearer test-token');
    });

    test('false when nothing is active, so the prompt is shown', () async {
      stub.body = jsonEncode({'active': []});

      expect(await service.hasActiveSession(), isFalse);
    });

    // The next three pin the fail-open rule: only an unambiguous "a session is
    // active" may suppress the prompt. A swallowed prompt costs a day of unpaid
    // parking; a redundant one costs a tap.
    test('fails open when the service is unreachable', () async {
      await stub.stop();

      expect(await service.hasActiveSession(), isFalse);
    });

    test('fails open on 409 (upstream session expired)', () async {
      stub.status = 409;
      stub.body = '{"detail": "needs auth"}';

      expect(await service.hasActiveSession(), isFalse);
    });

    test('fails open on 502 (upstream error)', () async {
      stub.status = 502;

      expect(await service.hasActiveSession(), isFalse);
    });

    test('fails open on an unparseable body', () async {
      stub.body = 'not json';

      expect(await service.hasActiveSession(), isFalse);
    });
  });
}
