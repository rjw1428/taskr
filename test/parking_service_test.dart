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

  /// Statuses to serve, one per request, before falling back to [status].
  /// Lets a test make an attempt fail and the next one succeed.
  final List<int> statusSequence = [];

  /// What /health reports for `hasSession`. null omits the field entirely.
  Object? hasSession = true;

  /// Status for /health, which is served independently of [status] so a test
  /// can break the health endpoint without breaking /park, or the reverse.
  int healthStatus = 200;

  Future<String> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server.forEach((request) {
      authHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
      paths.add(request.uri.toString());
      if (request.uri.path == '/health') {
        request.response.statusCode = healthStatus;
        request.response.write(jsonEncode({
          'ok': true,
          if (hasSession != null) 'hasSession': hasSession,
        }));
        request.response.close();
        return;
      }
      request.response.statusCode =
          statusSequence.isNotEmpty ? statusSequence.removeAt(0) : status;
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
      ..token = 'test-token'
      ..retryBackoff = const [Duration.zero, Duration.zero];
  });

  tearDown(() async => stub.stop());

  group('triggerParking upstream session', () {
    test('a 409 reports that the account needs signing in', () async {
      stub.status = 409;

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.needsAuth);
      expect(result.message.toLowerCase(), contains('signed in'));
      expect(result.message.toLowerCase(), contains('nothing was charged'));
    });

    test('a 409 is not retried', () async {
      stub.status = 409;

      await service.triggerParking();

      expect(stub.paths.where((p) => p == '/park').length, 1);
    });

    test('does not consult /health on the way to paying', () async {
      stub.hasSession = false;

      final result = await service.triggerParking();

      expect(stub.paths, isNot(contains('/health')));
      expect(result.outcome, ParkingTriggerOutcome.accepted);
    });

    test('costs no extra round trip when the session is fine', () async {
      await service.triggerParking();

      expect(stub.paths, ['/park']);
    });
  });

  group('triggerParking', () {
    test('sends the token as a bearer header, never in the query string', () async {
      await service.triggerParking();

      expect(stub.paths, ['/park']);
      expect(stub.authHeaders.last, 'Bearer test-token');
      expect(stub.paths.last, isNot(contains('test-token')));
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
      // One attempt only — a rejected token is not retried.
      expect(stub.paths.where((p) => p == '/park').length, 1);
    });

    test('a 500 says nothing was paid for, and is not retried', () async {
      stub.status = 500;

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.failed);
      expect(result.message.toLowerCase(), contains('nothing was paid'));
      expect(stub.paths.where((p) => p == '/park').length, 1);
    });

    test('an unreachable service reports that the request was not sent', () async {
      await stub.stop();

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.failed);
      expect(result.message.toLowerCase(), contains('could not send'));
    });

    test('records the underlying error and per-attempt timings', () async {
      await stub.stop();

      final result = await service.triggerParking();

      expect(result.detail, contains('SocketException'));
      expect(RegExp(r'#\d+ \d+ms').allMatches(result.detail!).length, 3);
      expect(result.message, isNot(contains('SocketException')));
    });

    test('the stored error detail is one line and capped at 300 characters', () {
      expect(ParkingService.describeError(StateError('a  b\n\tc')), 'StateError: Bad state: a b c');
      // Exactly the cap passes through; one over is truncated to 297 plus an ellipsis.
      final atCap = 'x' * (300 - 'String: '.length);
      expect(ParkingService.describeError(atCap), 'String: $atCap');
      final over = 'y' * (301 - 'String: '.length);
      final described = ParkingService.describeError(over);
      expect(described.length, 300);
      expect(described, endsWith('...'));
    });

    test('carries the trail on a decisive answer too', () async {
      stub.statusSequence.addAll([503, 503]);

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.accepted);
      expect(result.detail, contains('HTTP 503'));
      expect(RegExp(r'#\d+ \d+ms').allMatches(result.detail!).length, 3);
    });

    test('a transient gateway error is retried and can still succeed', () async {
      stub.statusSequence.addAll([503, 502]);

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.accepted);
      expect(result.requestId, 'abc123');
      expect(stub.paths.where((p) => p == '/park').length, 3);
    });

    test('gives up after the configured number of attempts', () async {
      stub.status = 503;

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.failed);
      expect(stub.paths.where((p) => p == '/park').length, 3);
    });

    test('a 504 is a gateway error, so it is retried too', () async {
      stub.statusSequence.add(504);

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.accepted);
      expect(stub.paths.where((p) => p == '/park').length, 2);
    });

    test('numbers the attempts from one, including the decisive one', () async {
      stub.statusSequence.addAll([503, 503]);

      final result = await service.triggerParking();

      expect(result.detail, startsWith('#1 '));
      expect(result.detail, contains('; #2 '));
      expect(result.detail, contains('; #3 '));
    });

    test('caps a long error rendering so the inbox entry stays small', () async {
      // A host this long cannot resolve, and the lookup failure quotes it.
      service.baseUrl = 'http://${'a' * 400}.invalid';

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.failed);
      final first = result.detail!.split('; ').first;
      expect(first, startsWith('#1 '));
      expect(first, endsWith('...'));
      expect(first.length, lessThanOrEqualTo(310));
    });

    test('retries by default, with a real backoff between attempts', () {
      final fresh = ParkingService();
      expect(fresh.retryBackoff, isNotEmpty);
      expect(fresh.retryBackoff.every((d) => d > Duration.zero), isTrue);
    });

    test('a missing token makes no request at all', () async {
      service.token = '';

      final result = await service.triggerParking();

      expect(result.outcome, ParkingTriggerOutcome.unconfigured);
      expect(stub.paths, isEmpty);
    });
  });

  group('hasUpstreamSession', () {
    test('true when the service reports a live session', () async {
      stub.hasSession = true;

      expect(await service.hasUpstreamSession(), isTrue);
      expect(stub.paths, ['/health']);
    });

    test('false when the service reports a dead session', () async {
      stub.hasSession = false;

      expect(await service.hasUpstreamSession(), isFalse);
    });

    test('null when the field is absent', () async {
      stub.hasSession = null;

      expect(await service.hasUpstreamSession(), isNull);
    });

    test('null when /health itself errors', () async {
      stub.healthStatus = 503;

      expect(await service.hasUpstreamSession(), isNull);
    });

    test('null when the service is unreachable', () async {
      await stub.stop();

      expect(await service.hasUpstreamSession(), isNull);
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
