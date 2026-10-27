import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';

class DateService {
  DateService._internal();
  static DateService _instance = DateService._internal();

  /// Drops all state so the next `DateService()` starts fresh.
  @visibleForTesting
  static void resetInstance() => _instance = DateService._internal();
  static const stringFmt = 'yyyy-MM-dd';
  static const dbTimeFormat = 'HH:mm';
  static const displayTimeFormat = 'h:mm aa';
  var selectedDate = DateTime.now();
  factory DateService() {
    return _instance;
  }

  /// Clock, swappable so pickers that default to "now" are deterministic under test.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// The current instant.
  DateTime now() => clock();

  /// The current wall-clock time of day.
  TimeOfDay nowTime() => TimeOfDay.fromDateTime(clock());

  DateTime getSelectedDate() {
    return selectedDate;
  }

  void setSelectedDate(DateTime d) {
    selectedDate = d;
  }

  String getString(DateTime d) {
    return DateFormat(stringFmt).format(d);
  }

  String getTimeStr(DateTime t) {
    return DateFormat(dbTimeFormat).format(t);
  }

  String getShortDay(DateTime t) {
    return DateFormat('MM/dd').format(t);
  }

  TimeOfDay getTime(String time) {
    final t = DateFormat(dbTimeFormat).parse(time);
    return TimeOfDay(hour: t.hour, minute: t.minute);
  }

  String displayTime(String time) {
    final t = DateFormat(dbTimeFormat).parse(time);
    return DateFormat(displayTimeFormat).format(t);
  }

  DateTime getDate(String dateStr) {
    return DateFormat(stringFmt).parse(dateStr);
  }

  String getDayOfWeek(DateTime d) {
    return DateFormat.EEEE().format(d);
  }

  String getMonth(int month) {
    final now = DateTime.now();
    return DateFormat('MMM').format(DateTime(now.year, month, 1));
  }

  /// Shifts [d] by whole calendar days, forward or back.
  ///
  /// `add(Duration(days: 1))` adds 24 hours, which is not a day when the clocks
  /// change. 2026-11-01 is 25 hours long in New York, so midnight plus 24 hours
  /// is 23:00 on the *same* date — which froze the date scroller on that day and
  /// made goal-task generation emit it twice and skip the 2nd. Rebuilding from
  /// the calendar components lets DateTime normalize the day instead, and leaves
  /// the wall-clock time alone.
  ///
  /// UTC-ness is preserved: callers that already work in UTC (see
  /// RecurringSeries.utcDate) are immune to this and must stay that way.
  static DateTime shiftDays(DateTime d, int days) => d.isUtc
      ? DateTime.utc(d.year, d.month, d.day + days, d.hour, d.minute, d.second, d.millisecond)
      : DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second, d.millisecond);

  /// Whole calendar days from [from] to [to], ignoring the time of day.
  ///
  /// `to.difference(from).inDays` counts 24-hour blocks and then truncates, so
  /// a week containing a spring-forward is 6 days and 23 hours — it reports 6.
  /// Comparing the dates in UTC removes the offset from the subtraction, the
  /// same trick RecurringSeries.utcDate uses.
  static int daysBetween(DateTime from, DateTime to) {
    final a = DateTime.utc(from.year, from.month, from.day);
    final b = DateTime.utc(to.year, to.month, to.day);
    return b.difference(a).inDays;
  }

  String dayAxisLabel(int daysBack) {
    final newDate = shiftDays(DateTime.now(), -daysBack);
    return DateFormat('E').format(newDate);
  }

  String incrementDate(DateTime d) {
    return DateFormat(stringFmt).format(shiftDays(d, 1));
  }

  String decrementDate(DateTime d) {
    return DateFormat(stringFmt).format(shiftDays(d, -1));
  }

  DateTime daysAgo(DateTime startDate, int days) {
    return shiftDays(startDate, -days);
  }

  String timeFrameBuilder(Task task) {
    if (task.dueDate == null || task.dueDate == '') {
      return '';
    }
    try {
      if (task.startTime == null) {
        return '';
      }
      final stime = DateFormat(dbTimeFormat).parse(task.startTime!);
      final startTime = DateFormat(displayTimeFormat).format(stime);
      if (task.endTime == null) {
        return startTime;
      }
      final etime = DateFormat(dbTimeFormat).parse(task.endTime!);
      final endTime = DateFormat(displayTimeFormat).format(etime);
      return "$startTime - $endTime";
    } catch (e) {
      debugPrint("Error: ${task.dueDate}");
      debugPrint(e.toString());
      return '';
    }
  }

  bool isTimeLessThan(TimeOfDay a, TimeOfDay b) {
    double toDouble(TimeOfDay a) => a.hour + a.minute / 60.0;
    return toDouble(a) < toDouble(b);
  }

  bool isDateLessThan(String a, String b) {
    final aDate = DateFormat(stringFmt).parse(a);
    final bDate = DateFormat(stringFmt).parse(b);
    return aDate.isBefore(bDate);
  }

  /// The top of the next hour. Wraps past 23:00 so a picker opened late in the
  /// evening gets a valid time instead of hour 24.
  TimeOfDay getRoundedTime(TimeOfDay t) {
    return TimeOfDay(hour: (t.hour + 1) % 24, minute: 0);
  }

  String getDayOfWeekByIndex(int index) {
    final daysOfWeek = [
      "Mon",
      "Tues",
      "Wed",
      "Thurs",
      "Fri",
      "Sat",
      "Sun",
    ];
    return daysOfWeek[index];
  }

  bool isToday(String date) {
    final today = DateTime.now();
    final parsedDate = DateFormat(stringFmt).parse(date);
    return parsedDate.year == today.year && parsedDate.month == today.month && parsedDate.day == today.day;
  }

  /// Compact "time ago" label for an epoch-ms timestamp (notification center).
  String relativeTime(int epochMs) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return getString(d);
  }
}
