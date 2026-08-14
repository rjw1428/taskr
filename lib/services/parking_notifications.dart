import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:taskr/shared/error_reporting.dart';

import 'parking.service.dart';

/// FCM `data.type` identifying the actionable "pay for parking?" prompt.
const String parkingPromptType = 'parking_prompt';

/// FCM `data.type` for the parking service's own asynchronous result push.
const String parkingResultType = 'septapark';

const String payParkingAction = 'pay-parking';
const String dismissParkingAction = 'dismiss-parking';

/// Marks a notification as the parking prompt so a tap on its *body* — which
/// carries no action id and merely opens the app — can be recognised and
/// answered with the in-app dialog instead of dropping the user somewhere with
/// no way to act.
const String parkingPromptPayload = 'parking-prompt';

const int _parkingPromptId = 90001;
const int _parkingResultId = 90002;

const AndroidNotificationChannel _parkingChannel = AndroidNotificationChannel(
  'fcm_default_channel',
  'Taskr Notifications',
  description: 'Notifications from Taskr',
  importance: Importance.high,
);

/// The plugin is a singleton, so this is the same instance `main.dart` holds —
/// which matters because these functions also run in the FCM background
/// isolate, where `main()` never ran.
final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

/// Loads `.env` if this isolate has not already. The background isolate starts
/// cold, so the token would otherwise be missing exactly when the user taps Yes.
Future<void> _ensureEnvLoaded() async {
  if (dotenv.isInitialized) return;
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('parking: could not load .env: $e');
  }
}

/// Displays the parking prompt, unless parking is already covered.
///
/// The push is data-only — a `notification` block would make Android draw its
/// own buttonless copy alongside this one — so nothing appears unless this runs.
Future<void> showParkingPrompt([Map<String, dynamic>? data]) async {
  await _ensureEnvLoaded();

  // Skip a prompt that could not do anything useful. This fails open: only an
  // unambiguous "yes, a session is active" suppresses it, because a swallowed
  // prompt costs a day of unpaid parking while a redundant one costs a tap.
  if (await ParkingService().hasActiveSession()) {
    debugPrint('parking: session already active, suppressing prompt');
    return;
  }

  await _plugin.show(
    _parkingPromptId,
    data?['title'] as String? ?? 'Pay for parking?',
    data?['body'] as String? ?? 'Your train is leaving. Want to pay for parking?',
    NotificationDetails(
      android: AndroidNotificationDetails(
        _parkingChannel.id,
        _parkingChannel.name,
        channelDescription: _parkingChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            payParkingAction,
            'Yes',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          // No handler work at all: this action exists only to dismiss.
          AndroidNotificationAction(
            dismissParkingAction,
            'No',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ],
      ),
    ),
    payload: parkingPromptPayload,
  );
}

/// Asks in-app whether to pay for parking.
///
/// The notification's buttons are the fast path, but they are gone once it is
/// dismissed or tapped on the body — and a tap that opens the app with no way
/// to answer is a dead end. This is the same question, reachable from inside.
Future<void> showParkingPromptDialog(BuildContext context) async {
  final pay = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Pay for parking?'),
      content: const Text('Buy a parking session for today?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('No'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Yes'),
        ),
      ],
    ),
  );

  if (pay != true) return;

  final result = await ParkingService().triggerParking();
  // The app is open, so report inline rather than as another notification.
  scaffoldMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.message)));
}

/// Runs the action the user selected on a notification.
///
/// Returns true when the action was recognised, so callers can fall through to
/// their own handling otherwise.
Future<bool> handleParkingAction(String? actionId) async {
  switch (actionId) {
    case payParkingAction:
      await _payForParking();
      return true;
    case dismissParkingAction:
      // Dismissal is the whole behaviour. No request, no writes.
      debugPrint('parking: prompt dismissed');
      return true;
    default:
      return false;
  }
}

Future<void> _payForParking() async {
  await _ensureEnvLoaded();

  final result = await ParkingService().triggerParking();
  debugPrint('parking: trigger outcome ${result.outcome} (${result.requestId})');

  // The app may well be closed, so the only way to report back is a
  // notification. Note this reports whether the *request* went out — the
  // service pushes the actual payment outcome separately.
  await _showParkingInfo(
    result.outcome == ParkingTriggerOutcome.accepted
        ? 'Parking requested'
        : 'Parking not requested',
    result.message,
  );
}

/// Surfaces the parking service's own asynchronous result push.
Future<void> showParkingResult(Map<String, dynamic> data) async {
  final status = data['status'] as String?;

  switch (status) {
    case 'paid':
      await _showParkingInfo('Parking paid', 'Your parking session is active.');
      break;
    case 'skipped':
      await _showParkingInfo(
        'Parking already active',
        'A session was already covering you. Nothing was bought.',
      );
      break;
    case 'needs-auth':
      // Retrying can never fix this — it needs a person to complete an SMS
      // verification — so this deliberately offers no retry affordance.
      await _showParkingInfo(
        'Parking needs sign-in',
        'The parking account must be re-authenticated before it can pay again.',
      );
      break;
    case 'dry-run':
      await _showParkingInfo('Parking dry run', 'Nothing was charged.');
      break;
    case 'refused':
      await _showParkingInfo(
        'Parking refused',
        'A safety check stopped the purchase. Nothing was charged.',
      );
      break;
    default:
      await _showParkingInfo(
        'Parking failed',
        'The parking run did not complete. Nothing was charged.',
      );
  }
}

Future<void> _showParkingInfo(String title, String body) async {
  await _plugin.show(
    _parkingResultId,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        _parkingChannel.id,
        _parkingChannel.name,
        channelDescription: _parkingChannel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
  );
}
