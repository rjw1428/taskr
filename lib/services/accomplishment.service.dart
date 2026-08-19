import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/models.dart';

class AccomplishmentService {
  // `late` so a test can inject a fake via [db] before the real instance is
  // touched (Firebase isn't initialized under `flutter test`).
  late FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  @visibleForTesting
  set db(FirebaseFirestore db) => _db = db;

  CollectionReference<Map<String, dynamic>>? _collection() {
    var user = _auth.user;
    if (user == null) {
      return null;
    }
    return _db.collection('todos').doc(user.uid).collection('accomplishments');
  }

  /// Accomplishments newest-first.
  ///
  /// Ordering happens server-side: `date` is stored as an ISO-8601 string, which
  /// sorts lexicographically in chronological order, so there is no need to
  /// re-sort in the client. Pass [limit] to fetch only the entries a view
  /// renders instead of the whole collection.
  ///
  /// This is a single-field sort with no `where` clause, so Firestore's
  /// automatic single-field indexes cover it — no composite index to deploy.
  Stream<List<Accomplishment>> getAccomplishments({int? limit}) {
    var ref = _collection();
    if (ref == null) {
      return Stream.value([]);
    }
    Query<Map<String, dynamic>> query = ref.orderBy('date', descending: true);
    if (limit != null) {
      query = query.limit(limit);
    }
    return query.snapshots().map((list) => list.docs.map((doc) {
          var data = doc.data();
          data['id'] = doc.id;
          return Accomplishment.fromJson(data);
        }).toList());
  }

  /// A single accomplishment, tracked by id. Emits `null` once the document no
  /// longer exists, which is what drives the detail page's dismiss-on-delete.
  Stream<Accomplishment?> getAccomplishment(String id) {
    var ref = _collection();
    if (ref == null) {
      return Stream.value(null);
    }
    return ref.doc(id).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }
      var data = doc.data()!;
      data['id'] = doc.id;
      return Accomplishment.fromJson(data);
    });
  }

  Future<void> addAccomplishment(Accomplishment accomplishment) {
    var ref = _collection();
    if (ref == null) {
      throw Exception('User is not authenticated');
    }
    return ref.add(accomplishment.toJson());
  }

  Future<void> updateAccomplishment(Accomplishment accomplishment) {
    var ref = _collection();
    if (ref == null) {
      throw Exception('User is not authenticated');
    }
    return ref.doc(accomplishment.id).update(accomplishment.toJson());
  }

  Future<void> deleteAccomplishment(String accomplishmentId) {
    var ref = _collection();
    if (ref == null) {
      throw Exception('User is not authenticated');
    }
    return ref.doc(accomplishmentId).delete();
  }
}
