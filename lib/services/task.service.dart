import 'dart:async';

import 'package:algoliasearch/algoliasearch_lite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/models.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/shared/shared.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:rrule/rrule.dart';
import 'package:intl/intl.dart';

class TaskService {
  final _db = FirebaseFirestore.instance;
  static const defaultUnassignedDate = "unassigned";

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

  Future<void> _syncCountdownIndex(String userId, Task task) async {
    if (task.id == null) return;
    // The countdown index is a denormalized cache; a failure here must never
    // break the primary task write (which would, e.g., leave the add-task form
    // stuck open because the caller never reaches its pop()).
    try {
      final ref = countdownCollection(userId).doc(task.id);
      final isNonStartMultiDay = task.multiDayGroupId != null && task.multiDayPosition != 'start';
      if (task.countdown && task.dueDate != null && !task.completed && !isNonStartMultiDay) {
        await ref.set({'title': task.title, 'dueDate': task.dueDate});
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
    return _db
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
            }).toList())
        .handleError((error) => debugPrint("SUBTASKS: $error"));
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

    await _db.runTransaction((transaction) async {
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
    });
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

  Future<List<Map<String, dynamic>>> getTasksInOrder(String userId, String? date) async {
    final order = await getTaskOrder(userId, date ?? defaultUnassignedDate);
    final tasks = await getTasks(userId, date ?? defaultUnassignedDate);
    return order.map((id) => tasks.firstWhere((t) => t['id'] == id)).toList();
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

  Future<String> addTask(Task task) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = task.dueDate ?? defaultUnassignedDate;
    final completer = Completer<String>();

    final data = removeNulls(task.toDbTask());
    // Stamp the owner so subtasks can be gathered via a collection-group query
    // across date partitions (see add-subtasks design).
    data['userId'] = user.uid;
    // Insert into DB
    var id = await taskCollection(user.uid, date).add(data).then((DocumentReference ref) => ref.id);

    // -- Smart Ordering --
    // If backloged, add to end
    if (task.dueDate == null) {
      await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
        "taskOrder": FieldValue.arrayUnion([id])
      }, SetOptions(merge: true));

