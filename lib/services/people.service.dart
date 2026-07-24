import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:taskr/services/models.dart';

class PeopleService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _userId => _auth.currentUser!.uid;

  Future<String> addPerson(Person person) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final personData = person.toJson();
    personData['createdAt'] = now;
    personData['lastUpdated'] = now;

    final docRef = await _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .add(personData);
    return docRef.id;
  }

  Future<void> updatePerson(String personId, Person person) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final personData = person.toJson();
    personData['lastUpdated'] = now;

    // The person form only edits static info, so its `logs` is always an empty
    // list and `createdAt` is null. Merging those in would wipe the server's
    // real conversation logs and creation timestamp — strip them so this update
    // touches static fields only. (`id` is the doc id, not a stored field.)
    personData.remove('logs');
    personData.remove('createdAt');
    personData.remove('id');

    await _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .doc(personId)
        .set(personData, SetOptions(merge: true));
  }

  Future<void> deletePerson(String personId) async {
    await _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .doc(personId)
        .delete();
  }

  Stream<List<Person>> getPeople() {
    return _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Person.fromJson(data);
      }).toList();
    });
  }

  Stream<Person?> getPerson(String personId) {
    return _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .doc(personId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      return Person.fromJson(data);
    });
  }

  Future<void> addLog(String personId, ConversationLog log) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final logData = log.toJson();
    // Logs live inside the person document (not their own collection), so give
    // each one a stable id here. Without it every log was stored with id: null,
    // which then broke editing/deleting individual logs (log.id! crashed).
    logData['id'] = log.id ?? _firestore.collection('todos').doc().id;
    logData['createdAt'] = now;
    logData['updatedAt'] = now;

    final personRef = _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .doc(personId);

    await _firestore.runTransaction((transaction) async {
      final personDoc = await transaction.get(personRef);
      if (!personDoc.exists) {
        throw Exception('Person no longer exists');
      }
      final person = Person.fromJson(personDoc.data()!);
      person.id = personId;
      person.logs.add(ConversationLog.fromJson(logData));
      person.lastUpdated = now;
      transaction.update(personRef, person.toJson());
    });
  }

  Future<void> updateLog(String personId, String logId, ConversationLog log) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final logData = log.toJson();
    logData['updatedAt'] = now;

    final personRef = _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .doc(personId);

    await _firestore.runTransaction((transaction) async {
      final personDoc = await transaction.get(personRef);
      final person = Person.fromJson(personDoc.data() as Map<String, dynamic>);
      person.id = personId;

      final logIndex = person.logs.indexWhere((l) => l.id == logId);
      if (logIndex != -1) {
        logData['id'] = logId;
        person.logs[logIndex] = ConversationLog.fromJson(logData);
        person.lastUpdated = now;
        transaction.update(personRef, person.toJson());
      }
    });
  }

  Future<void> deleteLog(String personId, String logId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final personRef = _firestore
        .collection('todos')
        .doc(_userId)
        .collection('people')
        .doc(personId);

    await _firestore.runTransaction((transaction) async {
      final personDoc = await transaction.get(personRef);
      final person = Person.fromJson(personDoc.data() as Map<String, dynamic>);
      person.id = personId;
      person.logs.removeWhere((l) => l.id == logId);
      person.lastUpdated = now;
      transaction.update(personRef, person.toJson());
    });
  }
}
