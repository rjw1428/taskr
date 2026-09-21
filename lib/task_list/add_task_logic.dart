import 'package:taskr/services/models.dart';

/// What the save path must do about a task's reminder once the form's value is
/// compared with what was stored.
enum ReminderTransition { none, schedule, cancel, update }

/// Pure form logic behind [AddTaskScreen]: value normalisation and the
/// decisions the save path makes. No widgets, no services.
class AddTaskLogic {
  AddTaskLogic._();

  /// `MM/dd h:mm AM` for the reminder picker row. Takes a local [DateTime] so
  /// the caller decides the zone.
  static String formatReminder(DateTime dt) {
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$month/$day $hour:$minute $period';
  }

  /// The label stored on a countdown task: null when the countdown is off or
  /// the field is blank, so the chip falls back to the title.
  static String? countdownLabel(bool countdown, String text) {
    if (!countdown) return null;
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Drops the recurrence fields that don't apply to the chosen type, so a
  /// template edited back and forth in the form doesn't keep stale settings.
  static RecurringTask normalizeTemplate(RecurringTask template, DateTime startDate) {
    template.startDate = startDate;
    if (template.recurrenceType != 'Weekly') template.daysOfWeek = null;
    if (template.recurrenceType == 'Yearly' || template.recurrenceType == 'Daily') {
      template.frequency = null;
    }
    if (template.recurrenceType != 'Monthly') template.dayOfMonth = null;
    return template;
  }

  /// Days covered by a multi-day task, inclusive of both ends. Fewer than two
  /// means it isn't a multi-day task at all.
  static int multiDayCount(DateTime start, DateTime end) => end.difference(start).inDays + 1;

  static String multiDayPosition(int index, int dayCount) {
    if (index == 0) return 'start';
    if (index == dayCount - 1) return 'end';
    return 'middle';
  }

  /// Which reminder call an edit needs, given the stored and the new instant.
  static ReminderTransition reminderTransition(String? stored, String? updated) {
    if (stored == updated) return ReminderTransition.none;
    if (updated == null) return ReminderTransition.cancel;
    if (stored == null) return ReminderTransition.schedule;
    return ReminderTransition.update;
  }

  /// Stored as a UTC instant (with 'Z') so the backend resolves the same
  /// absolute moment regardless of server timezone.
  static String reminderInstant(DateTime date, int hour, int minute) {
    return DateTime(date.year, date.month, date.day, hour, minute).toUtc().toIso8601String();
  }
}
