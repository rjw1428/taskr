import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/task_list/add_task_logic.dart';

void main() {
  group('formatReminder', () {
    test('renders 12-hour time with zero-padded month, day and minute', () {
      expect(AddTaskLogic.formatReminder(DateTime(2026, 3, 7, 14, 5)), '03/07 2:05 PM');
      expect(AddTaskLogic.formatReminder(DateTime(2026, 11, 23, 9, 30)), '11/23 9:30 AM');
    });
    test('midnight and noon', () {
      expect(AddTaskLogic.formatReminder(DateTime(2026, 1, 1, 0, 0)), '01/01 12:00 AM');
      expect(AddTaskLogic.formatReminder(DateTime(2026, 1, 1, 12, 0)), '01/01 12:00 PM');
    });
  });

  test('countdownLabel is null when off or blank, trimmed otherwise', () {
    expect(AddTaskLogic.countdownLabel(false, 'Paris'), isNull);
    expect(AddTaskLogic.countdownLabel(true, '   '), isNull);
    expect(AddTaskLogic.countdownLabel(true, ' Paris '), 'Paris');
  });

  group('normalizeTemplate', () {
    RecurringTask full(String type) => RecurringTask(
          recurrenceType: type,
          frequency: 2,
          daysOfWeek: {'Mon': true},
          dayOfMonth: 15,
        );
    final start = DateTime(2026, 9, 14);

    test('Weekly keeps daysOfWeek and frequency, drops dayOfMonth', () {
      final r = AddTaskLogic.normalizeTemplate(full('Weekly'), start);
      expect(r.startDate, start);
      expect(r.daysOfWeek, {'Mon': true});
      expect(r.frequency, 2);
      expect(r.dayOfMonth, isNull);
    });

    test('Monthly keeps dayOfMonth and frequency, drops daysOfWeek', () {
      final r = AddTaskLogic.normalizeTemplate(full('Monthly'), start);
      expect(r.daysOfWeek, isNull);
      expect(r.frequency, 2);
      expect(r.dayOfMonth, 15);
    });

    test('Daily and Yearly drop everything but the type', () {
      for (final type in ['Daily', 'Yearly']) {
        final r = AddTaskLogic.normalizeTemplate(full(type), start);
        expect(r.daysOfWeek, isNull, reason: type);
        expect(r.frequency, isNull, reason: type);
        expect(r.dayOfMonth, isNull, reason: type);
      }
    });
  });

  group('multi-day', () {
    test('day count is inclusive of both ends', () {
      expect(AddTaskLogic.multiDayCount(DateTime(2026, 9, 1), DateTime(2026, 9, 3)), 3);
      expect(AddTaskLogic.multiDayCount(DateTime(2026, 9, 1), DateTime(2026, 9, 1)), 1);
    });
    test('positions mark start, middle and end', () {
      expect([for (var i = 0; i < 4; i++) AddTaskLogic.multiDayPosition(i, 4)],
          ['start', 'middle', 'middle', 'end']);
      expect([for (var i = 0; i < 2; i++) AddTaskLogic.multiDayPosition(i, 2)], ['start', 'end']);
    });
  });

  group('reminderTransition', () {
    test('unchanged, including both unset, needs nothing', () {
      expect(AddTaskLogic.reminderTransition(null, null), ReminderTransition.none);
      expect(AddTaskLogic.reminderTransition('a', 'a'), ReminderTransition.none);
    });
    test('clearing cancels, adding schedules, changing updates', () {
      expect(AddTaskLogic.reminderTransition('a', null), ReminderTransition.cancel);
      expect(AddTaskLogic.reminderTransition(null, 'a'), ReminderTransition.schedule);
      expect(AddTaskLogic.reminderTransition('a', 'b'), ReminderTransition.update);
    });
  });

  test('reminderInstant stores a UTC ISO string that round-trips to the chosen local time', () {
    final iso = AddTaskLogic.reminderInstant(DateTime(2026, 9, 14), 8, 30);
    expect(iso, endsWith('Z'));
    expect(DateTime.parse(iso).toLocal(), DateTime(2026, 9, 14, 8, 30));
  });
}
