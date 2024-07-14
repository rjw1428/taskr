import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/models.dart';
import 'package:rxdart/rxdart.dart';

class TaskService {
  TaskService._internal();

  final _db = FirebaseFirestore.instance;
  static final TaskService _instance = TaskService._internal();

  factory TaskService() {
    return _instance;
  }

  CollectionReference<Map<String, dynamic>> taskCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('tasks');
  }

  Stream<List<String>> taskOrderStream(userId) {
    return _db.collection('todos').doc(userId).snapshots().map((snapshot) {
      final d = snapshot.data();
      if (d != null && d.containsKey("taskOrder")) {
        return List<String>.from(d["taskOrder"]);
      } else {
        return List<String>.from([]);
      }
    });
  }

  Future<List<String>> getTaskOrder(userId) async {
    final ref = await _db.collection('todos').doc(userId).get();
    final d = ref.data();
    if (d != null && d.containsKey("taskOrder")) {
      return List<String>.from(d["taskOrder"]);
    } else {
      return List<String>.from([]);
    }
  }

  Future<void> updateTaskOrder(String userId, List<String> updatedOrder) async {
    return await _db.collection('todos').doc(userId).update({"taskOrder": updatedOrder});
  }

  Stream<List<Task>> streamTasks(String userId, String date) {
    return CombineLatestStream.combine3(
        taskCollection(
          userId,
        )
            // .orderBy('added', descending: true)
            .snapshots()
            .handleError((error) => print("TASK LIST: $error"))
            .map((snapshot) {
          return snapshot.docs.map((doc) {
            return Task.fromJson({...doc.data(), 'id': doc.id});
          }).toList();
        }),
        TagService().streamTags(userId),
        taskOrderStream(userId),
        (tasks, tags, order) =>
            order.map((id) => tasks.firstWhere((task) => task.id == id)).map((task) {
              final tagList = task.tags
                  .map((tagId) => tags.containsKey(tagId) ? tags[tagId]!.label : '<NOT FOUND>')
                  .toList();
              return Task.fromJson({...task.toJson(), "tags": tagList});
            }).toList()).handleError((error) => print(error));
  }

  Future<List<Task>> getTasks() async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when getting tasks";
    }
    var snapshot = await taskCollection(user.uid).orderBy('added', descending: true).get();
    var data = snapshot.docs.map((doc) => ({
          ...doc.data(),
          'id': doc.id,
        }));
    return data.map((d) => Task.fromJson(d)).toList();
  }

  Future<String> addTasks(Task task) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    final completer = Completer<String>();
    var id = await taskCollection(user.uid)
        .add(task.removeNulls())
        .then((DocumentReference ref) => ref.id);

    await _db.collection('todos').doc(user.uid).set({
      "taskOrder": FieldValue.arrayUnion([id])
    }, SetOptions(merge: true));
    completer.complete(id);
    return completer.future;
  }

  Future<void> updateTaskByKey(Map<String, dynamic> update, String taskId) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when completing task";
    } else {
      return await taskCollection(user.uid).doc(taskId).update(update);
    }
  }

  Future<void> deleteTask(String taskId) async {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when deleting task";
    } else {
      await _db.collection('todos').doc(user.uid).set({
        "taskOrder": FieldValue.arrayRemove([taskId])
      }, SetOptions(merge: true));
      return await taskCollection(user.uid).doc(taskId).delete();
    }
  }
}
