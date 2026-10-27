import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/date.service.dart';
import 'package:taskr/services/models.dart';

void main() {
  final ds = DateService();

  group('DateService.isTimeLessThan', () {
    test('earlier hour is less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 11, minute: 0)), isTrue);
    });
    test('same hour, earlier minute is less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 9, minute: 15), const TimeOfDay(hour: 9, minute: 30)), isTrue);
    });
    test('equal times are not less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 9, minute: 0), const TimeOfDay(hour: 9, minute: 0)), isFalse);
    });
    test('minutes count as fractions of an hour, not multiples', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 9, minute: 45), const TimeOfDay(hour: 10, minute: 0)), isTrue);
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 10, minute: 0), const TimeOfDay(hour: 9, minute: 59)), isFalse);
    });
    test('later is not less', () {
      expect(ds.isTimeLessThan(const TimeOfDay(hour: 14, minute: 0), const TimeOfDay(hour: 9, minute: 0)), isFalse);
    });
  });

  group('DateService.getTime', () {
    test('parses 24h db format', () {
      final time = ds.getTime('13:45');
      expect(time.hour, 13);
      expect(time.minute, 45);
    });
  });

  group('DateService date math', () {
    test('increment/decrement round-trip', () {
      final start = ds.getDate('2026-08-01');
      final next = ds.incrementDate(start); // '2026-08-02'
      expect(next, '2026-08-02');
      expect(ds.decrementDate(ds.getDate(next)), '2026-08-01');
    });

    test('increment rolls over month end', () {
      expect(ds.incrementDate(ds.getDate('2026-08-31')), '2026-09-01');
    });

    test('isDateLessThan compares chronologically', () {
      expect(ds.isDateLessThan('2026-08-01', '2026-08-02'), isTrue);
      expect(ds.isDateLessThan('2026-08-02', '2026-08-01'), isFalse);
    });

    test('daysAgo subtracts whole days', () {
      expect(ds.daysAgo(DateTime.utc(2026, 3, 10), 10), DateTime.utc(2026, 2, 28));
    });

    test('increment crosses the days the clocks change', () {
      // In US zones 2026-11-01 is 25 hours long and 2026-03-08 is 23, so the
      // old `add(Duration(days: 1))` landed back on 11-01 — the date scroller
      // could not move past it. The next-calendar-day invariant below holds in
      // every zone, so this test is not tied to the machine's own.
      expect(ds.incrementDate(ds.getDate('2026-11-01')), '2026-11-02');
      expect(ds.decrementDate(ds.getDate('2026-11-02')), '2026-11-01');
      expect(ds.incrementDate(ds.getDate('2026-03-08')), '2026-03-09');
      expect(ds.decrementDate(ds.getDate('2026-03-09')), '2026-03-08');
    });

    test('walking a year forward visits every date exactly once', () {
      var d = ds.getDate('2026-01-01');
      final seen = <String>[];
      for (var i = 0; i < 400; i++) {
        seen.add(ds.getString(d));
        d = DateService.shiftDays(d, 1);
      }
      expect(seen.toSet(), hasLength(400), reason: 'a repeated date means a day was lost');
      expect(seen.last, '2027-02-04');
    });

    test('daysBetween counts calendar days across both clock changes', () {
      // The week containing the spring-forward is 167 hours, so inDays used to
      // report 6 and a multi-day task lost its last day.
      expect(DateService.daysBetween(ds.getDate('2026-03-08'), ds.getDate('2026-03-15')), 7);
      expect(DateService.daysBetween(ds.getDate('2026-11-01'), ds.getDate('2026-11-08')), 7);
      expect(DateService.daysBetween(ds.getDate('2026-11-01'), ds.getDate('2026-11-02')), 1);
      expect(DateService.daysBetween(ds.getDate('2026-11-02'), ds.getDate('2026-11-01')), -1);
      expect(DateService.daysBetween(ds.getDate('2026-11-01'), ds.getDate('2026-11-01')), 0);
    });

    test('daysBetween ignores the time of day', () {
      expect(
        DateService.daysBetween(DateTime(2026, 11, 1, 23, 59), DateTime(2026, 11, 2, 0, 1)),
        1,
      );
    });

    test('shiftDays keeps the wall-clock time and the UTC flag', () {
      final local = DateService.shiftDays(DateTime(2026, 11, 1, 9, 30), 1);
      expect([local.year, local.month, local.day, local.hour, local.minute], [2026, 11, 2, 9, 30]);
      expect(local.isUtc, isFalse);
      expect(DateService.shiftDays(DateTime.utc(2026, 11, 1), 1).isUtc, isTrue);
    });
  });

  group('selected date', () {
    test('setSelectedDate is what getSelectedDate returns', () {
      final d = DateTime(2024, 5, 6);
      ds.setSelectedDate(d);
      expect(ds.getSelectedDate(), d);
      expect(ds.selectedDate, d);
    });
  });

  group('formatting', () {
    final d = DateTime(2026, 3, 4, 14, 5);

    test('getString, getTimeStr and getShortDay', () {
      expect(ds.getString(d), '2026-03-04');
      expect(ds.getTimeStr(d), '14:05');
      expect(ds.getShortDay(d), '03/04');
    });

    test('displayTime renders 12h with am/pm', () {
      expect(ds.displayTime('14:05'), '2:05 PM');
      expect(ds.displayTime('00:30'), '12:30 AM');
    });

    test('getDayOfWeek and getDayOfWeekByIndex', () {
      expect(ds.getDayOfWeek(d), 'Wednesday');
      expect(ds.getDayOfWeekByIndex(0), 'Mon');
      expect(ds.getDayOfWeekByIndex(6), 'Sun');
    });

    test('getMonth abbreviates the month number', () {
      expect(ds.getMonth(1), 'Jan');
      expect(ds.getMonth(12), 'Dec');
    });

    test('dayAxisLabel names the weekday N days back', () {
      final expected = DateFormat('E').format(DateTime.now().subtract(const Duration(days: 3)));
      expect(ds.dayAxisLabel(3), expected);
      expect(ds.dayAxisLabel(0), DateFormat('E').format(DateTime.now()));
    });

    test('getRoundedTime moves to the top of the next hour', () {
      final t = ds.getRoundedTime(const TimeOfDay(hour: 9, minute: 41));
      expect(t.hour, 10);
      expect(t.minute, 0);
    });
  });

  group('timeFrameBuilder', () {
    Task task({String? date = '2026-08-01', String? start, String? end}) =>
        Task(added: 1, title: 'x', dueDate: date, startTime: start, endTime: end);

    test('nothing without a due date', () {
      expect(ds.timeFrameBuilder(task(date: null, start: '09:00')), '');
      expect(ds.timeFrameBuilder(task(date: '', start: '09:00')), '');
    });

    test('nothing without a start time', () {
      expect(ds.timeFrameBuilder(task()), '');
    });

    test('start only, and a start-end range', () {
      expect(ds.timeFrameBuilder(task(start: '09:00')), '9:00 AM');
      expect(ds.timeFrameBuilder(task(start: '09:00', end: '17:30')), '9:00 AM - 5:30 PM');
    });

    test('an unparseable time degrades to nothing', () {
      expect(ds.timeFrameBuilder(task(start: 'noon')), '');
      expect(ds.timeFrameBuilder(task(start: '09:00', end: 'later')), '');
    });
  });

  group('isToday', () {
    test('matches only the current calendar day', () {
      final now = DateTime.now();
      expect(ds.isToday(ds.getString(now)), isTrue);
      expect(ds.isToday(ds.incrementDate(now)), isFalse);
      expect(ds.isToday(ds.decrementDate(now)), isFalse);
    });
  });

  group('relativeTime', () {
    int ago(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch;

    test('covers every bucket', () {
      expect(ds.relativeTime(ago(const Duration(seconds: 10))), 'just now');
      expect(ds.relativeTime(ago(const Duration(minutes: 5))), '5m ago');
      expect(ds.relativeTime(ago(const Duration(hours: 3))), '3h ago');
      expect(ds.relativeTime(ago(const Duration(days: 2))), '2d ago');
      final old = DateTime.now().subtract(const Duration(days: 30));
      expect(ds.relativeTime(old.millisecondsSinceEpoch), ds.getString(old));
    });
  });

  group('DateService.getRoundedTime', () {
    test('rounds up to the top of the next hour', () {
      expect(ds.getRoundedTime(const TimeOfDay(hour: 9, minute: 5)), const TimeOfDay(hour: 10, minute: 0));
      expect(ds.getRoundedTime(const TimeOfDay(hour: 9, minute: 0)), const TimeOfDay(hour: 10, minute: 0));
    });
    test('wraps to midnight after 11pm instead of producing hour 24', () {
      expect(ds.getRoundedTime(const TimeOfDay(hour: 23, minute: 30)), const TimeOfDay(hour: 0, minute: 0));
    });
    test('nowTime follows the injected clock', () {
      ds.clock = () => DateTime(2026, 9, 19, 14, 45);
      expect(ds.nowTime(), const TimeOfDay(hour: 14, minute: 45));
    });
  });
}
