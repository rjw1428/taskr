import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

class HealthService {
  HealthService._internal();
  static final _instance = HealthService._internal();
  factory HealthService() => _instance;

  final _db = FirebaseFirestore.instance;

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
