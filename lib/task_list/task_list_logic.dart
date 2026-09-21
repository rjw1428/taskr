import 'package:taskr/services/models.dart';
import 'package:taskr/shared/constants.dart';

/// Pure list-shaping logic behind [TaskListScreen]: what is rendered, how a
/// drag or completion is merged back into the persisted order, and which
/// countdown chips show. No widgets, no services, so it is unit testable.
class TaskListLogic {
  TaskListLogic._();

  /// Rows actually rendered at the top level: hide container parents on a day
  /// (they live only in the backlog), and hide subtasks in the backlog (they're
  /// shown nested under their parent).
  static List<Task> visibleTasks(List<Task> tasks, {required bool isBacklog}) {
    return [
      for (final task in tasks)
        if (isBacklog ? !task.isSubtask : !task.isParent) task,
    ];
  }

  /// Backlog nesting: every subtask keyed by its parent id, in stream order.
  static Map<String, List<Task>> childrenByParent(List<Task> subtasks) {
    final out = <String, List<Task>>{};
    for (final s in subtasks) {
      if (s.parentId != null) (out[s.parentId!] ??= []).add(s);
    }
    return out;
  }

  static Map<String, int> habitStreaksById(List<Habit> habits) {
    return {
      for (final h in habits)
        if (h.id != null) h.id!: h.currentStreak,
    };
  }

  /// Reorder/complete operate on the visible subset. This merges the new
  /// visible order back into the full partition order so hidden ids keep their
  /// positions: the slots previously occupied by visible ids are refilled, in
  /// order, with [newVisibleIds].
  static List<String> mergeVisibleOrder(
      List<String> fullIds, Set<String> visibleIds, List<String> newVisibleIds) {
    final merged = List<String>.from(fullIds);
    final positions = <int>[];
    for (int k = 0; k < merged.length; k++) {
      if (visibleIds.contains(merged[k])) positions.add(k);
    }
    for (int k = 0; k < positions.length && k < newVisibleIds.length; k++) {
      merged[positions[k]] = newVisibleIds[k];
    }
    return merged;
  }

  /// [ReorderableListView.onReorder] semantics: [newIndex] is the drop slot in
  /// the list *before* removal, so a downward move lands one short of it.
  static List<String> reorder(List<String> ids, int oldIndex, int newIndex) {
    final out = List<String>.from(ids);
    if (newIndex >= out.length) {
      out.add(out.removeAt(oldIndex));
    } else {
      final delta = newIndex > oldIndex ? -1 : 0;
      out.insert(newIndex + delta, out.removeAt(oldIndex));
    }
    return out;
  }

  /// Completing a task sends it to the bottom of the list.
  static List<String> moveToEnd(List<String> ids, int index) {
    final out = List<String>.from(ids);
    out.add(out.removeAt(index));
    return out;
  }

  /// Countdown chips for the day in view: only ones still ahead of [viewed],
  /// soonest first. Rows carry `dueDate` as yyyy-MM-dd, which sorts lexically.
  static List<Map<String, dynamic>> upcomingCountdowns(
      List<Map<String, dynamic>> countdowns, DateTime viewed, DateTime Function(String) parse) {
    final chips = countdowns.where((cd) {
      final due = cd['dueDate'] as String?;
      if (due == null) return false;
      return parse(due).isAfter(viewed);
    }).toList()
      ..sort((a, b) => (a['dueDate'] as String).compareTo(b['dueDate'] as String));
    return chips;
  }

  /// A chip shows its label when one is set, else the task title.
  static String countdownChipText(Map<String, dynamic> countdown) {
    final label = (countdown['label'] as String?)?.trim();
    return label != null && label.isNotEmpty ? label : countdown['title'] as String;
  }

  /// Horizontal swipe on the list: +1 moves to the next day, -1 to the
  /// previous, 0 ignores a jitter shorter than the threshold.
  static int swipeDayDelta(double dragDelta, {double threshold = 10}) {
    if (dragDelta > threshold) return -1;
    if (dragDelta < -threshold) return 1;
    return 0;
  }

  /// Daily progress numerator/denominator: effort points for the rendered
  /// tasks, dividers excluded.
  static ({int completed, int total}) progress(List<Task> visible, int Function(Effort) score) {
    var completed = 0;
    var total = 0;
    for (final task in visible) {
      if (task.isDivider) continue;
      final points = score(task.priority);
      total += points;
      if (task.completed) completed += points;
    }
    return (completed: completed, total: total);
  }
}
