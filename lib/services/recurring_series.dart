import 'package:intl/intl.dart';
import 'package:rrule/rrule.dart';
import 'package:taskr/services/date.service.dart';
import 'package:taskr/services/models.dart';

/// Pure logic for recurring task series: how far ahead occurrences are
/// materialized, how far ahead reminders can be enqueued, and how a series'
/// time-of-day reminder resolves to an absolute instant on each occurrence.
///
/// Kept free of Firestore so it can be unit tested directly (see
/// `test/recurring_series_test.dart`).
class RecurringSeries {
  RecurringSeries._();

  /// How far ahead occurrences are materialized. Matches
  /// [HabitService.ensureInstances]'s default so the two features behave alike,
  /// but is defaulted independently — the shared contract is the watermark +
  /// dedupe + top-up shape, not this number.
  static const horizonDays = 60;

  /// How far ahead reminders can be handed to Cloud Tasks. This is a platform
  /// ceiling, not a preference: Cloud Tasks rejects a `scheduleTime` more than
  /// 30 days out. Deliberately shorter than [horizonDays] — occurrences past it
  /// already carry their `reminderTime` and are enqueued by a later pass.
  static const reminderEnqueueWindowDays = 30;

  /// Most reminders one top-up pass will enqueue. Each costs a callable round
  /// trip, so a long daily series converges across launches instead of firing
  /// dozens of sequential RPCs. Safe to truncate: the enqueue guard is
  /// `reminderTaskName == null`, so leftovers are simply picked up next pass.
  static const reminderEnqueueCapPerPass = 10;

  /// Firestore caps a WriteBatch at 500 operations. Chunk below that, leaving
  /// headroom for the template write and per-occurrence countdown syncs.
  static const batchChunkSize = 400;

  /// The absolute instant at which a series' [reminderTimeOfDay] (local `HH:mm`)
  /// falls on [occurrenceDate], as the UTC ISO-8601 string `Task.reminderTime`
  /// already uses.
  ///
  /// Resolving per occurrence — rather than storing one offset for the series —
  /// is what makes this DST-correct: 08:30 in November and 08:30 in July are
  /// different UTC instants, and only the occurrence's own local date knows
  /// which offset applies. It is also why no server component needs a timezone.
  ///
  /// Returns null when [reminderTimeOfDay] is null or unparseable.
  static String? reminderInstantFor(String? reminderTimeOfDay, DateTime occurrenceDate) {
    if (reminderTimeOfDay == null) return null;
    final DateTime t;
    try {
      t = DateFormat(DateService.dbTimeFormat).parseStrict(reminderTimeOfDay);
    } catch (_) {
      return null;
    }
    // Local constructor, so the offset resolved is the one in force on that date.
    final local = DateTime(
      occurrenceDate.year,
      occurrenceDate.month,
      occurrenceDate.day,
      t.hour,
      t.minute,
    );
    return local.toUtc().toIso8601String();
  }

  /// Whether [reminderInstant] (UTC ISO-8601) is close enough to hand to Cloud
  /// Tasks now. Past-due instants are excluded — there is nothing to schedule.
  static bool isWithinEnqueueWindow(String reminderInstant, {required DateTime now}) {
    final DateTime at;
    try {
      at = DateTime.parse(reminderInstant);
    } catch (_) {
      return false;
    }
    final nowUtc = now.toUtc();
    if (!at.isAfter(nowUtc)) return false;
    return at.isBefore(nowUtc.add(const Duration(days: reminderEnqueueWindowDays)));
  }

  /// Upper bound on RRULE expansion. Templates carry an end date (enforced by
  /// the recurring form) so expansion is finite; this only guards a malformed
  /// template with a missing or far-future end.
  static const _expansionCap = 1000;

