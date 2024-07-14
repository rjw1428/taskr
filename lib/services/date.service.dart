import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';

class DateService {
  DateService._internal();
  static final _instance = DateService._internal();
  static const stringFmt = 'yyyy-MM-dd';

  factory DateService() {
    return _instance;
  }

  String getString(DateTime d) {
    return DateFormat(stringFmt).format(d);
  }

  DateTime getDate(String dateStr) {
    return DateFormat(stringFmt).parse(dateStr);
  }

  String getDayOfWeek(DateTime d) {
    return DateFormat.EEEE().format(d);
  }

  String incrementDate(DateTime d) {
    final update = d.add(const Duration(days: 1));
    return DateFormat(stringFmt).format(update);
  }

  String decrementDate(DateTime d) {
    final update = d.subtract(const Duration(days: 1));
    return DateFormat(stringFmt).format(update);
  }

  String timeFrameBuilder(Task task) {
    if (task.dueDate == null || task.dueDate == '') {
      return '';
    }
    try {
      final parsedDate = DateFormat(stringFmt).parse(task.dueDate!);
      final dueDate = DateFormat('MM/dd').format(parsedDate);
      final startTime = task.startTime;
      if (startTime == null) {
        return dueDate;
      }
      final endTime = task.endTime;
      if (endTime == null) {
        return startTime;
      }
      return "$startTime - $endTime";
    } catch (e) {
      print("Error: ${task.dueDate}");
      return '';
    }
  }
}
