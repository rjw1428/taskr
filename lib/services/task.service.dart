import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/models.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/shared/shared.dart';
import 'package:cloud_functions/cloud_functions.dart';

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
        (tasks, order) => order.map((id) => tasks.firstWhere((task) => task['id'] == id)).map((task) {
              final tagList = (task['tags'] as List).map((tag) {
                if (tag is String) {
                  return tagMap[tag];
                } else {
                  return tagMap[tag["id"]];
                }
              }).toList();

              task['tags'] = tagList
                  .where((t) => t != null)
                  // .map((t) => )
                  .toList();

              return Task.fromJson(task);
            }).toList()).handleError((error) => debugPrint("SHIT: $error"));
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

  Future<String> addTask(Task task) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = task.dueDate ?? defaultUnassignedDate;
    final completer = Completer<String>();

    final data = removeNulls(task.toDbTask());
    // Insert into DB
    var id = await taskCollection(user.uid, date).add(data).then((DocumentReference ref) => ref.id);

    // -- Smart Ordering --
    // If backloged, add to end
    if (task.dueDate == null) {
      await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
        "taskOrder": FieldValue.arrayUnion([id])
      }, SetOptions(merge: true));

      completer.complete(id);
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
      await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
        "taskOrder": FieldValue.arrayRemove([taskId])
      }, SetOptions(merge: true));
      if (task.completed) {
        await PerformanceService().updatePerfomanceStats(user.uid, task, false);
      }
      return await taskCollection(user.uid, date).doc(taskId).delete();
    }
  }

  Future<void> pushTask(Task task) async {
    var user = AuthService().user!;
    await deleteTask(task);
    final now = DateTime.now();
    final d = task.dueDate != null ? DateService().getDate(task.dueDate!) : now;
    final decrementScore = d.day == now.day && d.month == now.month && d.year == now.year;
    task.dueDate = DateService().incrementDate(d);
    task.pushCount += 1;
    await addTask(task);
    if (decrementScore) {
      await PerformanceService().decrementScore(user.uid, 1);
    }
  }

  Future<void> checkTrainStatus() async {
    try {
      final userId = AuthService().user!.uid;
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('trainScheduleTest');
      final result = await callable.call(["userId", userId]);
      debugPrint('trainScheduleTest result: ${result.data}');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Firebase Functions Exception: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('Generic Exception: $e');
    }
  }

  Future<void> addWindTask(Map<String, dynamic> data) async {
    try {
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('addWindTaskFromNotification');
      final result = await callable.call(data);
      debugPrint('addWindTaskFromNotification result: ${result.data}');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Firebase Functions Exception: ${e.code} - ${e.message}');
    } catch (e) {
      debugPrint('Generic Exception: $e');
    }
  }
}