  /// A calendar date as UTC midnight.
  ///
  /// Series work in date-space, not instants: occurrences are addressed by day
  /// (`todos/{uid}/tasks/{date}/items`), and a reminder's real instant is derived
  /// separately from the series' time of day. Anchoring the rule with a plain
  /// `.toUtc()` instead dragged the local wall-clock time into the expansion, so
  /// saving in the evening in a negative-offset zone produced a first occurrence
  /// dated tomorrow.
  static DateTime utcDate(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// The RRULE for [template]. Shared by materialization, top-up and delete so
  /// they can never disagree about what a series' occurrences are.
  static RecurrenceRule buildRule(RecurringTask template) {
    final type = recurrenceFrequency(template.recurrenceType);
    final until = template.endDate == null ? null : utcDate(template.endDate!);
    final interval = template.frequency ?? 1;
    switch (template.recurrenceType) {
      case 'Weekly':
        final byWeekDays = weeklyRecurrenceList(template.daysOfWeek ?? const {});
        // A weekly template with no day selected would expand to nothing; fall
        // back to a plain interval so a malformed template still produces a series.
        if (byWeekDays.isEmpty) {
          return RecurrenceRule(frequency: type, interval: interval, until: until);
        }
        return RecurrenceRule(
          frequency: type,
          interval: interval,
          until: until,
          byWeekDays: byWeekDays,
        );
      case 'Monthly':
        return RecurrenceRule(
          frequency: type,
          interval: interval,
          until: until,
          byMonthDays: [template.dayOfMonth ?? 1],
        );
      default:
        return RecurrenceRule(frequency: type, interval: interval, until: until);
    }
  }

  /// Every occurrence of [template] across the whole series. Used by delete.
  static List<DateTime> allOccurrences(RecurringTask template, {required DateTime today}) {
    final start = utcDate(template.startDate ?? today);
    return buildRule(template).getInstances(start: start).take(_expansionCap).toList();
  }

  /// Occurrence dates to materialize: those falling in `[start, today + horizon]`,
  /// bounded by the template's end date.
  ///
  /// Pass [from] on a top-up to resume after the watermark. When [from] is null
  /// this is a creation-time expansion, and the first occurrence is always
  /// included even if the series begins beyond the horizon — otherwise saving a
  /// series that starts months out would produce no visible task at all.
  static List<DateTime> occurrencesInHorizon(
    RecurringTask template, {
    required DateTime today,
    DateTime? from,
    int horizon = horizonDays,
  }) {
    final seriesStart = utcDate(template.startDate ?? today);
    final horizonEnd = utcDate(today).add(Duration(days: horizon));
    final fromDate = from == null ? null : utcDate(from);
    final windowStart = (fromDate != null && fromDate.isAfter(seriesStart)) ? fromDate : seriesStart;

    final expanded = buildRule(template).getInstances(start: seriesStart).take(_expansionCap);

    final result = <DateTime>[];
    for (final instance in expanded) {
      if (instance.isAfter(horizonEnd)) break;
      if (instance.isBefore(windowStart)) continue;
      result.add(instance);
    }

    if (result.isEmpty && from == null) {
      final first = expanded.take(1).toList();
      if (first.isNotEmpty) return first;
    }
    return result;
  }
}

Frequency recurrenceFrequency(String templateRecurrance) {
  if (templateRecurrance == 'Daily') return Frequency.daily;
  if (templateRecurrance == 'Weekly') return Frequency.weekly;
  if (templateRecurrance == 'Monthly') return Frequency.monthly;
  if (templateRecurrance == 'Yearly') return Frequency.yearly;
  throw Exception('Invalid recurrence type');
}

List<ByWeekDayEntry> weeklyRecurrenceList(Map<String, bool> daysOfWeek) {
  const dayNumbers = {
    'Su': DateTime.sunday,
    'Mo': DateTime.monday,
    'Tu': DateTime.tuesday,
    'We': DateTime.wednesday,
    'Th': DateTime.thursday,
    'Fr': DateTime.friday,
    'Sa': DateTime.saturday,
  };
  return daysOfWeek.entries
      .where((e) => e.value && dayNumbers.containsKey(e.key))
      .map((e) => ByWeekDayEntry(dayNumbers[e.key]!))
      .toList();
}
