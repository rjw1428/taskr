import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'package:taskr/firebase_options.dart';

import 'parking_notifications.dart';

/// Task name for the parking purchase.
const String parkingPayTask = 'parking-pay';

/// Unique work name. Reusing it means a second tap joins the pending purchase
/// rather than queueing another one.
const String _parkingWorkName = 'parking-pay-work';

const String _queuedAtKey = 'queuedAt';

/// How long a queued purchase stays worth retrying.
///
/// WorkManager will happily retry for a day. A session bought late at night
/// covers a commute that already happened, so a stale attempt is abandoned
/// instead of charging for parking nobody needs.
const Duration _maxAge = Duration(hours: 2);

/// Entry point for the WorkManager isolate.
///
/// Registered from `main()` and re-entered by Android in a fresh isolate, so it
/// must bootstrap everything it needs itself.
@pragma('vm:entry-point')
void parkingCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != parkingPayTask) return true;

    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('parking worker: Firebase already initialized: $e');
    }

    final queuedAt = inputData?[_queuedAtKey] as int?;
    if (queuedAt != null &&
        DateTime.now().millisecondsSinceEpoch - queuedAt > _maxAge.inMilliseconds) {
      await reportParkingAbandoned();
      return true;
    }

    // False asks WorkManager to retry with backoff, which is the whole point of
    // running here: the tap survives a dead zone.
    return runParkingPurchase();
  });
}

/// Queues the purchase. Deliberately cheap: a local WorkManager write, which
/// completes well inside the notification receiver's short lifetime.
Future<void> enqueueParkingPurchase() {
  return Workmanager().registerOneOffTask(
    _parkingWorkName,
    parkingPayTask,
    inputData: {_queuedAtKey: DateTime.now().millisecondsSinceEpoch},
    existingWorkPolicy: ExistingWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(seconds: 10),
    expedited: true,
  );
}
