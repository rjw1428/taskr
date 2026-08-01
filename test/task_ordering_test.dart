import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/task_ordering.dart';
import 'package:taskr/shared/constants.dart';

/// Builds a task map in the shape [TaskOrdering] expects.
Map<String, dynamic> t(String id,
        {bool completed = false, String? start, String? end, String priority = 'medium'}) =>
    {'id': id, 'completed': completed, 'startTime': start, 'endTime': end, 'priority': priority};

void main() {
  // insertionIndex + insertInto are the placement rules extracted from
  // TaskService.addTask. These lock in behavior we've regressed on twice.
  group('TaskOrdering.insertionIndex', () {
    test('empty list -> index 0', () {
      expect(TaskOrdering.insertionIndex([], priority: Effort.medium), 0);
    });

    test('untimed task lands after incomplete, before completed', () {
      final existing = [t('a'), t('b'), t('done', completed: true)];
      expect(TaskOrdering.insertionIndex(existing, priority: Effort.medium), 2);
    });

    test('untimed task with no completed tasks lands at the end', () {
      final existing = [t('a'), t('b')];
      expect(TaskOrdering.insertionIndex(existing, priority: Effort.low), 2);
    });

    test('a new untimed task lands below timed tasks', () {
      final existing = [t('9', start: '09:00'), t('11', start: '11:00')];
      expect(TaskOrdering.insertionIndex(existing, priority: Effort.medium), 2);
    });

    test('never places after a completed task', () {
      final existing = [t('done', completed: true), t('after', completed: true)];
      expect(TaskOrdering.insertionIndex(existing, priority: Effort.high), 0);
    });

    group('timed placement', () {
      test('slots chronologically among timed tasks', () {
        final existing = [t('9', start: '09:00'), t('11', start: '11:00')];
        // 10:00 goes between 9 and 11 -> index 1
        expect(TaskOrdering.insertionIndex(existing, priority: Effort.medium, startTime: '10:00'), 1);
      });

      test('later than all timed tasks -> end (before completed)', () {
        final existing = [t('9', start: '09:00'), t('11', start: '11:00'), t('done', completed: true)];
        expect(TaskOrdering.insertionIndex(existing, priority: Effort.medium, startTime: '14:00'), 2);
      });

      test('earlier than all timed tasks -> front', () {
        final existing = [t('9', start: '09:00'), t('11', start: '11:00')];
        expect(TaskOrdering.insertionIndex(existing, priority: Effort.medium, startTime: '07:00'), 0);
      });

      test('a new timed task slots into the timed group above untimed tasks', () {
        final existing = [t('9', start: '09:00'), t('11', start: '11:00'), t('note')];
        expect(TaskOrdering.insertInto(existing, 'x', priority: Effort.medium, startTime: '10:00'),
            ['9', 'x', '11', 'note']);
      });

      test('a new timed task goes above an existing untimed task', () {
        final existing = [t('note')];
        expect(TaskOrdering.insertInto(existing, 'x', priority: Effort.medium, startTime: '09:00'),
            ['x', 'note']);
      });

      test('a new timed task stays below a pinned untimed Info task', () {
        final existing = [t('info', priority: 'info'), t('9', start: '09:00')];
        expect(TaskOrdering.insertInto(existing, 'x', priority: Effort.medium, startTime: '08:00'),
            ['info', 'x', '9']);
      });

      test('endTime is used when startTime is null', () {
        final existing = [t('9', start: '09:00'), t('13', start: '13:00')];
        expect(TaskOrdering.insertionIndex(existing, priority: Effort.medium, endTime: '11:00'), 1);
      });
    });

    group('Info pinning', () {
      test('untimed Info task pins to the very top', () {
        final existing = [t('a'), t('b')];
        expect(TaskOrdering.insertionIndex(existing, priority: Effort.info), 0);
      });

      test('untimed Info pins above other untimed Info too', () {
        final existing = [t('info1'), t('a')];
        expect(TaskOrdering.insertInto(existing, 'info2', priority: Effort.info), ['info2', 'info1', 'a']);
      });

      test('Info task WITH a time follows normal timed placement', () {
        final existing = [t('9', start: '09:00'), t('11', start: '11:00')];
        // Not pinned: 10:00 slots between the timed tasks.
        expect(TaskOrdering.insertionIndex(existing, priority: Effort.info, startTime: '10:00'), 1);
      });
    });
  });
}
