import 'dart:async';

import 'package:algoliasearch/algoliasearch_lite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/task_ordering.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/shared/shared.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

/// Outcome of materializing a series: the template id, the occurrences actually
/// written (so the caller can enqueue their reminders), and how the commit landed.
class RecurringSeriesWrite {
  final String templateId;
  final List<Task> occurrences;
  final WriteAck ack;
  const RecurringSeriesWrite({
    required this.templateId,
    required this.occurrences,
    required this.ack,
  });
}

class TaskService {
  // `late` so a test can inject a fake via [db] before the real instance is
  // touched (Firebase isn't initialized under `flutter test`).
  late FirebaseFirestore _db = FirebaseFirestore.instance;
  static const defaultUnassignedDate = "unassigned";

  @visibleForTesting
  set db(FirebaseFirestore db) => _db = db;

  CollectionReference<Map<String, dynamic>> taskCollection(String userId, String? date) {
    return _db
        .collection('todos')
        .doc(userId)
        .collection('tasks')
        .doc(date ?? defaultUnassignedDate)
        .collection("items");
  }

  CollectionReference<Map<String, dynamic>> recurringTempateCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('recurring');
  }

  CollectionReference<Map<String, dynamic>> countdownCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('countdowns');
  }

  /// Whether [task] belongs in the countdown index. Shared so the batched series
  /// path and [_syncCountdownIndex] can never drift apart.
  bool countdownEligible(Task task) {
    final isNonStartMultiDay = task.multiDayGroupId != null && task.multiDayPosition != 'start';
    return task.countdown && task.dueDate != null && !task.completed && !isNonStartMultiDay;
  }

  Future<void> _syncCountdownIndex(String userId, Task task) async {
    if (task.id == null) return;
    // The countdown index is a denormalized cache; a failure here must never
    // break the primary task write (which would, e.g., leave the add-task form
    // stuck open because the caller never reaches its pop()).
    try {
      final ref = countdownCollection(userId).doc(task.id);
      if (countdownEligible(task)) {
        await ref.set({
          'title': task.title,
          'dueDate': task.dueDate,
          if (task.countdownLabel != null && task.countdownLabel!.isNotEmpty)
            'label': task.countdownLabel,
        });
      } else {
        await ref.delete();
      }
    } catch (_) {
      // Ignore; the index will be reconciled on the next task mutation.
    }
  }

  Stream<List<Map<String, dynamic>>> streamCountdowns(String userId) {
    return countdownCollection(userId).snapshots().map((snap) => snap.docs
        .map((doc) => {'taskId': doc.id, ...doc.data()})
        .toList());
  }

  Stream<List<String>> taskOrderStream(String userId, String? date) {
    return _db
        .collection('todos')
        .doc(userId)
        .collection("tasks")
        .doc(date ?? defaultUnassignedDate)
        .snapshots()
        .map((snapshot) {
      final d = snapshot.data();
      if (d != null && d.containsKey("taskOrder")) {
        return List<String>.from(d["taskOrder"]);
      } else {
        return List<String>.from([]);
      }
    });
  }

  Future<List<String>> getTaskOrder(String userId, String? date) async {
    final ref = await _db.collection('todos').doc(userId).collection("tasks").doc(date ?? defaultUnassignedDate).get();
    final d = ref.data();
    if (d != null && d.containsKey("taskOrder")) {
      return List<String>.from(d["taskOrder"]);
    } else {
      return List<String>.from([]);
    }
  }

  Future<void> updateTaskOrder(String userId, List<String> updatedOrder, String? date) async {
    return await _db
        .collection('todos')
        .doc(userId)
        .collection("tasks")
        .doc(date ?? defaultUnassignedDate)
        .update({"taskOrder": updatedOrder});
  }

  Stream<List<Task>> streamTasks(String userId, String? date, List<Tag> tags) {
    final tagMap = tags.fold({}, (acc, cur) => {...acc, cur.id: cur.toJson()});
    return CombineLatestStream.combine2(
        taskCollection(userId, date ?? defaultUnassignedDate)
            .snapshots()
            .map((snapshot) => snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList())
            .handleError((error) => debugPrint("TASK LIST: $error")),
        taskOrderStream(userId, date ?? defaultUnassignedDate),
        (tasks, order) {
          final taskMap = {for (var t in tasks) t['id'] as String: t};
          return order
              .where((id) => taskMap.containsKey(id))
              .map((id) {
            final task = taskMap[id]!;
            final tagList = (task['tags'] as List).map((tag) {
              if (tag is String) {
                return tagMap[tag];
              } else {
                return tagMap[tag["id"]];
              }
            }).toList();

            task['tags'] = tagList.where((t) => t != null).toList();

            return Task.fromJson(task);
          }).toList();
        }).handleError((error) => debugPrint("SHIT: $error"));
  }

  /// All of a user's subtasks (tasks with a parentId) across every date
  /// partition, via a collection-group query. The backlog groups these by
  /// parentId to nest children under their parent (including scheduled ones,
  /// which live in other date partitions). Requires the (userId, parentId)
  /// collection-group index and the matching security rule.
  Stream<List<Task>> streamSubtasks(String userId, List<Tag> tags) {
    final tagMap = tags.fold({}, (acc, cur) => {...acc, cur.id: cur.toJson()});
    // Rx.retryWhen re-subscribes after an error instead of leaving the stream
    // dead. This is what makes the backlog self-heal while the collection-group
    // index is still building (or after a transient network error) — without it
    // the first error stranded the UI until a manual screen refresh.
    return Rx.retryWhen<List<Task>>(
      () => _db
          .collectionGroup('items')
          .where('userId', isEqualTo: userId)
          .where('parentId', isNotEqualTo: null)
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) {
                final data = {...doc.data(), 'id': doc.id};
                final rawTags = (data['tags'] as List?) ?? [];
                data['tags'] = rawTags
                    .map((tag) => tag is String ? tagMap[tag] : tagMap[tag['id']])
                    .where((t) => t != null)
                    .toList();
                return Task.fromJson(data);
              }).toList()),
      (error, stackTrace) {
        debugPrint("SUBTASKS retry (will re-subscribe): $error");
        return Stream<void>.fromFuture(Future<void>.delayed(const Duration(seconds: 3)));
      },
    );
  }

  /// Effort points "missed" on each of [dates]: tasks still sitting incomplete
  /// in that day's partition. A pushed task moves to the next day's partition
  /// (and is tallied under `pushed`), so what remains here was never completed
  /// and never deferred. Dividers carry no points and are ignored.
  ///
  /// Only pass past dates — today's leftovers aren't missed yet. Emits a map of
  /// date string -> points, updating live as each day's partition changes.
  Stream<Map<String, int>> streamMissedPoints(String userId, List<String> dates) {
    if (dates.isEmpty) return Stream.value(const {});
    final streams = dates.map((date) => taskCollection(userId, date).snapshots().map((snap) {
          var points = 0;
          for (final doc in snap.docs) {
            final data = doc.data();
            if (data['completed'] == true) continue;
            if (data['type'] == 'divider') continue;
            // Matches Task.fromJson's fallback for an absent/unknown priority.
            final priority = Effort.values.firstWhere(
              (e) => e.name == data['priority'],
              orElse: () => Effort.low,
            );
            points += PerformanceService().getScore(priority);
          }
          return points;
        }).handleError((error) => debugPrint("MISSED POINTS ($date): $error")));
    return CombineLatestStream.list(streams)
        .map((values) => {for (int i = 0; i < dates.length; i++) dates[i]: values[i]});
  }

  // ─── Subtasks ──────────────────────────────────────────────────────────

  /// One-time fetch of a parent's children (used for delete + counter recompute).
  Future<List<Task>> getSubtasksOf(String parentId) async {
    final user = AuthService().user!;
    final snap = await _db
        .collectionGroup('items')
        .where('userId', isEqualTo: user.uid)
        .where('parentId', isEqualTo: parentId)
        .get();
    return snap.docs.map((doc) {
      final data = {...doc.data(), 'id': doc.id};
      data['tags'] = <dynamic>[]; // tags are irrelevant to the operations that use this
      return Task.fromJson(data);
    }).toList();
  }

  /// Move a task's document to another date partition, preserving its id and
  /// keeping `taskOrder` consistent on both sides. `targetDate` is a day string
  /// or [defaultUnassignedDate] for the backlog. `extra` merges field overrides.
  Future<void> _relocateTask(Task task, String targetDate, Map<String, dynamic> extra) async {
    final user = AuthService().user!;
    final oldDate = task.dueDate ?? defaultUnassignedDate;
    final id = task.id!;
    final data = removeNulls(task.toDbTask());
    data['userId'] = user.uid;
    if (targetDate == defaultUnassignedDate) {
      data.remove('dueDate');
    } else {
      data['dueDate'] = targetDate;
    }
    data.addAll(extra);
    final tasksDoc = _db.collection('todos').doc(user.uid).collection('tasks');
    await taskCollection(user.uid, targetDate).doc(id).set(data);
    await tasksDoc.doc(targetDate).set({
      'taskOrder': FieldValue.arrayUnion([id])
    }, SetOptions(merge: true));
    if (oldDate != targetDate) {
      await taskCollection(user.uid, oldDate).doc(id).delete();
      await tasksDoc.doc(oldDate).set({
        'taskOrder': FieldValue.arrayRemove([id])
      }, SetOptions(merge: true));
    }
  }

  /// Add a subtask to [parent]. The first child inherits the parent's date and
  /// converts the parent into a backlog-only container (moved to `unassigned`);
  /// later children start unassigned. Adding an incomplete child reopens a
  /// previously-completed parent.
  Future<String> addSubtask(Task parent, String title, {Effort? priority}) async {
    final user = AuthService().user;
    if (user == null) throw "No user logged in when adding subtask";
    if (parent.recurringTemplateId != null || parent.isMultiDay) {
      throw "Recurring and multi-day tasks can't have subtasks";
    }
    final isFirstChild = !parent.isParent;
    final child = Task(
      added: DateTime.now().millisecondsSinceEpoch,
      title: title.trim(),
      priority: priority ?? parent.priority,
      completed: false,
      dueDate: isFirstChild ? parent.dueDate : null,
      parentId: parent.id,
      parentTitle: parent.title,
      tags: const [],
    );
    final childId = await addTask(child);

    if (isFirstChild) {
      // Convert to a container: move to the backlog and seed counters.
      await _relocateTask(parent, defaultUnassignedDate, {
        'childCount': 1,
        'childCompletedCount': 0,
        'completed': false,
      });
    } else {
      await taskCollection(user.uid, defaultUnassignedDate).doc(parent.id!).update({
        'childCount': FieldValue.increment(1),
        'completed': false, // reopen if it had been auto-completed
      });
    }
    return childId;
  }

  /// Toggle a subtask's completion, updating the parent's completed-counter in
  /// the same transaction and auto-completing / reopening the parent.
  Future<void> toggleSubtaskComplete(Task child, bool completed) async {
    final user = AuthService().user!;
    final childDate = child.dueDate ?? defaultUnassignedDate;
    final childRef = taskCollection(user.uid, childDate).doc(child.id!);
    final parentRef = taskCollection(user.uid, defaultUnassignedDate).doc(child.parentId!);
    const completeTimeFormat = "${DateService.stringFmt} ${DateService.dbTimeFormat}";

    // A transaction needs a server round trip — the offline queue can't hold it,
    // so `queueable: false`: a timeout here means the change really was lost.
    await ackWrite(_db.runTransaction((transaction) async {
      final parentSnap = await transaction.get(parentRef);
      transaction.update(childRef, {
        'completed': completed,
        'completedTime': completed ? DateFormat(completeTimeFormat).format(DateTime.now()) : null,
      });
      if (parentSnap.exists) {
        final data = parentSnap.data()!;
        final count = (data['childCount'] as num?)?.toInt() ?? 0;
        var done = ((data['childCompletedCount'] as num?)?.toInt() ?? 0) + (completed ? 1 : -1);
        done = done.clamp(0, count);
        transaction.update(parentRef, {
          'childCompletedCount': done,
          'completed': count > 0 && done >= count,
        });
      }
    }), action: "Couldn't update subtask", queueable: false);
  }

  /// Delete a parent, either removing its children too or orphaning them into
  /// standalone tasks (nulling their parent reference).
  Future<void> deleteParent(Task parent, {required bool keepChildren}) async {
    final user = AuthService().user!;
    final children = await getSubtasksOf(parent.id!);
    for (final child in children) {
      if (keepChildren) {
        final date = child.dueDate ?? defaultUnassignedDate;
        await taskCollection(user.uid, date).doc(child.id!).update({
          'parentId': FieldValue.delete(),
          'parentTitle': FieldValue.delete(),
        });
      } else {
        await deleteTask(child);
      }
    }
    await deleteTask(parent);
  }

  /// Recompute a parent's counters from its actual children (drift recovery).
  Future<void> recomputeParentCounters(String parentId) async {
    final user = AuthService().user!;
    final children = await getSubtasksOf(parentId);
    final count = children.length;
    final done = children.where((c) => c.completed).length;
    await taskCollection(user.uid, defaultUnassignedDate).doc(parentId).update({
      'childCount': count,
      'childCompletedCount': done,
      'completed': count > 0 && done >= count,
    });
  }

  /// Schedule (or unschedule, with `date == null`) a subtask, preserving its
  /// parent link. Moves the child's document to the target partition.
  Future<void> scheduleSubtask(Task child, String? date) async {
    await _relocateTask(child, date ?? defaultUnassignedDate, {});
  }

  /// Delete a single subtask and reconcile its parent's counters (and
  /// auto-complete state) from the remaining children.
  Future<void> deleteSubtask(Task child) async {
    await deleteTask(child);
    if (child.parentId != null) {
      await recomputeParentCounters(child.parentId!);
    }
  }

  /// Assign a date to a parent: cascade only its **unassigned, incomplete**
  /// children onto that date. Hand-dated and completed children are untouched.
  Future<void> assignParentDate(Task parent, String date) async {
    final children = await getSubtasksOf(parent.id!);
    for (final child in children) {
      if (child.completed || child.dueDate != null) continue;
      await _relocateTask(child, date, {});
    }
  }

  Future<List<Map<String, dynamic>>> getTasks(String userId, String? date) async {
    var snapshot = await taskCollection(userId, date ?? defaultUnassignedDate).orderBy('added', descending: true).get();
    return snapshot.docs
        .map((doc) => ({
              ...doc.data(),
              'id': doc.id,
            }))
        .toList();
  }

  /// The date's tasks in `taskOrder` sequence.
  ///
  /// An id listed in `taskOrder` with no matching document is skipped, the same
  /// way [streamTasks] filters the list the user actually sees. It used to
  /// `firstWhere` without an `orElse` and threw `Bad state: No element` — which
  /// aborted the whole save. That happens for real: a doc deleted on another
  /// device, or simply a partially-populated local cache while offline.
  Future<List<Map<String, dynamic>>> getTasksInOrder(String userId, String? date) async {
    final order = await getTaskOrder(userId, date ?? defaultUnassignedDate);
    final tasks = await getTasks(userId, date ?? defaultUnassignedDate);
    final byId = {for (final t in tasks) t['id'] as String: t};
    final missing = order.where((id) => !byId.containsKey(id)).toList();
    if (missing.isNotEmpty) {
      debugPrint('taskOrder for ${date ?? defaultUnassignedDate} lists ${missing.length} unknown id(s): $missing');
    }
    return order.map((id) => byId[id]).whereType<Map<String, dynamic>>().toList();
  }

  Future<String> addDivider(String label, String? date) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding divider";
    }
    final dateKey = date ?? defaultUnassignedDate;
    final data = {
      'title': label,
      'type': 'divider',
      'completed': false,
      'added': DateTime.now().millisecondsSinceEpoch,
      'modified': '',
      'dueDate': dateKey,
      'tags': <String>[],
      'priority': 'low',
      'pushCount': 0,
    };
    final id = await taskCollection(user.uid, dateKey).add(data).then((ref) => ref.id);
    final currentOrder = await getTaskOrder(user.uid, dateKey);
    currentOrder.insert(0, id);
    await _db.collection('todos').doc(user.uid).collection("tasks").doc(dateKey).set({
      "taskOrder": currentOrder
    }, SetOptions(merge: true));
    return id;
  }

  /// Adds [task]. Pass [existingId] to write the doc under a known id instead of
  /// generating a new one — used by [pushTask] to move a task to another day
  /// while preserving its document id, so links keyed off the id (e.g. a goal
  /// generation's `taskIds`) survive the push.
  /// Every write here is *issued* before anything is awaited, then all of them
  /// are ack-waited together. Awaiting one write before issuing the next would
  /// strand the rest when the device is offline: Firestore leaves an
  /// unacknowledged write's future pending forever, so the task document would
  /// land in the local cache while its taskOrder entry never got written — and
  /// the task would be invisible until the app came back online.
  Future<String> addTask(Task task, {String? existingId}) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = task.dueDate ?? defaultUnassignedDate;

    final data = removeNulls(task.toDbTask());
    // Stamp the owner so subtasks can be gathered via a collection-group query
    // across date partitions (see add-subtasks design).
    data['userId'] = user.uid;
    // doc() mints the id client-side, so the caller still gets one when the
    // write is only queued locally (add() would have to wait for the server).
    final ref =
        existingId != null ? taskCollection(user.uid, date).doc(existingId) : taskCollection(user.uid, date).doc();
    final id = ref.id;
    final orderDoc = _db.collection('todos').doc(user.uid).collection("tasks").doc(date);

    final writes = <Future<void>>[ref.set(data)];

    // -- Smart Ordering --
    if (task.dueDate == null) {
      // If backloged, add to end
      writes.add(orderDoc.set({
        "taskOrder": FieldValue.arrayUnion([id])
      }, SetOptions(merge: true)));
    } else {
      // A read, not a write: served from the local cache while offline.
      final tasks = await getTasksInOrder(user.uid, task.dueDate!);
      // Slot the new task in, preserving the order of everything else. See
      // TaskOrdering for the placement rules (Info-pin, before-completed,
      // timed-chronological).
      final newOrder = TaskOrdering.insertInto(
        tasks,
        id,
        priority: task.priority,
        startTime: task.startTime,
        endTime: task.endTime,
      );
      writes.add(orderDoc.set({"taskOrder": newOrder}));
    }

    writes.add(_syncCountdownIndex(user.uid, task.copyWith(id: id)));
    await ackWrite(Future.wait(writes), action: "Couldn't save task");
    return id;
  }

  Future<void> updateTask(String id, Task newTask, Task oldTask) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = newTask.dueDate ?? defaultUnassignedDate;
    final data = removeNulls(newTask.toDbTask());
    data['userId'] = user.uid; // keep owner stamp so collection-group subtask reads still match

    // Issued together, ack-waited once — see addTask.
    final writes = <Future<void>>[
      taskCollection(user.uid, date).doc(id).set(data),
      _syncCountdownIndex(user.uid, newTask.copyWith(id: id)),
    ];
    if (oldTask.completed && newTask.priority != oldTask.priority) {
      // Both read-modify-write the same perf doc, so they stay sequential with
      // respect to each other — just not ahead of the task write.
      writes.add(Future(() async {
        await PerformanceService().updatePerfomanceStats(user.uid, oldTask, false);
        await PerformanceService().updatePerfomanceStats(user.uid, newTask, true);
      }));
    }
    await ackWrite(Future.wait(writes), action: "Couldn't save task");
  }

  Future<void> updateTaskByKey(Map<String, dynamic> update, Task task) async {
    var user = AuthService().user;
    final taskId = task.id!;
    final date = task.dueDate ?? defaultUnassignedDate;
    if (user == null) {
      throw "No user logged in when completing task";
    } else {
      // Issued together, ack-waited once — see addTask.
      final writes = <Future<void>>[taskCollection(user.uid, date).doc(taskId).update(update)];
      if (update.containsKey('completed')) {
        writes.add(PerformanceService().updatePerfomanceStats(user.uid, task, !!update['completed']));
        if (update['completed'] == true && task.countdown) {
          writes.add(countdownCollection(user.uid).doc(taskId).delete().catchError((_) {}));
        }
      }
      await ackWrite(Future.wait(writes), action: "Couldn't update task");
    }
  }

  Future<void> deleteTask(Task task) async {
    var user = AuthService().user;
    final taskId = task.id!;
    final date = task.dueDate ?? defaultUnassignedDate;
    if (user == null) {
      throw "No user logged in when deleting task";
    } else {
      if (task.reminderTaskName != null) {
        // A callable function, not a queueable write: it can't be deferred, but
        // it must not block the delete either.
        unawaited(ReminderService()
            .cancelReminder(task)
            .catchError((Object e, StackTrace s) => reportError(e, s, "Couldn't cancel the task's reminder")));
      }
      // Issued together, ack-waited once — see addTask.
      final writes = <Future<void>>[
        taskCollection(user.uid, date).doc(taskId).delete(),
        _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
          "taskOrder": FieldValue.arrayRemove([taskId])
        }, SetOptions(merge: true)),
      ];
      if (task.completed && !task.isDivider) {
        writes.add(PerformanceService().updatePerfomanceStats(user.uid, task, false));
      }
      if (task.countdown) {
        writes.add(countdownCollection(user.uid).doc(taskId).delete().catchError((_) {}));
      }
      await ackWrite(Future.wait(writes), action: "Couldn't delete task");
    }
  }

  Future<void> restoreTask(Task task) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when restoring task";
    }
    final date = task.dueDate ?? defaultUnassignedDate;

    // Re-create the document (stamp owner for collection-group subtask reads)
    final restoreData = removeNulls(task.toDbTask());
    restoreData['userId'] = user.uid;
    await taskCollection(user.uid, date).doc(task.id!).set(restoreData);

    // Add the task ID back to the taskOrder array
    await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
      "taskOrder": FieldValue.arrayUnion([task.id!])
    }, SetOptions(merge: true));

    // Restore performance stats if the task was completed
    if (task.completed && !task.isDivider) {
      await PerformanceService().updatePerfomanceStats(user.uid, task, true);
    }
  }

  /// The reminder instant a pushed occurrence should carry on its new date, or
  /// null when it has no series reminder to inherit. A deleted template is a
  /// state the app already tolerates (see the orphaned-series view), so it
  /// degrades quietly to no reminder rather than failing the push.
  Future<String?> _seriesReminderFor(Task task) async {
    if (task.recurringTemplateId == null || task.dueDate == null) return null;
    try {
      final template = await getRecurringTemplate(task.recurringTemplateId!);
      if (template.reminderTimeOfDay == null) return null;
      return RecurringSeries.reminderInstantFor(
        template.reminderTimeOfDay,
        DateService().getDate(task.dueDate!),
      );
    } catch (e) {
      debugPrint('No series template for pushed task ${task.id}: $e');
      return null;
    }
  }

  Future<void> pushTask(Task task) async {
    var user = AuthService().user!;
    if (task.reminderTaskName != null) {
      await ReminderService().cancelReminder(task);
    }
    await deleteTask(task);
    final now = DateTime.now();
    // The day the points are being pushed FROM (captured before dueDate is bumped).
    final fromDate = task.dueDate ?? DateService().getString(now);
    final d = task.dueDate != null ? DateService().getDate(task.dueDate!) : now;
    final decrementScore = d.day == now.day && d.month == now.month && d.year == now.year;
    task.dueDate = DateService().incrementDate(d);
    task.pushCount += 1;
    // A series' reminder is a time of day, not a property of the original date,
    // so it follows the task when it moves. Everything else (one-off tasks, a
    // series with no reminder time, an occurrence whose template is gone) keeps
    // the old behaviour of clearing the reminder.
    task.reminderTime = await _seriesReminderFor(task);
    task.reminderTaskName = null;
    // Preserve the document id across the move so id-keyed links (e.g. a goal
    // generation's taskIds) stay connected after a push.
    await addTask(task, existingId: task.id);
    if (task.reminderTime != null) {
      // Only actually schedules if the new instant is inside the enqueue window.
      await ReminderService().enqueueDueReminders([task]);
    }
    // Record the effort points pushed off the from-date (any day, not just today).
    await PerformanceService().recordPush(user.uid, task, fromDate);
    if (decrementScore) {
      await PerformanceService().decrementScore(user.uid, 1);
    }
  }

  Future<List<Task>> getMultiDayGroup(String groupId, {required String knownDate}) async {
    final user = AuthService().user;
    if (user == null) throw 'No user logged in';
    final anchor = DateService().getDate(knownDate);
    final results = <Task>[];

    Future<Task?> checkDate(DateTime date) async {
      final dateStr = DateService().getString(date);
      final snap = await taskCollection(user.uid, dateStr)
          .where('multiDayGroupId', isEqualTo: groupId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final data = snap.docs.first.data();
      data['id'] = snap.docs.first.id;
      return Task.fromJson(data);
    }

    // Search backward from anchor to find the start
    for (int i = 0; i <= 30; i++) {
      final task = await checkDate(anchor.subtract(Duration(days: i)));
      if (task == null) break;
      results.insert(0, task);
    }
    // Search forward from anchor+1 to find the end
    for (int i = 1; i <= 30; i++) {
      final task = await checkDate(anchor.add(Duration(days: i)));
      if (task == null) break;
      results.add(task);
    }

    return results;
  }

  Future<void> updateMultiDayEndDate(String groupId, String newEndDate, Task template) async {
    final group = await getMultiDayGroup(groupId, knownDate: template.dueDate!);
    if (group.isEmpty) return;

    final startDate = DateService().getDate(group.first.dueDate!);
    final endDate = DateService().getDate(newEndDate);
    if (!endDate.isAfter(startDate)) return;

    final newDayCount = endDate.difference(startDate).inDays + 1;
    final existingDates = {for (final t in group) t.dueDate!: t};

    for (int i = 0; i < newDayCount; i++) {
      final date = startDate.add(Duration(days: i));
      final dateStr = DateService().getString(date);
      final position = i == 0 ? 'start' : (i == newDayCount - 1 ? 'end' : 'middle');

      if (existingDates.containsKey(dateStr)) {
        final existing = existingDates[dateStr]!;
        if (existing.multiDayPosition != position) {
          await updateTaskByKey({'multiDayPosition': position}, existing);
        }
        existingDates.remove(dateStr);
      } else {
        final task = Task(
          title: template.title,
          description: template.description,
          priority: template.priority,
          completed: false,
          dueDate: dateStr,
          added: DateTime.now().millisecondsSinceEpoch,
          tags: template.tags,
          pushCount: 0,
          multiDayGroupId: groupId,
          multiDayPosition: position,
        );
        await addTask(task);
      }
    }

    // Delete days that are now beyond the new end date
    for (final leftover in existingDates.values) {
      await deleteTask(leftover);
    }
  }

  Future<void> callRemoteMethod(String name, dynamic payload) async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(name);
      final result = await callable.call(payload);
      debugPrint('trainScheduleTest result: ${result.data}');
    } on FirebaseFunctionsException catch (e, s) {
      reportError(e, s, 'Server call "$name" failed');
    } catch (e, s) {
      reportError(e, s, 'Server call "$name" failed');
    }
  }

  /// Creates a recurring series — the template plus every occurrence inside the
  /// materialization horizon — in ONE batched commit with no per-occurrence reads.
  ///
  /// This replaces the old save-then-loop path, which cost roughly four serial
  /// round trips per occurrence and left the add-task form open behind a spinner
  /// while it worked through the series.
  Future<RecurringSeriesWrite> createRecurringSeries(RecurringTask template, Task prototype) async {
    final user = AuthService().user;
    if (user == null) throw "No user logged in when adding recurring task";

    final now = DateTime.now();
    // doc() mints the id client-side, so no round trip is needed before the batch.
    final templateRef = recurringTempateCollection(user.uid).doc();
    final dates = RecurringSeries.occurrencesInHorizon(template, today: now);
    final tasks = _buildOccurrences(
      uid: user.uid,
      prototype: prototype,
      templateId: templateRef.id,
      dates: dates,
      reminderTimeOfDay: template.reminderTimeOfDay,
    );

    // Only the first occurrence's day gets an ordered insert: it is usually today,
    // the day the user is looking at. Later occurrences land on empty future days
    // where arrayUnion is equivalent to ordered insertion and needs no read.
    final firstOrder = tasks.isEmpty ? null : await _orderedInsertFor(user.uid, tasks.first);

    final templateData = removeNulls(template.toJson())..remove('id');
    if (tasks.isNotEmpty) {
      templateData['lastMaterializedDate'] = tasks.last.dueDate;
    }

    final ack = await _commitSeriesBatches(
      uid: user.uid,
      tasks: tasks,
      firstOrder: firstOrder,
      templateRef: templateRef,
      templateData: templateData,
      action: "Couldn't save recurring task",
    );
    return RecurringSeriesWrite(templateId: templateRef.id, occurrences: tasks, ack: ack);
  }

  /// Materializes [dates] for an existing series and advances its watermark, in
  /// one batched commit. Used by the rolling top-up; every date lands on a future
  /// day, so no ordered insert is needed.
  Future<RecurringSeriesWrite> materializeOccurrences({
    required String templateId,
    required RecurringTask template,
    required Task prototype,
    required List<DateTime> dates,
  }) async {
    final user = AuthService().user;
    if (user == null) throw "No user logged in when materializing recurring task";
    if (dates.isEmpty) {
      return RecurringSeriesWrite(templateId: templateId, occurrences: const [], ack: WriteAck.confirmed);
    }

    final tasks = _buildOccurrences(
      uid: user.uid,
      prototype: prototype,
      templateId: templateId,
      dates: dates,
      reminderTimeOfDay: template.reminderTimeOfDay,
    );

    final ack = await _commitSeriesBatches(
      uid: user.uid,
      tasks: tasks,
      templateRef: recurringTempateCollection(user.uid).doc(templateId),
      templateData: {'lastMaterializedDate': tasks.last.dueDate},
      templateMerge: true,
      action: "Couldn't extend the recurring series",
    );
    return RecurringSeriesWrite(templateId: templateId, occurrences: tasks, ack: ack);
  }

  /// One [Task] per date, each with a client-minted id and — when the series
  /// defines a time of day — its own absolute reminder instant. Every occurrence
  /// gets identical field treatment; the old path silently dropped `countdown`
  /// and other fields on every occurrence after the first.
  List<Task> _buildOccurrences({
    required String uid,
    required Task prototype,
    required String templateId,
    required List<DateTime> dates,
    required String? reminderTimeOfDay,
  }) {
    final dateService = DateService();
    return dates.map((date) {
      final dateStr = dateService.getString(date);
      return prototype.copyWith(
        id: taskCollection(uid, dateStr).doc().id,
        dueDate: dateStr,
        recurringTemplateId: templateId,
        reminderTime: RecurringSeries.reminderInstantFor(reminderTimeOfDay, date),
      );
    }).toList();
  }

  Future<List<String>> _orderedInsertFor(String uid, Task task) async {
    final existing = await getTasksInOrder(uid, task.dueDate!);
    return TaskOrdering.insertInto(
      existing,
      task.id!,
      priority: task.priority,
      startTime: task.startTime,
      endTime: task.endTime,
    );
  }

  /// Commits [tasks] (and optionally a template write) as batches chunked below
  /// Firestore's 500-operation limit. A WriteBatch is atomic, so a failure is
  /// all-or-nothing per chunk; a series large enough to span chunks is completed
  /// by the next top-up pass if one chunk fails.
  Future<WriteAck> _commitSeriesBatches({
    required String uid,
    required List<Task> tasks,
    required String action,
    List<String>? firstOrder,
    DocumentReference<Map<String, dynamic>>? templateRef,
    Map<String, dynamic>? templateData,
    bool templateMerge = false,
  }) async {
    final tasksDoc = _db.collection('todos').doc(uid).collection('tasks');
    final commits = <Future<void>>[];
    var batch = _db.batch();
    var ops = 0;

    void flush() {
      if (ops == 0) return;
      commits.add(batch.commit());
      batch = _db.batch();
      ops = 0;
    }

    if (templateRef != null && templateData != null) {
      batch.set(templateRef, templateData, SetOptions(merge: templateMerge));
      ops++;
    }

    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      final date = task.dueDate!;
      final data = removeNulls(task.toDbTask());
      // Stamp the owner so the collection-group queries (subtasks, series
      // dedupe) can find this doc across date partitions.
      data['userId'] = uid;
      batch.set(taskCollection(uid, date).doc(task.id), data);
      ops++;

      batch.set(
        tasksDoc.doc(date),
        {'taskOrder': i == 0 && firstOrder != null ? firstOrder : FieldValue.arrayUnion([task.id])},
        SetOptions(merge: true),
      );
      ops++;

      if (countdownEligible(task)) {
        batch.set(countdownCollection(uid).doc(task.id), {'title': task.title, 'dueDate': task.dueDate});
        ops++;
      }

      if (ops >= RecurringSeries.batchChunkSize) flush();
    }
    flush();

    return ackWrite(Future.wait(commits), action: action);
  }

  Future<RecurringTask> getRecurringTemplate(String templateId) async {
    final user = AuthService().user!;
    final snap = await recurringTempateCollection(user.uid).doc(templateId).get();
    final data = snap.data();
    if (data == null) {
      throw Exception('Recurring template not found');
    }
    return RecurringTask.fromJson(data);
  }

  /// Rewrites a series in place: drop its outstanding occurrences (cancelling any
  /// enqueued reminders), then re-materialize the new definition across the same
  /// horizon creation uses.
  ///
  /// Creation and editing used to disagree — creation took 30 occurrences, editing
  /// regenerated only a month — so an edited series silently changed length. Both
  /// now go through [createRecurringSeries].
  Future<void> updateRecurringTemplate(Task task, RecurringTask updatedTemplate) async {
    try {
      final existingTemplate = await getRecurringTemplate(task.recurringTemplateId!);
      await deleteRecurringTemplate(task, existingTemplate);

      // The edited occurrence is the prototype for the new series; clear the
      // fields that belong to a single occurrence rather than to the series.
      final prototype = task.copyWith(
        id: null,
        completed: false,
        pushCount: 0,
        added: DateTime.now().millisecondsSinceEpoch,
      );
      prototype.id = null;
      prototype.reminderTime = null;
      prototype.reminderTaskName = null;
      prototype.recurringTemplateId = null;

      // A fresh series has no watermark; re-materializing sets it.
      updatedTemplate.lastMaterializedDate = null;
      final written = await createRecurringSeries(updatedTemplate, prototype);
      await ReminderService().enqueueDueReminders(written.occurrences);
    } catch (e) {
      debugPrint('Error updating recurring template: $e');
      rethrow;
    }
  }

  /// Removes a series' outstanding occurrences, cancelling any reminder already
  /// handed to Cloud Tasks. Completed occurrences are preserved as history.
  ///
  /// Prefers one collection-group read. The old path expanded every occurrence
  /// across the whole series and issued a query per date — up to ~365 serial
  /// reads to delete a daily year-long series — which is retained only as the
  /// fallback for when the index is not yet deployed.
  Future<void> _deleteRecurringInstances(String templateId, RecurringTask template) async {
    final found = await seriesInstances(templateId);
    if (found != null) {
      await _removeOccurrences(found.where((t) => !t.completed));
      return;
    }
    await _deleteRecurringInstancesByDate(templateId, template);
  }

  /// Cancels reminders and deletes each occurrence. [deleteTask] keeps taskOrder
  /// and the countdown index consistent.
  Future<void> _removeOccurrences(Iterable<Task> occurrences) async {
    for (final task in occurrences) {
      if (task.reminderTaskName != null) {
        await ReminderService().cancelReminder(task);
      }
      await deleteTask(task);
    }
  }

  /// Degraded path used until the (userId, recurringTemplateId) index exists.
  Future<void> _deleteRecurringInstancesByDate(String templateId, RecurringTask template) async {
    final user = AuthService().user!;
    final instances = RecurringSeries.allOccurrences(template, today: DateTime.now());
    for (final instance in instances) {
      final dateStr = DateService().getString(instance);
      final snapshot =
          await taskCollection(user.uid, dateStr).where('recurringTemplateId', isEqualTo: templateId).get();
      final tasks = snapshot.docs.map((doc) {
        final data = {...doc.data(), 'id': doc.id};
        return Task.fromJson(data);
      }).where((t) => !t.completed);
      await _removeOccurrences(tasks);
    }
  }

  /// Tasks carrying a reminder that has not been handed to Cloud Tasks yet —
  /// the input to [ReminderService.topUpPendingReminders].
  ///
  /// Bounded by the enqueue window on both sides: past instants are dead, and
  /// anything beyond the window still cannot be scheduled. `reminderTaskName`
  /// is filtered client-side rather than in the query, because a task written
  /// before that field existed has no `null` value for Firestore to match.
  ///
  /// Needs the (userId, reminderTime) index; until that is deployed the query
  /// fails with failed-precondition, so degrade gracefully and return nothing —
  /// reminders inside the window were already scheduled at save time.
  Future<List<Task>> tasksWithPendingReminders() async {
    final user = AuthService().user;
    if (user == null) return const [];
    final now = DateTime.now().toUtc();
    try {
      final snap = await _db
          .collectionGroup('items')
          .where('userId', isEqualTo: user.uid)
          .where('reminderTime', isGreaterThan: now.toIso8601String())
          .where('reminderTime',
              isLessThan: now
                  .add(const Duration(days: RecurringSeries.reminderEnqueueWindowDays))
                  .toIso8601String())
          .get();
      return snap.docs.map((doc) {
        final data = {...doc.data(), 'id': doc.id};
        data['tags'] = <dynamic>[]; // tags are irrelevant to scheduling
        return Task.fromJson(data);
      }).where((t) => t.reminderTaskName == null && !t.completed).toList();
    } catch (e) {
      debugPrint('Pending reminder query failed (index building?): $e');
      return const [];
    }
  }

  /// Occurrences of a series, found in one collection-group read instead of a
  /// query per date. Needs the (userId, recurringTemplateId) index; until that is
  /// deployed the query fails with failed-precondition, so degrade gracefully and
  /// return null — callers fall back to the per-date scan / watermark alone.
  ///
  /// [fromDate] bounds the read to occurrences due on or after that day, so a
  /// launch-time top-up does not re-read a year of completed history. That
  /// needs the (userId, recurringTemplateId, dueDate) index; until it exists the
  /// bounded query fails and the unbounded one answers instead.
  Future<List<Task>?> seriesInstances(String templateId, {String? fromDate}) async {
    final user = AuthService().user;
    if (user == null) return null;
    final base = _db
        .collectionGroup('items')
        .where('userId', isEqualTo: user.uid)
        .where('recurringTemplateId', isEqualTo: templateId);
    List<Task> parse(QuerySnapshot<Map<String, dynamic>> snap) => snap.docs.map((doc) {
          final data = {...doc.data(), 'id': doc.id};
          data['tags'] = <dynamic>[]; // tags are irrelevant to the operations that use this
          return Task.fromJson(data);
        }).toList();
    if (fromDate != null) {
      try {
        return parse(await base.where('dueDate', isGreaterThanOrEqualTo: fromDate).get());
      } catch (e) {
        debugPrint('Bounded series instance query failed (index building?): $e');
      }
    }
    try {
      return parse(await base.get());
    } catch (e) {
      debugPrint('Series instance query failed (index building?): $e');
      return null;
    }
  }

  /// Scheduled instance dates for [template] from [start], bounded by the
  /// template's endDate (habits set endDate to their rolling horizon). Delegates
  /// to the shared generator so habits, recurring tasks and delete-series can
  /// never disagree about what a series' occurrences are.
  List<DateTime> generateInstancesInWindow(RecurringTask template, DateTime start) {
    return RecurringSeries.buildRule(template).getInstances(start: RecurringSeries.utcDate(start)).take(500).toList();
  }

  Future<void> deleteRecurringTemplate(Task task, RecurringTask template) async {
    final user = AuthService().user!;
    try {
      await _deleteRecurringInstances(task.recurringTemplateId!, template);
      await recurringTempateCollection(user.uid).doc(task.recurringTemplateId).delete();
    } catch (e, s) {
      reportError(e, s, "Couldn't delete the recurring series");
    }
  }

  Future<List<Task>> searchTasks(String query) async {
    final appId = dotenv.env['ALGOLIA_APP_ID'] ?? '';
    final apiKey = dotenv.env['ALGOLIA_SEARCH_KEY'] ?? '';
    if (appId.isEmpty || apiKey.isEmpty) {
      debugPrint('Algolia credentials not configured');
      return [];
    }

    final userId = AuthService().user!.uid;
    final client = SearchClient(appId: appId, apiKey: apiKey);

    try {
      final response = await client.searchIndex(
        request: SearchForHits(
          // Replica sorted by due date asc (name says "desc" but it's ascending).
          indexName: 'taskr_dueDate_desc',
          query: query,
          hitsPerPage: 50,
        ),
      );

      debugPrint('Algolia returned ${response.hits.length} hits');
      if (response.hits.isNotEmpty) {
        debugPrint('Sample hit keys: ${response.hits.first.keys.toList()}');
      }

      return response.hits.where((hit) {
        final path = hit['path'] as String? ?? '';
        final type = hit['type'] as String? ?? '';
        return path.contains(userId) && type != 'divider';
      }).map((hit) {
        final path = hit['path'] as String? ?? '';
        final pathSegments = path.split('/');
        final dueDate = pathSegments.length > 3 ? pathSegments[3] : hit['dueDate'] as String?;

        return Task(
          id: hit.objectID,
          title: hit['title'] as String? ?? '',
          description: hit['description'] as String?,
          dueDate: dueDate,
          completed: hit['completed'] as bool? ?? false,
          priority: _parseEffort(hit['priority'] as String?),
          added: 0,
          tags: [],
        );
      }).toList();
    } catch (e) {
      debugPrint('Algolia search error: $e');
      return [];
    }
  }

  static Effort _parseEffort(String? effort) {
    switch (effort?.toLowerCase()) {
      case 'high':
        return Effort.high;
      case 'medium':
        return Effort.medium;
      case 'info':
        return Effort.info;
      default:
        return Effort.low;
    }
  }
}

