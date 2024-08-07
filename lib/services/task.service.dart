import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/models.dart';
import 'package:rxdart/rxdart.dart';

class TaskService {
  TaskService._internal();

  final _db = FirebaseFirestore.instance;
  static const defaultUnassignedDate = "unassigned";
  static final TaskService _instance = TaskService._internal();

  factory TaskService() {
    return _instance;
  }

  CollectionReference<Map<String, dynamic>> taskCollection(String userId, String date) {
    return _db.collection('todos').doc(userId).collection('tasks').doc(date).collection("items");
  }

  Stream<List<String>> taskOrderStream(String userId, String date) {
    return _db
        .collection('todos')
        .doc(userId)
        .collection("tasks")
        .doc(date)
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

  Future<List<String>> getTaskOrder(String userId, String date) async {
    final ref = await _db.collection('todos').doc(userId).collection("tasks").doc(date).get();
    final d = ref.data();
    if (d != null && d.containsKey("taskOrder")) {
      return List<String>.from(d["taskOrder"]);
    } else {
      return List<String>.from([]);
    }
  }

  Future<void> updateTaskOrder(String userId, List<String> updatedOrder, String date) async {
    return await _db
        .collection('todos')
        .doc(userId)
        .collection("tasks")
        .doc(date)
        .update({"taskOrder": updatedOrder});
  }

  Stream<List<Task>> streamTasks(String userId, String date) {
    return CombineLatestStream.combine3(
        taskCollection(userId, date)
            // .orderBy('added', descending: true)
            .snapshots()
            .handleError((error) => print("TASK LIST: $error"))
            .map((snapshot) {
          return snapshot.docs.map((doc) {
            return Task.fromJson({...doc.data(), 'id': doc.id});
          }).toList();
        }),
        TagService().streamTags(userId),
        taskOrderStream(userId, date),
        (tasks, tags, order) =>
            order.map((id) => tasks.firstWhere((task) => task.id == id)).map((task) {
              final tagList = task.tags
                  .map((tagId) => tags.containsKey(tagId) ? tags[tagId]!.label : '<NOT FOUND>')
                  .toList();
              return Task.fromJson({...task.toJson(), "tags": tagList});
            }).toList()).handleError((error) => print(error));
  }

  Future<List<Task>> getTasks(String userId, String date) async {
    var snapshot = await taskCollection(userId, date).orderBy('added', descending: true).get();
    var data = snapshot.docs.map((doc) => ({
          ...doc.data(),
          'id': doc.id,
        }));
    return data.map((d) => Task.fromJson(d)).toList();
  }

  Future<List<Task>> getTasksInOrder(String userId, String date) async {
    final order = await getTaskOrder(userId, date);
    final tasks = await getTasks(userId, date);
    return order.map((id) => tasks.firstWhere((t) => t.id == id)).toList();
  }

  Future<String> addTask(Task task) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = task.dueDate == null ? defaultUnassignedDate : task.dueDate!;
    final completer = Completer<String>();

    // Insert into DB
    var id = await taskCollection(user.uid, date)
        .add(task.removeNulls())
        .then((DocumentReference ref) => ref.id);

    // -- Smart Ordering --
    // If backloged, add to end
    if (task.dueDate == null) {
      await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
        "taskOrder": FieldValue.arrayUnion([id])
      }, SetOptions(merge: true));
      completer.complete(id);
      return completer.future;
    }

    List<Task> tasks = await getTasksInOrder(user.uid, task.dueDate!);

    // If no start time, make the last not-completed task
    if (task.startTime == null) {
      var completed = tasks.where((t) => t.completed).map((t) => t.id).toList();
      var notCompleted = tasks.where((t) => !t.completed).map((t) => t.id).toList();
      notCompleted.add(id);
      var newOrder = notCompleted + completed;
      await _db
          .collection('todos')
          .doc(user.uid)
          .collection("tasks")
          .doc(date)
          .set({"taskOrder": newOrder});
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

      if (t.completed) {
        lowerItems.add(id);
        break;
      }

      if (t.startTime == null) {
        lowerItems.add(t.id);
        continue;
      }

      if (DateService().isTimeLessThan(
          DateService().getTime(task.startTime!), DateService().getTime(t.startTime!))) {
        lowerItems.add(id);
        break;
      }
      lowerItems.add(t.id);
    }
    var update = lowerItems;
    if (index == tasks.length - 1) {
      update = update + [id];
    } else if (index < tasks.length) {
      update = update + tasks.sublist(index).map((t) => t.id!).toList();
    }
    await _db
        .collection('todos')
        .doc(user.uid)
        .collection("tasks")
        .doc(date)
        .set({"taskOrder": update});
    completer.complete(id);
    return completer.future;
  }

  Future<void> updateTask(String id, Task task) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = task.dueDate == null ? defaultUnassignedDate : task.dueDate!;
    await taskCollection(user.uid, date).doc(id).set(task.removeNulls());
  }

  Future<void> updateTaskByKey(Map<String, dynamic> update, Task task) async {
    var user = AuthService().user;
    final taskId = task.id!;
    final date = task.dueDate == null ? defaultUnassignedDate : task.dueDate!;
    if (user == null) {
      throw "No user logged in when completing task";
    } else {
      return await taskCollection(user.uid, date).doc(taskId).update(update);
    }
  }

  Future<void> deleteTask(Task task) async {
    var user = AuthService().user;
    final taskId = task.id!;
    final date = task.dueDate == null ? defaultUnassignedDate : task.dueDate!;
    if (user == null) {
      throw "No user logged in when deleting task";
    } else {
      await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
        "taskOrder": FieldValue.arrayRemove([taskId])
      }, SetOptions(merge: true));
      return await taskCollection(user.uid, date).doc(taskId).delete();
    }
  }

  Future<void> pushTask(Task task) async {
    var user = AuthService().user;
    final tags = await TagService().streamTagsArray(user!.uid).first;
    await deleteTask(task);
    final d = task.dueDate != null ? DateService().getDate(task.dueDate!) : DateTime.now();
    task.dueDate = DateService().incrementDate(d);
    task.pushCount += 1;
    task.tags = task.tags.map((label) => tags.firstWhere((tag) => tag.label == label).id).toList();
    await addTask(task);
  }
}
