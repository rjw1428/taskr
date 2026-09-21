import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/firebase_refs.dart';

class HealthService {
  HealthService._internal();
  static HealthService _instance = HealthService._internal();

  /// Drops all state so the next `HealthService()` starts fresh.
  @visibleForTesting
  static void resetInstance() => _instance = HealthService._internal();
  factory HealthService() => _instance;

  late FirebaseFirestore _db = FirebaseRefs.firestore;

  @visibleForTesting
  set db(FirebaseFirestore db) => _db = db;

  CollectionReference<Map<String, dynamic>> _healthCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('health');
  }

  Stream<HealthEntry?> streamEntry(String date) {
    final user = AuthService().user;
    if (user == null) return Stream.value(null);
    return _healthCollection(user.uid).doc(date).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      data.remove('updatedAt');
      return HealthEntry.fromJson(data);
    });
  }
}
