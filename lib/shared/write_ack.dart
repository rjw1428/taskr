import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:taskr/shared/error_reporting.dart';

/// How a Firestore write ended up.
enum WriteAck {
  /// The server acknowledged it.
  confirmed,

  /// Applied to the local cache but not yet acknowledged — the SDK will retry
  /// until it reaches the server. Only possible for writes the offline queue
  /// can hold (a plain set/update/delete, not a transaction).
  queued,

  /// It failed outright; the user has already been shown the error.
  failed,
}

/// How long to wait for the server before treating a write as offline-queued.
const kWriteAckTimeout = Duration(seconds: 6);

/// Waits a bounded time for [write] to be acknowledged.
///
/// Firestore's write futures complete only when the *server* confirms them.
/// With no connectivity the SDK applies the write to the local cache and leaves
/// the future pending indefinitely — which is why a failing save used to hang a
/// form open with no error and no snackbar. Here instead:
///
///   * completes  → [WriteAck.confirmed]
///   * throws     → error snackbar, [WriteAck.failed] (late failures, after this
///                  future has already returned, still raise a snackbar)
///   * times out  → [WriteAck.queued] plus a notice, so the caller can close its
///                  form; the write is safe in the offline queue.
///
/// Pass `queueable: false` for work the offline queue cannot hold — a
/// transaction needs a round trip, so a timeout there means the change is lost
/// and is reported as an error rather than a queued write.
Future<WriteAck> ackWrite(
  Future<void> write, {
  String? action,
  bool queueable = true,
  Duration timeout = kWriteAckTimeout,
}) {
  final guarded = write.then<WriteAck>((_) => WriteAck.confirmed).catchError((Object e, StackTrace s) {
    reportError(e, s, action);
    return WriteAck.failed;
  });
  return guarded.timeout(timeout, onTimeout: () {
    if (queueable) {
      debugPrint('Write not acknowledged in ${timeout.inSeconds}s, queued offline${action == null ? '' : ': $action'}');
      showNoticeSnack("Saved on this device — it'll sync when you're back online.");
      return WriteAck.queued;
    }
    reportError(
      TimeoutException("the server didn't respond in ${timeout.inSeconds}s"),
      null,
      action,
    );
    return WriteAck.failed;
  });
}
