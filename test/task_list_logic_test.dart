import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/task_list/task_list_logic.dart';

void main() {
  Task t(String id,
          {int childCount = 0,
          String? parentId,
          String type = 'task',
          Effort priority = Effort.low,
          bool completed = false}) =>
      Task(
          id: id,
          added: 1,
          title: id,
          childCount: childCount,
          parentId: parentId,
          type: type,
          priority: priority,
          completed: completed);

  group('visibleTasks', () {
    final tasks = [t('plain'), t('parent', childCount: 2), t('child', parentId: 'parent')];

    test('a day hides container parents but shows subtasks scheduled there', () {
      expect(TaskListLogic.visibleTasks(tasks, isBacklog: false).map((x) => x.id), ['plain', 'child']);
    });

    test('the backlog hides subtasks (nested under their parent) but shows parents', () {
      expect(TaskListLogic.visibleTasks(tasks, isBacklog: true).map((x) => x.id), ['plain', 'parent']);
    });
  });

  test('childrenByParent groups subtasks and ignores rows without a parent', () {
    final grouped = TaskListLogic.childrenByParent([
      t('c1', parentId: 'p'),
      t('orphan'),
      t('c2', parentId: 'p'),
      t('c3', parentId: 'q'),
    ]);
    expect(grouped.keys, ['p', 'q']);
    expect(grouped['p']!.map((x) => x.id), ['c1', 'c2']);
  });

  test('habitStreaksById skips habits without an id', () {
    final streaks = TaskListLogic.habitStreaksById([
      Habit(id: 'h1', title: 'a', startDate: '2026-01-01', currentStreak: 4),
      Habit(title: 'b', startDate: '2026-01-01', currentStreak: 9),
    ]);
    expect(streaks, {'h1': 4});
  });

  group('mergeVisibleOrder', () {
    test('refills only the visible slots so hidden ids keep their positions', () {
      final full = ['a', 'H1', 'b', 'c', 'H2'];
      final merged = TaskListLogic.mergeVisibleOrder(full, {'a', 'b', 'c'}, ['c', 'a', 'b']);
      expect(merged, ['c', 'H1', 'a', 'b', 'H2']);
      expect(full, ['a', 'H1', 'b', 'c', 'H2'], reason: 'input untouched');
    });

    test('with nothing hidden it is just the new order', () {
      expect(TaskListLogic.mergeVisibleOrder(['a', 'b'], {'a', 'b'}, ['b', 'a']), ['b', 'a']);
    });
  });

  group('reorder (ReorderableListView semantics)', () {
    const ids = ['a', 'b', 'c', 'd'];
    test('moving down lands one slot short of newIndex', () {
      expect(TaskListLogic.reorder(ids, 0, 2), ['b', 'a', 'c', 'd']);
    });
    test('moving up lands exactly at newIndex', () {
      expect(TaskListLogic.reorder(ids, 3, 1), ['a', 'd', 'b', 'c']);
    });
    test('dropping past the end appends', () {
      expect(TaskListLogic.reorder(ids, 1, 4), ['a', 'c', 'd', 'b']);
    });
    test('dropping in place is a no-op', () {
      expect(TaskListLogic.reorder(ids, 2, 2), ids);
      expect(TaskListLogic.reorder(ids, 2, 3), ids);
    });
  });

  test('moveToEnd sends the completed row to the bottom', () {
    expect(TaskListLogic.moveToEnd(['a', 'b', 'c'], 0), ['b', 'c', 'a']);
    expect(TaskListLogic.moveToEnd(['a', 'b', 'c'], 2), ['a', 'b', 'c']);
  });

  group('upcomingCountdowns', () {
    DateTime parse(String s) => DateTime.parse(s);
    test('keeps only future dates, soonest first', () {
      final rows = [
        {'title': 'later', 'dueDate': '2026-10-01'},
        {'title': 'today', 'dueDate': '2026-09-19'},
        {'title': 'soon', 'dueDate': '2026-09-21'},
        {'title': 'none'},
        {'title': 'past', 'dueDate': '2026-09-01'},
      ];
      final chips = TaskListLogic.upcomingCountdowns(rows, DateTime(2026, 9, 19), parse);
      expect(chips.map((c) => c['title']), ['soon', 'later']);
    });
  });

  test('countdownChipText prefers a non-blank label over the title', () {
    expect(TaskListLogic.countdownChipText({'title': 'Trip', 'label': 'Paris'}), 'Paris');
    expect(TaskListLogic.countdownChipText({'title': 'Trip', 'label': '  '}), 'Trip');
    expect(TaskListLogic.countdownChipText({'title': 'Trip'}), 'Trip');
  });

  test('swipeDayDelta: right swipe goes back a day, left goes forward, jitter ignored', () {
    expect(TaskListLogic.swipeDayDelta(40), -1);
    expect(TaskListLogic.swipeDayDelta(-40), 1);
    expect(TaskListLogic.swipeDayDelta(10), 0);
    expect(TaskListLogic.swipeDayDelta(-10), 0);
    expect(TaskListLogic.swipeDayDelta(3), 0);
  });

  test('progress sums effort points and ignores dividers', () {
    int score(Effort e) => switch (e) {
          Effort.high => 3,
          Effort.medium => 2,
          Effort.low => 1,
          Effort.info => 0,
        };
    final p = TaskListLogic.progress([
      t('a', priority: Effort.high, completed: true),
      t('b', priority: Effort.medium),
      t('c', priority: Effort.low, completed: true),
      t('d', type: 'divider', priority: Effort.high, completed: true),
    ], score);
    expect(p.completed, 4);
    expect(p.total, 6);
  });
}
