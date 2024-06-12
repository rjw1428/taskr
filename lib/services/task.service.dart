import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/models.dart';
import 'package:rxdart/rxdart.dart';

class TaskService {
  final _db = FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> taskCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('tasks');
  }

  Stream<List<Task>> streamTasks() {
    return AuthService().userStream.switchMap((user) {
      if (user == null) {
        throw "No user logged in when streaming tasks";
      }
      return taskCollection(user.uid).orderBy('added', descending: true).snapshots().map(
          (snapshot) =>
              snapshot.docs.map((doc) => Task.fromJson({...doc.data(), 'id': doc.id})).toList());
    });
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
    await taskCollection(user.uid)
        .add(task.removeNulls())
        .then((DocumentReference ref) => completer.complete(ref.id));
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
      return await taskCollection(user.uid).doc(taskId).delete();
    }
  }
}
