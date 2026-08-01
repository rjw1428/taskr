import 'package:taskr/services/date.service.dart';
import 'package:taskr/shared/constants.dart';

/// Pure task-ordering logic used by [TaskService.addTask]. Extracted so the
/// insertion rules can be unit-tested without Firestore.
///
/// A task in [existing] is a plain map with (at least) `id`, `completed`
/// (bool), `startTime` (String?), `endTime` (String?) and `priority` (the
/// serialized Effort name, e.g. `'info'`), in current display order.
/// [insertionIndex] returns where a newly added task's id should slot in,
/// preserving the order of everything else. The target layout of the incomplete
/// run, top to bottom, is:
///
///   [untimed Info] → [timed, chronological] → [untimed non-Info] → [completed]
///
/// The rules, in priority order:
///
///   1. An untimed Info task pins to the very top of the list.
///   2. New tasks always sit ahead of completed ones (stop at the first
///      completed task).
///   3. Timed tasks (start or end time) sit ahead of untimed tasks, and in time
///      order among themselves. So a new timed task stops at the first untimed
///      non-Info task or the first timed task scheduled later than it — but
///      flows past pinned untimed Info tasks so they stay on top.
///
/// A new untimed (non-Info) task has no time key, so nothing but a completed
/// task stops it — it lands at the end of the incomplete run, below the timed
/// tasks and any earlier untimed ones. An Info task that *does* have a time
/// follows normal timed placement.
class TaskOrdering {
  static int insertionIndex(
    List<Map<String, dynamic>> existing, {
    required Effort priority,
    String? startTime,
    String? endTime,
  }) {
    final newTime = startTime ?? endTime;
    final isTopPinnedInfo = priority == Effort.info && newTime == null;
    if (isTopPinnedInfo) return 0;

    for (int i = 0; i < existing.length; i++) {
      final t = existing[i];
      if (t['completed'] == true) return i;
      if (newTime != null) {
        final tTime = (t['startTime'] ?? t['endTime']) as String?;
        if (tTime == null) {
          // Untimed task: a new timed task goes above it — unless it's a pinned
          // Info task, which stays on top, so skip past it.
          if (t['priority'] == 'info') continue;
          return i;
        }
        if (DateService().isTimeLessThan(DateService().getTime(newTime), DateService().getTime(tTime))) {
          return i;
        }
      }
    }
    return existing.length;
  }

  /// Returns the full new `taskOrder` after inserting [id] into [existing]'s
  /// id list at the computed [insertionIndex].
  static List<String> insertInto(
    List<Map<String, dynamic>> existing,
    String id, {
    required Effort priority,
    String? startTime,
    String? endTime,
  }) {
    final order = existing.map((t) => t['id'] as String).toList();
    final at = insertionIndex(existing, priority: priority, startTime: startTime, endTime: endTime);
    return [...order.sublist(0, at), id, ...order.sublist(at)];
  }
}
