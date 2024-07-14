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

  // Future<List<String>> getTaskOrder(userId) async {
  //   final ref = await _db.collection('todos').doc(userId).get();
  //   final d = ref.data();
  //   if (d != null && d.containsKey("taskOrder")) {
  //     return List<String>.from(d["taskOrder"]);
  //   } else {
  //     return List<String>.from([]);
  //   }
  // }

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

  Future<List<Task>> getTasks(String date) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when getting tasks";
    }
    var snapshot = await taskCollection(user.uid, date).orderBy('added', descending: true).get();
    var data = snapshot.docs.map((doc) => ({
          ...doc.data(),
          'id': doc.id,
        }));
    return data.map((d) => Task.fromJson(d)).toList();
  }

  Future<String> addTask(Task task) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final date = task.dueDate == null ? defaultUnassignedDate : task.dueDate!;
    final completer = Completer<String>();
    var id = await taskCollection(user.uid, date)
        .add(task.removeNulls())
        .then((DocumentReference ref) => ref.id);

    await _db.collection('todos').doc(user.uid).collection("tasks").doc(date).set({
      "taskOrder": FieldValue.arrayUnion([id])
    }, SetOptions(merge: true));
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
    await deleteTask(task);
    final d = task.dueDate != null ? DateService().getDate(task.dueDate!) : DateTime.now();
    task.dueDate = DateService().incrementDate(d);
    await addTask(task);
    // await TaskService().updateTaskByKey({"dueDate": DateService().incrementDate(d)}, task);
  }
}
