import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/date.service.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/task.service.dart';
import 'package:taskr/shared/shared.dart';

/// Manual, open-ended habits backed by the recurring-task generation engine.
/// A habit materializes real task instances (stamped with `habitId`) on a
/// rolling horizon; completing an instance scores its Effort through the normal
/// task flow, while the streak is tracked separately here and never affects the
/// score.
class HabitService {
  // `late` so a test can inject a fake via [db] before the real instance is
  // touched (Firebase isn't initialized under `flutter test`).
  late FirebaseFirestore _db = FirebaseFirestore.instance;
  final TaskService _taskService = TaskService();
  final DateService _dates = DateService();

  @visibleForTesting
  set db(FirebaseFirestore db) {
    _db = db;
    // ignore: invalid_use_of_visible_for_testing_member
    _taskService.db = db; // keep the wrapped TaskService on the same fake
  }

  // Guards against concurrent top-ups within the app (e.g. Habits list + List
  // tab both calling ensureInstances at once) creating duplicate instances.
  static final Set<String> _materializing = {};

  String get _uid => AuthService().user!.uid;

  CollectionReference<Map<String, dynamic>> habitCollection(String uid) =>
      _db.collection('todos').doc(uid).collection('habits');

  Stream<List<Habit>> streamHabits() {
    return habitCollection(_uid).snapshots().map((snap) {
      final habits = snap.docs.map((doc) => Habit.fromJson({...doc.data(), 'id': doc.id})).toList();
      habits.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
      return habits;
    });
  }

  Future<Habit?> getHabit(String id) async {
    final doc = await habitCollection(_uid).doc(id).get();
    if (!doc.exists) return null;
    return Habit.fromJson({...doc.data()!, 'id': doc.id});
  }

  RecurringTask _toRecurringTask(Habit h, {required DateTime start, required DateTime until}) {
    return RecurringTask(
      recurrenceType: h.recurrenceType,
      frequency: h.frequency,
      daysOfWeek: h.daysOfWeek,
      dayOfMonth: h.dayOfMonth ?? 1,
      startDate: start,
      endDate: until,
    );
  }

