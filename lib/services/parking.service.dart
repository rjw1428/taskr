import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Base URL of the SEPTA Park auto-pay service. The public route strips the
/// `/parking` prefix before the request reaches the service, so `/parking/park`
/// and the service's own `/park` are the same endpoint.
const String parkingBaseUrl = 'https://api.ryanwilk.com/parking';

/// How long to wait on the service before giving up. The trigger is
/// fire-and-forget on the far side, so a slow response means a slow *network*,
/// not a slow purchase.
const Duration _parkingTimeout = Duration(seconds: 10);

/// What happened when we asked the service to buy parking.
///
/// Note [accepted] means the request was accepted and the purchase is running —
/// it does **not** mean parking has been paid for. The real outcome arrives
/// later as a separate FCM push with `type == 'septapark'`.
enum ParkingTriggerOutcome {
  /// The service accepted the request. Payment is in progress, not complete.
  accepted,

  /// No trigger token is configured, so nothing was sent.
  unconfigured,

  /// The service rejected our token. Retrying will not help.
  unauthorized,

  /// The request never made it, or came back an error. Nothing was bought.
  failed,

  /// The service's own upstream session has expired, so it cannot buy anything
  /// until a person completes an SMS verification. Retrying is futile.
  needsAuth,
}

class ParkingTriggerResult {
  const ParkingTriggerResult(this.outcome, this.message, {this.requestId});

  final ParkingTriggerOutcome outcome;

  /// User-facing text. Deliberately never claims parking is paid for.
  final String message;

  /// Correlates with the service's logs and its result push.
  final String? requestId;
}

class ParkingService {
  /// Overridden in tests to point at a local stub server. Late so the default
  /// is resolved on first read, never at construction.
  late String baseUrl = parkingBaseUrl;

  /// The bearer token, copied from the automation project's `.env`. Late so a
  /// background isolate can load `.env` before this is first read, and so tests
  /// can inject one without a dotenv fixture.
  late String token = dotenv.env['PARKING_TRIGGER_TOKEN'] ?? '';

  String get _token => token;

  bool get isConfigured => _token.isNotEmpty;

  /// Whether the service still has a working upstream session.
  ///
  /// Returns null when that cannot be determined, so callers can carry on
  /// rather than block a purchase that might have succeeded.
  Future<bool?> hasUpstreamSession() async {
    try {
      // /health needs no auth and reports the upstream session directly.
      final response = await HttpClient()
          .getUrl(Uri.parse('$baseUrl/health'))
          .then((request) => request.close())
          .timeout(_parkingTimeout);
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) return null;
      final health = jsonDecode(body) as Map<String, dynamic>;
      final session = health['hasSession'];
      return session is bool ? session : null;
    } catch (e) {
      debugPrint('ParkingService.hasUpstreamSession error: $e');
      return null;
    }
  }

  /// Asks the service to buy a parking session.
  ///
  /// The endpoint is idempotent in practice — if a session is already active for
  /// the plate it reports `skipped` and buys nothing — so a double-tap cannot
  /// double-charge.
  Future<ParkingTriggerResult> triggerParking() async {
    if (!isConfigured) {
      return const ParkingTriggerResult(
        ParkingTriggerOutcome.unconfigured,
        'Parking is not set up on this device.',
      );
    }

    // The service reports a dead upstream session before we spend a request on
    // it. Its own result push is best-effort, so catching this here is the
    // difference between a certain notification and a silent non-payment.
    if (await hasUpstreamSession() == false) {
      return const ParkingTriggerResult(
        ParkingTriggerOutcome.needsAuth,
        'Parking could not be paid: the parking account needs to be signed in '
        'again. Nothing was charged.',
      );
    }

    try {
      final url = Uri.parse('$baseUrl/park');
      final response = await HttpClient()
          .getUrl(url)
          .then((request) {
            // The token goes in the header, never the query string, so it stays
            // out of access logs, proxy logs and browser history.
            request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
            return request.close();
          })
          .timeout(_parkingTimeout);

      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode == 401) {
        return const ParkingTriggerResult(
          ParkingTriggerOutcome.unauthorized,
          'Parking request was rejected. The access token needs updating.',
        );
      }

      if (response.statusCode != 200) {
        return ParkingTriggerResult(
          ParkingTriggerOutcome.failed,
          'Could not reach the parking service (${response.statusCode}). '
          'Nothing was paid for.',
        );
      }

      String? requestId;
      try {
        requestId = (jsonDecode(body) as Map<String, dynamic>)['requestId'] as String?;
      } catch (_) {
        // A 200 we cannot parse is still an accepted request; the requestId is
        // only used for correlation.
      }

      // 200 means *accepted*, not paid. Say so.
      return ParkingTriggerResult(
        ParkingTriggerOutcome.accepted,
        'Parking request sent. You will get a notification when it completes.',
        requestId: requestId,
      );
    } catch (e) {
      debugPrint('ParkingService.triggerParking error: $e');
      return const ParkingTriggerResult(
        ParkingTriggerOutcome.failed,
        'Could not send the parking request. Nothing was paid for.',
      );
    }
  }

  /// Whether a parking session is already covering the vehicle.
  ///
  /// Fails **open**: anything other than an unambiguous `200` with a non-empty
  /// `active` array returns false. Suppressing the prompt on a transient network
  /// failure would risk a day of unpaid parking, which is far worse than one
  /// unnecessary notification.
  Future<bool> hasActiveSession() async {
    if (!isConfigured) return false;

    try {
      final url = Uri.parse('$baseUrl/status');
      final response = await HttpClient()
          .getUrl(url)
          .then((request) {
            request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
            return request.close();
          })
          .timeout(_parkingTimeout);

      final body = await response.transform(utf8.decoder).join();

      // 409 (upstream session expired) and 502 (upstream error) tell us nothing
      // about whether parking is covered, so they fall through to false.
      if (response.statusCode != 200) return false;

      final active = (jsonDecode(body) as Map<String, dynamic>)['active'];
      return active is List && active.isNotEmpty;
    } catch (e) {
      debugPrint('ParkingService.hasActiveSession error: $e');
      return false;
    }
  }
}
