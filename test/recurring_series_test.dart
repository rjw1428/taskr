import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';

void main() {
  RecurringTask weekly({
    required DateTime start,
    required DateTime end,
    int every = 1,
    Map<String, bool>? days,
    String? reminder,
  }) =>
      RecurringTask(
        recurrenceType: 'Weekly',
        frequency: every,
        daysOfWeek: days ?? const {'Mo': true},
        startDate: start,
        endDate: end,
        reminderTimeOfDay: reminder,
      );

  RecurringTask daily({required DateTime start, required DateTime end}) => RecurringTask(
        recurrenceType: 'Daily',
        frequency: 1,
        startDate: start,
        endDate: end,
      );

  group('occurrencesInHorizon', () {
    // 2026-01-05 is a Monday.
    final today = DateTime.utc(2026, 1, 5);

    test('a series shorter than the horizon is materialized in full', () {
      // Every Monday for 3 weeks.
      final t = weekly(start: today, end: DateTime.utc(2026, 1, 26));
      final dates = RecurringSeries.occurrencesInHorizon(t, today: today);
      expect(dates.length, 4); // Jan 5, 12, 19, 26
      expect(dates.first, DateTime.utc(2026, 1, 5));
      expect(dates.last, DateTime.utc(2026, 1, 26));
    });

    test('a series longer than the horizon stops at the horizon', () {
      final t = daily(start: today, end: DateTime.utc(2026, 12, 31));
      final dates = RecurringSeries.occurrencesInHorizon(t, today: today);
      // Inclusive of both ends of [today, today+60].
      expect(dates.length, RecurringSeries.horizonDays + 1);
      expect(dates.last, today.add(const Duration(days: RecurringSeries.horizonDays)));
    });

    test('the yearly every-3-weeks case that motivated this change', () {
      final t = weekly(start: today, end: DateTime.utc(2027, 1, 5), every: 3);
      final dates = RecurringSeries.occurrencesInHorizon(t, today: today);
      // 60-day horizon at a 21-day cadence: Jan 5, Jan 26, Feb 16, Mar 9.
      expect(dates.length, 3);
      expect(dates, [
        DateTime.utc(2026, 1, 5),
        DateTime.utc(2026, 1, 26),
        DateTime.utc(2026, 2, 16),
      ]);
    });

    test('a series starting beyond the horizon still yields its first occurrence', () {
      final start = DateTime.utc(2026, 7, 6); // ~6 months out, well past the horizon
      final t = weekly(start: start, end: DateTime.utc(2026, 12, 28));
      final dates = RecurringSeries.occurrencesInHorizon(t, today: today);
      // Saving must always produce a visible task.
      expect(dates, [start]);
    });

    test('the end date bounds the series before the horizon does', () {
      final t = daily(start: today, end: DateTime.utc(2026, 1, 8));
      final dates = RecurringSeries.occurrencesInHorizon(t, today: today);
      expect(dates.length, 4); // Jan 5..8
      expect(dates.last, DateTime.utc(2026, 1, 8));
    });

    test('from resumes after the watermark and does not force a first occurrence', () {
      final t = daily(start: today, end: DateTime.utc(2026, 12, 31));
      final dates = RecurringSeries.occurrencesInHorizon(
        t,
        today: today,
        from: DateTime.utc(2026, 3, 1),
      );
      expect(dates.first, DateTime.utc(2026, 3, 1));
      expect(dates.last, today.add(const Duration(days: RecurringSeries.horizonDays)));
    });

    test('a top-up past the horizon yields nothing rather than a stray occurrence', () {
      final t = daily(start: today, end: DateTime.utc(2026, 12, 31));
      final dates = RecurringSeries.occurrencesInHorizon(
        t,
        today: today,
        from: DateTime.utc(2026, 6, 1), // beyond today+60
      );
      expect(dates, isEmpty);
    });

    test('a weekly template with no day selected still produces a series', () {
      final t = weekly(start: today, end: DateTime.utc(2026, 2, 2), days: const {});
      final dates = RecurringSeries.occurrencesInHorizon(t, today: today);
      expect(dates, isNotEmpty);
    });
  });

  group('reminderInstantFor', () {
    test('resolves the local time of day on the occurrence date', () {
      final instant = RecurringSeries.reminderInstantFor('08:30', DateTime(2026, 1, 5));
      final local = DateTime.parse(instant!).toLocal();
      expect(local.year, 2026);
      expect(local.month, 1);
      expect(local.day, 5);
      expect(local.hour, 8);
      expect(local.minute, 30);
    });

    test('each occurrence gets its own date, not the first one repeated', () {
      final a = RecurringSeries.reminderInstantFor('08:30', DateTime(2026, 1, 5));
      final b = RecurringSeries.reminderInstantFor('08:30', DateTime(2026, 1, 26));
      expect(DateTime.parse(a!).toLocal().day, 5);
      expect(DateTime.parse(b!).toLocal().day, 26);
    });

    test('holds 08:30 local across a DST boundary', () {
      // Whatever the runner's zone, 08:30 must stay 08:30 on BOTH dates. If the
      // series stored a single UTC offset instead of resolving per occurrence,
      // one of these would drift by an hour in a DST-observing zone.
      final winter = RecurringSeries.reminderInstantFor('08:30', DateTime(2026, 1, 15));
      final summer = RecurringSeries.reminderInstantFor('08:30', DateTime(2026, 7, 15));
      final w = DateTime.parse(winter!).toLocal();
      final s = DateTime.parse(summer!).toLocal();
      expect(w.hour, 8);
      expect(w.minute, 30);
      expect(s.hour, 8);
      expect(s.minute, 30);
    });

    test('null time of day yields no reminder', () {
      expect(RecurringSeries.reminderInstantFor(null, DateTime(2026, 1, 5)), isNull);
    });

    test('an unparseable time yields no reminder rather than throwing', () {
      expect(RecurringSeries.reminderInstantFor('not-a-time', DateTime(2026, 1, 5)), isNull);
      expect(RecurringSeries.reminderInstantFor('99:99', DateTime(2026, 1, 5)), isNull);
    });
  });

  group('isWithinEnqueueWindow', () {
    final now = DateTime.utc(2026, 1, 5, 12);

    test('accepts an instant inside the Cloud Tasks ceiling', () {
      final at = now.add(const Duration(days: 10)).toIso8601String();
      expect(RecurringSeries.isWithinEnqueueWindow(at, now: now), isTrue);
    });

    test('rejects an instant beyond the ceiling', () {
      final at = now.add(const Duration(days: 45)).toIso8601String();
      expect(RecurringSeries.isWithinEnqueueWindow(at, now: now), isFalse);
    });

    test('rejects a past-due instant', () {
      final at = now.subtract(const Duration(hours: 1)).toIso8601String();
      expect(RecurringSeries.isWithinEnqueueWindow(at, now: now), isFalse);
    });

    test('the window is exactly the Cloud Tasks ceiling', () {
      expect(RecurringSeries.reminderEnqueueWindowDays, 30);
      final justInside =
          now.add(const Duration(days: RecurringSeries.reminderEnqueueWindowDays - 1)).toIso8601String();
      expect(RecurringSeries.isWithinEnqueueWindow(justInside, now: now), isTrue);
    });
  });
}