  Future<String> addHabit(Habit h) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final data = removeNulls(h.toJson())..remove('id');
    data['createdAt'] = now;
    data['modifiedAt'] = now;
    final ref = await habitCollection(_uid).add(data);
    h.id = ref.id;
    h.createdAt = now;
    await ensureInstances(h);
    return ref.id;
  }

  /// Rolling top-up: materialize the scheduled dates from (lastMaterialized+1 or
  /// today) through today+horizon. Idempotent: it skips any date that already
  /// has an instance, so a null/stale lastMaterializedDate (e.g. after an edit)
  /// can never produce duplicates. The in-memory guard prevents concurrent runs.
  Future<void> ensureInstances(Habit h, {int horizonDays = 60}) async {
    if (h.status != 'active' || h.id == null) return;
    if (_materializing.contains(h.id)) return;
    _materializing.add(h.id!);
    try {
      final todayStr = _dates.getString(DateTime.now());
      final today = _dates.getDate(todayStr);
      final start = _dates.getDate(h.startDate);
      // Dates that already have an instance for this habit — the authoritative
      // record of what exists. (Collection-group query on (userId, habitId);
      // null if the index isn't ready.)
      final snap = await _habitInstanceQuery(h.id!);
      final Set<String>? existingDates =
          snap?.docs.map((d) => d.data()['dueDate'] as String?).whereType<String>().toSet();

      // When that query is available it — not the watermark — decides the window,
      // so the whole horizon is scanned from today and any date missing BEHIND
      // the watermark is backfilled.
      //
      // The watermark alone could not do this. It advances on loop completion,
      // and addTask cannot report otherwise: ackWrite deliberately swallows
      // failures (WriteAck.failed) and timeouts (WriteAck.queued) so a form is
      // never left hanging. So a write that failed, or was stranded in the
      // offline queue and lost, still moved the watermark past its date — and
      // that date could never be regenerated. Editing a habit hit this hardest,
      // since updateHabit deletes the future before regenerating it.
      DateTime windowStart = start.isAfter(today) ? start : today;
      if (existingDates == null && h.lastMaterializedDate != null) {
        final next = _dates.getDate(h.lastMaterializedDate!).add(const Duration(days: 1));
        if (next.isAfter(windowStart)) windowStart = next;
      }
      final until = today.add(Duration(days: horizonDays));
      if (windowStart.isAfter(until)) return;

      final template = _toRecurringTask(h, start: windowStart, until: until);
      final instances = _taskService.generateInstancesInWindow(template, windowStart);
      String? lastDate = h.lastMaterializedDate;
      for (final inst in instances) {
        final dateStr = _dates.getString(inst);
        if (existingDates != null && existingDates.contains(dateStr)) {
          lastDate = dateStr;
          continue;
        }
        await _taskService.addTask(Task(
          added: DateTime.now().millisecondsSinceEpoch,
          title: h.title,
          priority: h.effort,
          completed: false,
          dueDate: dateStr,
          habitId: h.id,
        ));
        lastDate = dateStr;
      }
      if (lastDate != null && lastDate != h.lastMaterializedDate) {
        h.lastMaterializedDate = lastDate;
        await habitCollection(_uid).doc(h.id).update({'lastMaterializedDate': lastDate});
      }
    } finally {
      _materializing.remove(h.id);
    }
  }

  /// Toggle a habit instance's completion and recompute the streak. Scoring
  /// stays in updateTaskByKey/the card (Effort points); the streak is separate.
  Future<void> toggleComplete(Task instance, bool completed) async {
    const fmt = "${DateService.stringFmt} ${DateService.dbTimeFormat}";
    await _taskService.updateTaskByKey({
      'completed': completed,
      'completedTime': completed ? DateFormat(fmt).format(DateTime.now()) : null,
    }, instance);
    if (instance.habitId != null) await recomputeStreakById(instance.habitId!);
  }

  Future<void> recomputeStreakById(String id) async {
    final h = await getHabit(id);
    if (h != null) await recomputeStreak(h);
  }

  /// Streak = consecutive most-recent scheduled occurrences completed. Today,
  /// if scheduled but not yet completed, is treated as pending (not a miss).
  Future<void> recomputeStreak(Habit h) async {
    if (h.id == null) return;
    final snap = await _habitInstanceQuery(h.id!);
    if (snap == null) return; // index not ready — skip rather than clobber the streak
    final completedByDate = <String, bool>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final date = data['dueDate'] as String?;
      if (date != null) completedByDate[date] = (data['completed'] as bool?) ?? false;
    }
    final todayStr = _dates.getString(DateTime.now());
    final start = _dates.getDate(h.startDate);
    final today = _dates.getDate(todayStr);
    final template = _toRecurringTask(h, start: start, until: today);
    final scheduled = _taskService
        .generateInstancesInWindow(template, start)
        .map((d) => _dates.getString(d))
        .where((d) => d.compareTo(todayStr) <= 0)
        .toList();

    int i = scheduled.length - 1;
    if (i >= 0 && scheduled[i] == todayStr && !(completedByDate[todayStr] ?? false)) {
      i--; // today is pending, not a miss
    }
    int streak = 0;
    String? lastCompleted;
    for (; i >= 0; i--) {
      final date = scheduled[i];
      if (completedByDate[date] == true) {
        streak++;
        lastCompleted ??= date;
      } else {
        break;
      }
    }

    await habitCollection(_uid).doc(h.id).update({
      'currentStreak': streak,
      'longestStreak': max(h.longestStreak, streak),
      'lastCompletedDate': lastCompleted,
      'modifiedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> updateHabit(Habit h) async {
    final data = h.toJson()
      ..remove('id')
      ..remove('currentStreak')
      ..remove('longestStreak')
      ..remove('lastCompletedDate')
      ..remove('createdAt');
    data['modifiedAt'] = DateTime.now().millisecondsSinceEpoch;
    data['lastMaterializedDate'] = null; // force regeneration of the future
    await habitCollection(_uid).doc(h.id).update(data);
    h.lastMaterializedDate = null;
    await _deleteFutureIncomplete(h.id!);
    await ensureInstances(h);
  }

  Future<void> pauseHabit(Habit h) async {
    await habitCollection(_uid).doc(h.id).update({
      'status': 'paused',
      'modifiedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _deleteFutureIncomplete(h.id!);
  }

  Future<void> resumeHabit(Habit h) async {
    await habitCollection(_uid).doc(h.id).update({
      'status': 'active',
      'modifiedAt': DateTime.now().millisecondsSinceEpoch,
    });
    h.status = 'active';
    await ensureInstances(h);
  }

  Future<void> deleteHabit(Habit h) async {
    // Remove the template first so the habit clears from the UI immediately,
    // then clean up its future instances in the background (best-effort).
    await habitCollection(_uid).doc(h.id).delete();
    unawaited(_deleteFutureIncomplete(h.id!)
        .catchError((e) => debugPrint('Habit instance cleanup failed: $e')));
  }

  // Delete a habit's future incomplete instances (preserve completed history).
  // Deletions run in parallel so cleanup of a long horizon isn't slow.
  Future<void> _deleteFutureIncomplete(String habitId) async {
    final todayStr = _dates.getString(DateTime.now());
    final instances = await _habitInstances(habitId);
    await Future.wait(instances
        .where((t) => !t.completed && t.dueDate != null && t.dueDate!.compareTo(todayStr) >= 0)
        .map((t) => _taskService.deleteTask(t)));
  }

  // These collection-group reads need the (userId, habitId) index. If it isn't
  // deployed yet they fail with failed-precondition; degrade gracefully (return
  // empty) so habit management (delete/toggle) still works — streak/cleanup
  // simply wait for the index. Callers treat an empty result as "no instances".
  Future<QuerySnapshot<Map<String, dynamic>>?> _habitInstanceQuery(String habitId) async {
    try {
      return await _db
          .collectionGroup('items')
          .where('userId', isEqualTo: _uid)
          .where('habitId', isEqualTo: habitId)
          .get();
    } catch (e) {
      debugPrint('Habit instance query failed (index building?): $e');
      return null;
    }
  }

  Future<List<Task>> _habitInstances(String habitId) async {
    final snap = await _habitInstanceQuery(habitId);
    if (snap == null) return [];
    return snap.docs.map((doc) {
      final data = {...doc.data(), 'id': doc.id};
      data['tags'] = <dynamic>[];
      return Task.fromJson(data);
    }).toList();
  }
}
