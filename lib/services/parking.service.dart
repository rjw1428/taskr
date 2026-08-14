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
