import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/shared/shared.dart';

class ReminderService {
  ReminderService._internal();
  static final _instance = ReminderService._internal();
  factory ReminderService() => _instance;

  // `late` so merely constructing the service doesn't touch Firebase — the
  // series paths call ReminderService() unconditionally, and eager
  // initialisation made those untestable under `flutter test`.
  late final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final _taskService = TaskService();

  Future<void> scheduleReminder(Task task) async {
    if (task.reminderTime == null || task.id == null) return;

    final taskDate = task.dueDate ?? TaskService.defaultUnassignedDate;
    final callable = _functions.httpsCallable('scheduleReminder');
    final result = await callable.call<Map<String, dynamic>>({
      'taskId': task.id,
      'taskDate': taskDate,
      'reminderTime': task.reminderTime,
      'title': task.title,
    });

    final reminderTaskName = result.data['reminderTaskName'] as String;
    await _taskService.updateTaskByKey({'reminderTaskName': reminderTaskName}, task);
    debugPrint('Reminder scheduled: $reminderTaskName');
  }

  Future<void> cancelReminder(Task task) async {
    if (task.reminderTaskName == null) return;

    final callable = _functions.httpsCallable('cancelReminder');
    await callable.call({'reminderTaskName': task.reminderTaskName});
    await _taskService.updateTaskByKey({
      'reminderTaskName': null,
      'reminderTime': null,
    }, task);
    debugPrint('Reminder cancelled');
  }

  Future<void> updateReminder(Task task, String newTime) async {
    if (task.reminderTaskName != null) {
      final callable = _functions.httpsCallable('cancelReminder');
      await callable.call({'reminderTaskName': task.reminderTaskName});
    }

    await _taskService.updateTaskByKey({'reminderTime': newTime}, task);
    final updated = task.copyWith(reminderTime: newTime);
    await scheduleReminder(updated);
  }

  /// Hands the reminders on [occurrences] to Cloud Tasks — but only those due
  /// inside the enqueue window and not already scheduled.
  ///
  /// `reminderTaskName == null` is both the dedupe and the retry marker: an
  /// occurrence left unscheduled (by the cap, by an error, or by a pass dying
  /// halfway) is simply picked up next time, so truncation here is safe.
  ///
  /// Returns how many were left un-enqueued by the per-pass cap, so a caller with
  /// user context can say scheduling is still in progress.
  /// Set [reportFailures] false for background work: the launch-time top-up runs
  /// unprompted, and a failure there (offline at launch, say) would otherwise
  /// raise an error snackbar the user did not ask for and cannot act on. The
  /// occurrence keeps a null reminderTaskName either way, so the next pass
  /// retries it.
  Future<int> enqueueDueReminders(
    List<Task> occurrences, {
    DateTime? now,
    bool reportFailures = true,
  }) async {
    final at = now ?? DateTime.now();
    final due = occurrences
        .where((t) =>
            t.reminderTime != null &&
            t.reminderTaskName == null &&
            RecurringSeries.isWithinEnqueueWindow(t.reminderTime!, now: at))
        .toList();
    if (due.isEmpty) return 0;

    final enqueueing = due.take(RecurringSeries.reminderEnqueueCapPerPass).toList();
    for (final task in enqueueing) {
      try {
        await scheduleReminder(task);
      } catch (e, s) {
        // Leave reminderTaskName null so the next pass retries this occurrence.
        if (reportFailures) {
          reportError(e, s, "Couldn't schedule a reminder");
        } else {
          debugPrint("Couldn't schedule a reminder for ${task.id}: $e\n$s");
        }
      }
    }
    return due.length - enqueueing.length;
  }
}