      completer.complete(id);
      await _syncCountdownIndex(user.uid, task.copyWith(id: id));
      return completer.future;
    }

    List<Map<String, dynamic>> tasks = await getTasksInOrder(user.uid, task.dueDate!);

    // If no start time, make the last not-completed task
    if (task.startTime == null) {
      var completed = tasks.where((t) => t['completed']).map((t) => t['id']).toList();
      var notCompleted = tasks.where((t) => !t['completed']).map((t) => t['id']).toList();
      notCompleted.add(id);
      var newOrder = notCompleted + completed;
      await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({"taskOrder": newOrder});
      completer.complete(id);
      await _syncCountdownIndex(user.uid, task.copyWith(id: id));
      return completer.future;
    }

    // If there is a start time, iterate through to find either the first completed
    // or the first with the time > the added task, while preserving the order of tasks
    // without a start time
    var lowerItems = [];
    var index = 0;
    for (int i = 0; i < tasks.length; i++) {
      var t = tasks[i];
      index = i;

      if (t['completed']) {
        lowerItems.add(id);
        break;
      }

      if (t['startTime'] == null) {
        lowerItems.add(id);
        break;
      }

      // if (t.startTime == null) {
      //   lowerItems.add(t.id);
      //   continue;
      // }

      if (DateService()
          .isTimeLessThan(DateService().getTime(task.startTime!), DateService().getTime(t['startTime']!))) {
        lowerItems.add(id);
        break;
      }
      lowerItems.add(t['id']);
    }
    var update = lowerItems;
    if (tasks.isEmpty) {
      update = [id];
    } else if (index == tasks.length - 1) {
      if (!update.contains(id)) {
        update = update + [id];
      } else {
        update = update + tasks.sublist(index).map((t) => t['id']!).toList();
      }
    } else if (index < tasks.length) {
      update = update + tasks.sublist(index).map((t) => t['id']!).toList();
    }
    await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({"taskOrder": update});

    completer.complete(id);
    await _syncCountdownIndex(user.uid, task.copyWith(id: id));
    return completer.future;
  }

  Future<void> updateTask(String id, Task newTask, Task oldTask) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = newTask.dueDate ?? defaultUnassignedDate;
    if (oldTask.completed && newTask.priority != oldTask.priority) {
      await PerformanceService().updatePerfomanceStats(user.uid, oldTask, false);
      await PerformanceService().updatePerfomanceStats(user.uid, newTask, true);
    }
    await taskCollection(user.uid, date).doc(id).set(removeNulls(newTask.toDbTask()));
    await _syncCountdownIndex(user.uid, newTask.copyWith(id: id));
  }

  Future<void> updateTaskByKey(Map<String, dynamic> update, Task task) async {
    var user = AuthService().user;
    final taskId = task.id!;
    final date = task.dueDate ?? defaultUnassignedDate;
    if (user == null) {
      throw "No user logged in when completing task";
    } else {
      if (update.containsKey('completed')) {
        await PerformanceService().updatePerfomanceStats(user.uid, task, !!update['completed']);
        if (update['completed'] == true && task.countdown) {
          await countdownCollection(user.uid).doc(taskId).delete().catchError((_) {});
        }
      }
      return await taskCollection(user.uid, date).doc(taskId).update(update);
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
        await ReminderService().cancelReminder(task);
      }
      await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
        "taskOrder": FieldValue.arrayRemove([taskId])
      }, SetOptions(merge: true));
      if (task.completed && !task.isDivider) {
        await PerformanceService().updatePerfomanceStats(user.uid, task, false);
      }
      if (task.countdown) {
        await countdownCollection(user.uid).doc(taskId).delete().catchError((_) {});
      }
      return await taskCollection(user.uid, date).doc(taskId).delete();
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

  Future<void> pushTask(Task task) async {
    var user = AuthService().user!;
    if (task.reminderTaskName != null) {
      await ReminderService().cancelReminder(task);
    }
    await deleteTask(task);
    final now = DateTime.now();
    final d = task.dueDate != null ? DateService().getDate(task.dueDate!) : now;
    final decrementScore = d.day == now.day && d.month == now.month && d.year == now.year;
    task.dueDate = DateService().incrementDate(d);
    task.pushCount += 1;
    task.reminderTime = null;
    task.reminderTaskName = null;
    await addTask(task);
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
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Firebase Functions Exception: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('Generic Exception: $e');
    }
  }

  Future<String?> saveRecurringTask(RecurringTask template) async {
    final user = AuthService().user!;
    try {
      final resp = await recurringTempateCollection(user.uid).add(template.toJson());
      final templateId = resp.id;
      return templateId;
    } catch (e) {
      debugPrint('$e');
      return null;
    }
  }

  Future _addRecurringTask(Task task, List<DateTime> instances, String templateId) async {
    for (final dueDate in instances) {
      await addTask(
        task.copyWith(
          dueDate: DateService().getString(dueDate),
          recurringTemplateId: templateId,
        ),
      );
    }
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

  Future<void> updateRecurringTemplate(Task task, RecurringTask updatedTemplate) async {
    final user = AuthService().user!;
    try {
      final existingTemplate = await getRecurringTemplate(task.recurringTemplateId!);

      // Remove & Create new template
      await deleteRecurringTemplate(task, existingTemplate);
      final newTemplate = await recurringTempateCollection(user.uid).add(updatedTemplate.toJson());

      // Generate and add new task instances based on the updated template
      final instances = _generateRecurringTaskInstances(updatedTemplate);
      await _addRecurringTask(task, instances, newTemplate.id);
    } catch (e) {
      debugPrint('Error updating recurring template: $e');
      rethrow;
    }
  }

  Future<void> _deleteRecurringInstances(String templateId, RecurringTask template) async {
    final user = AuthService().user!;

    // Expand EVERY occurrence across the whole series (start -> endDate), not just
    // the first month. Creation materializes up to 30 occurrences, but this used to
    // regenerate only a one-month window, so "Delete Series" left every later
    // occurrence orphaned in the database (they kept re-appearing on the list).
    final instances = _generateAllRecurringInstances(template);
    for (var instance in instances) {
      final dateStr = DateService().getString(instance);
      final tasksSnapshot =
          await taskCollection(user.uid, dateStr).where('recurringTemplateId', isEqualTo: templateId).get();

      for (final doc in tasksSnapshot.docs) {
        var data = doc.data();
        data['id'] = doc.id;
        final task = Task.fromJson(data);
        // Preserve completed occurrences as history; only remove outstanding ones.
        // Reuse deleteTask so taskOrder, reminders and countdowns are cleaned up too.
        if (!task.completed) {
          await deleteTask(task);
        }
      }
    }
  }

  RecurrenceRule _buildRecurrenceRule(RecurringTask template) {
    final type = getRecurrenceFrequency(template.recurrenceType);
    final untilDate = template.endDate?.toUtc();
    switch (template.recurrenceType) {
      case 'Weekly':
        return RecurrenceRule(
          frequency: type,
          interval: template.frequency ?? 1,
          until: untilDate,
          byWeekDays: getWeeklyRecurrenceList(template.daysOfWeek!),
        );
      case 'Monthly':
        return RecurrenceRule(
          frequency: type,
          interval: template.frequency ?? 1,
          until: untilDate,
          byMonthDays: [template.dayOfMonth!],
        );
      default:
        return RecurrenceRule(
          frequency: type,
          interval: template.frequency ?? 1,
          until: untilDate,
        );
    }
  }

  // Full series expansion used when deleting a series. Templates always carry an
  // end date (enforced by the recurring task form), so this is finite; the take()
  // cap is only a guard against a malformed template with a missing/far-future end.
  List<DateTime> _generateAllRecurringInstances(RecurringTask template) {
    final start = template.startDate?.toUtc() ?? DateTime.now().toUtc();
    final rule = _buildRecurrenceRule(template);
    return rule.getInstances(start: start).take(1000).toList();
  }

  List<DateTime> _generateRecurringTaskInstances(RecurringTask template) {
    final user = AuthService().user!;
    final type = getRecurrenceFrequency(template.recurrenceType);
    final untilDate = template.endDate?.toUtc();
    RecurrenceRule rule;

    // Determine the start date for recurrence generation
    // If the template has a startDate, use it. Otherwise, use now.
    final DateTime generationStartDate =
        template.startDate != null ? template.startDate!.toUtc() : DateTime.now().toUtc();
    debugPrint('generationStartDate: $generationStartDate');

    // Calculate one month from the generation start date
    final DateTime untilDateForGeneration = DateTime.utc(
      generationStartDate.year,
      generationStartDate.month + 1,
      generationStartDate.day,
      generationStartDate.hour,
      generationStartDate.minute,
      generationStartDate.second,
    );

    switch (template.recurrenceType) {
      case 'Weekly':
        rule = RecurrenceRule(
          frequency: type,
          interval: template.frequency ?? 1,
          until: untilDate,
          byWeekDays: getWeeklyRecurrenceList(template.daysOfWeek!),
        );
        break;
      case 'Monthly':
        rule = RecurrenceRule(
          frequency: type,
          interval: template.frequency ?? 1,
          until: untilDate,
          byMonthDays: [template.dayOfMonth!],
        );
        break;
      default:
        rule = RecurrenceRule(
          frequency: type,
          interval: template.frequency ?? 1,
          until: untilDate,
        );
    }

    final instances = rule
        .getInstances(start: generationStartDate)
        .where((instance) => instance.isBefore(untilDateForGeneration)) // Filter instances within the next month
        .toList();
    debugPrint('Generated ${instances.length} instances for the next month.');
    return instances;
  }

  Future<void> deleteRecurringTemplate(Task task, RecurringTask template) async {
    final user = AuthService().user!;
    try {
      await _deleteRecurringInstances(task.recurringTemplateId!, template);
      await recurringTempateCollection(user.uid).doc(task.recurringTemplateId).delete();
    } catch (e) {
      debugPrint('$e');
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

Frequency getRecurrenceFrequency(String templateRecurrance) {
  if (templateRecurrance == 'Daily') return Frequency.daily;
  if (templateRecurrance == 'Weekly') return Frequency.weekly;
  if (templateRecurrance == 'Monthly') return Frequency.monthly;
  if (templateRecurrance == 'Yearly') return Frequency.yearly;
  throw Exception('Invalid recurrence type');
}

List<ByWeekDayEntry> getWeeklyRecurrenceList(Map<String, bool> daysOfWeek) {
  return daysOfWeek.entries.fold<List<ByWeekDayEntry>>([], (acc, entry) {
    if (!entry.value) return acc;

    if (entry.key == 'Su') acc.add(ByWeekDayEntry(DateTime.sunday));
    if (entry.key == 'Mo') acc.add(ByWeekDayEntry(DateTime.monday));
    if (entry.key == 'Tu') acc.add(ByWeekDayEntry(DateTime.tuesday));
    if (entry.key == 'We') acc.add(ByWeekDayEntry(DateTime.wednesday));
    if (entry.key == 'Th') acc.add(ByWeekDayEntry(DateTime.thursday));
    if (entry.key == 'Fr') acc.add(ByWeekDayEntry(DateTime.friday));
    if (entry.key == 'Sa') acc.add(ByWeekDayEntry(DateTime.saturday));
    return acc;
  });
}
