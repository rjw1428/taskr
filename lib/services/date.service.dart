import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';

class DateService {
  DateService._internal();
  static final _instance = DateService._internal();
  static const stringFmt = 'yyyy-MM-dd';
  static const dbTimeFormat = 'HH:mm';
  static const displayTimeFormat = 'h:mm aa';
  var selectedDate = DateTime.now();
  factory DateService() {
    return _instance;
  }

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

  String dayAxisLabel(int daysBack) {
    final now = DateTime.now();
    final newDate = now.subtract(Duration(days: daysBack));
    return DateFormat('E').format(newDate);
  }

  String incrementDate(DateTime d) {
    final update = d.add(const Duration(days: 1));
    return DateFormat(stringFmt).format(update);
  }

  String decrementDate(DateTime d) {
    final update = d.subtract(const Duration(days: 1));
    return DateFormat(stringFmt).format(update);
  }

  DateTime daysAgo(DateTime startDate, int days) {
    return startDate.subtract(Duration(days: days));
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
      print("Error: ${task.dueDate}");
      print(e);
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

  TimeOfDay getRoundedTime(TimeOfDay t) {
    return TimeOfDay(hour: t.hour + 1, minute: 0);
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
}
