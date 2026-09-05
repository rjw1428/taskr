import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/date.service.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/reminder.service.dart';
import 'package:taskr/services/task.service.dart';
import 'package:taskr/shared/write_ack.dart';

/// Keeps recurring series materialized on a rolling horizon, and hands their
/// reminders to Cloud Tasks as they come into range.
///
/// This is the recurring-task counterpart to [HabitService.ensureInstances] and
/// deliberately shares its contract: a `lastMaterializedDate` watermark, a
/// collection-group query as the authoritative dedupe, and an in-memory guard
/// against concurrent passes. Creation writes only the first horizon; everything
/// past it is this service's job.
class RecurringSeriesService {
  RecurringSeriesService._internal();
  static final _instance = RecurringSeriesService._internal();
  factory RecurringSeriesService() => _instance;

  // `late` so a test can inject a fake before the real instance is touched
  // (Firebase isn't initialized under `flutter test`).
  late FirebaseFirestore _db = FirebaseFirestore.instance;
  final TaskService _taskService = TaskService();
  final DateService _dates = DateService();

  @visibleForTesting
  set db(FirebaseFirestore db) {
    _db = db;
    // ignore: invalid_use_of_visible_for_testing_member
    _taskService.db = db; // keep the wrapped TaskService on the same fake
  }

  // Guards against two concurrent passes over the same series duplicating work.
  static final Set<String> _materializing = {};

  // One pass per launch is enough for a 60-day horizon; this stops a rebuild or
  // a second auth event from starting another.
  static bool _passRan = false;

  @visibleForTesting
  static void resetPassGuard() => _passRan = false;

  /// Tops up every series once per launch. Safe to call more than once — later
  /// calls are no-ops until [resetPassGuard].
  Future<void> runLaunchPass() async {
    if (_passRan) return;
    _passRan = true;
    await topUpAllSeries();
  }

  /// Extends every series to the horizon and enqueues newly-due reminders.
  Future<void> topUpAllSeries() async {
    final user = AuthService().user;
    if (user == null) return;
    try {
      final snap = await _db.collection('todos').doc(user.uid).collection('recurring').get();
      for (final doc in snap.docs) {
        final template = RecurringTask.fromJson(doc.data())..id = doc.id;
        await ensureInstances(template);
      }
    } catch (e, s) {
      // A failed pass costs nothing the next launch cannot recover.
      debugPrint('Recurring top-up pass failed: $e\n$s');
    }
  }

  /// Rolling top-up for one series: materialize from the watermark (or today) to
  /// `today + horizon`, then enqueue any reminders that have come into range.
  ///
  /// Idempotent. The collection-group query — not the watermark — decides what
  /// already exists, so a null or stale `lastMaterializedDate` (a series created
  /// before this change, or one interrupted mid-write) can never duplicate.
  Future<void> ensureInstances(RecurringTask template) async {
    final id = template.id;
    if (id == null) return;
    if (_materializing.contains(id)) return;
    _materializing.add(id);
    try {
      final today = _dates.getDate(_dates.getString(DateTime.now()));

      // Past its end date: nothing left to materialize.
      if (template.endDate != null && template.endDate!.isBefore(today)) return;

      // Only today onwards can collide with what the horizon generates, so the
      // read is bounded there. A series with nothing upcoming still needs an
      // occurrence to copy from, so only then is its history read.
      var existing = await _taskService.seriesInstances(id, fromDate: _dates.getString(today));
      if (existing != null && existing.isEmpty) {
        existing = await _taskService.seriesInstances(id);
      }
      final existingDates = existing?.map((t) => t.dueDate).whereType<String>().toSet();

      // The watermark is only a fallback for when the collection-group query is
      // unavailable. When the query works it is the authority on what exists, so
      // the whole horizon is scanned and dates missing BEHIND the watermark are
      // backfilled rather than lost.
      //
      // Trusting the watermark as a starting point is what made the equivalent
      // habit path lose a series: it advances on loop completion, and the write
      // helpers cannot report failure (ackWrite swallows both errors and
      // timeouts by design), so a failed or offline-stranded write still moved
      // the watermark past its date, permanently.
      DateTime? from;
      if (existingDates == null && template.lastMaterializedDate != null) {
        from = _dates.getDate(template.lastMaterializedDate!).add(const Duration(days: 1));
      }

      final dates = RecurringSeries.occurrencesInHorizon(template, today: today, from: from)
          .where((d) => existingDates == null || !existingDates.contains(_dates.getString(d)))
          .toList();

      var written = const <Task>[];
      if (dates.isNotEmpty) {
        final result = await _taskService.materializeOccurrences(
          templateId: id,
          template: template,
          prototype: _prototypeFrom(existing, template),
          dates: dates,
        );
        // A queued (offline) write is still real: the SDK delivers it later,
        // and its reminder should not wait for another launch.
        if (result.ack != WriteAck.failed) written = result.occurrences;
      }

      await _enqueueReminders(id, [...?existing, ...written]);
    } catch (e, s) {
      debugPrint('Top-up failed for series $id: $e\n$s');
    } finally {
      _materializing.remove(id);
    }
  }

  /// New occurrences copy an existing one, so title, effort, tags and times stay
  /// consistent with the rest of the series. Prefers an outstanding occurrence;
  /// a completed one still carries the right fields.
  Task _prototypeFrom(List<Task>? existing, RecurringTask template) {
    final source = (existing ?? const <Task>[]).isEmpty
        ? null
        : (existing!.firstWhere((t) => !t.completed, orElse: () => existing.first));
    if (source == null) {
      // No occurrence to copy: the series has nothing materialized to base a new
      // one on, so there is nothing meaningful to extend it with.
      throw StateError('No existing occurrence to model series ${template.id} on');
    }
    return source.copyWith(
      id: null,
      completed: false,
      pushCount: 0,
      added: DateTime.now().millisecondsSinceEpoch,
    )
      ..id = null
      ..reminderTime = null
      ..reminderTaskName = null
      ..childCount = 0
      ..childCompletedCount = 0;
  }

  /// Enqueues reminders that have come into the Cloud Tasks window. Silent by
  /// design: this runs at launch, where a notice about reminder scheduling is
  /// something the user can neither expect nor act on.
  Future<void> _enqueueReminders(String templateId, List<Task> occurrences) async {
    // No re-read: the caller already holds the upcoming occurrences plus the
    // ones it just wrote, which are exactly the ones that may need scheduling.
    if (occurrences.isEmpty) return;
    final deferred = await ReminderService().enqueueDueReminders(occurrences, reportFailures: false);
    if (deferred > 0) {
      debugPrint('Series $templateId: $deferred reminder(s) deferred to a later pass');
    }
  }
}
