import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/services/firebase_refs.dart';

class PerformanceService {
  PerformanceService._internal();
  // `late` so a test can inject a fake via [db] before the real instance is
  // touched (Firebase isn't initialized under `flutter test`).
  late FirebaseFirestore _db = FirebaseRefs.firestore;
  static PerformanceService _instance = PerformanceService._internal();

  /// Drops all state so the next `PerformanceService()` starts fresh.
  @visibleForTesting
  static void resetInstance() => _instance = PerformanceService._internal();

  factory PerformanceService() {
    return _instance;
  }

  @visibleForTesting
  set db(FirebaseFirestore db) => _db = db;

  DocumentReference<Map<String, dynamic>> score(String userId) {
    return _db.collection('todos').doc(userId);
  }

  Stream<List<Map<String, dynamic>>> streamPerformance(String userId, DateTime timestamp) {
    return score(userId)
        .collection('performance')
        .where("date", isGreaterThan: Timestamp.fromDate(timestamp))
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> streamPerformanceForMonth(String userId, DateTime startDate, DateTime endDate) {
    debugPrint('streamPerformanceForMonth: $startDate to $endDate');
    return score(userId)
        .collection('performance')
        .where("date", isGreaterThanOrEqualTo: startDate)
        .where("date", isLessThanOrEqualTo: endDate)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  Future<void> incrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(value)});
  }

  Future<void> decrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(-1 * value)});
  }

  /// The day a task's points belong to: its due date or, for a dateless task,
  /// the day it was completed — today when it's being completed now, the stored
  /// completion day when an already-completed task is reversed or re-scored.
  String statsDate(Task task) {
    final completedDay = task.completed ? completedDayOf(task.completedTime) : null;
    return task.dueDate ?? completedDay ?? DateService().getString(DateTime.now());
  }

  /// The `yyyy-MM-dd` part of a stored `completedTime`, or null if absent.
  static String? completedDayOf(String? completedTime) =>
      (completedTime != null && completedTime.length >= 10) ? completedTime.substring(0, 10) : null;

  Future<void> updatePerfomanceStats(String userId, Task task, bool shouldAdd) {
    return adjustCompleted(userId, statsDate(task), task.priority, task.tags.map((t) => t.id).toList(), shouldAdd);
  }

  /// Adds (or with [shouldAdd] false, removes) a completion's points on [date]'s
  /// `completed` tally under ALL plus each tag id (or Other when untagged).
  ///
  /// Written as server-side increments in a single merge, never read-modify-write:
  /// a read could fail offline or return a stale cached doc, and concurrent
  /// completions would overwrite each other — all of which silently lost points.
  Future<void> adjustCompleted(String userId, String date, Effort priority, List<String> tagIds, bool shouldAdd) {
    final points = getScore(priority) * (shouldAdd ? 1 : -1);
    return score(userId)
        .collection('performance')
        .doc(date)
        .set({'completed': _increments(points, tagIds), 'date': DateService().getDate(date)}, SetOptions(merge: true));
  }

  /// Records the effort points "pushed" off [fromDate] when a task is deferred.
  /// Mirrors the `completed` tally but writes a separate `pushed` map on the
  /// same per-day performance doc (ALL + Other/tag keys). Always additive.
  Future<void> recordPush(String userId, Task task, String fromDate) {
    final tagIds = task.tags.map((t) => t.id).toList();
    return score(userId)
        .collection('performance')
        .doc(fromDate)
        .set({'pushed': _increments(getScore(task.priority), tagIds), 'date': DateService().getDate(fromDate)},
            SetOptions(merge: true));
  }

  /// Nested map (not dotted paths, so tag ids containing '.' stay one key) that
  /// a merge-set applies key by key.
  Map<String, FieldValue> _increments(int points, List<String> tagIds) {
    final inc = FieldValue.increment(points);
    return {
      'ALL': inc,
      if (tagIds.isEmpty) 'Other': inc,
      for (final id in tagIds) id: inc,
    };
  }

  int getScore(Effort priority) {
    if (priority == Effort.high) {
      return 3;
    }
    if (priority == Effort.medium) {
      return 2;
    }
    if (priority == Effort.low) {
      return 1;
    }
    if (priority == Effort.info) {
      return 0;
    }
    debugPrint("Unknown Priority: $priority");
    return 0;
  }
}
