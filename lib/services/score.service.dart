import 'package:cloud_firestore/cloud_firestore.dart';

class ScoreService {
  ScoreService._internal();
  final _db = FirebaseFirestore.instance;
  static final _instance = ScoreService._internal();

  factory ScoreService() {
    return _instance;
  }

  DocumentReference<Map<String, dynamic>> score(String userId) {
    return _db.collection('todos').doc(userId);
  }

  Stream<int> streamScore(String userId) {
    return score(userId).snapshots().map((snapshot) {
      final data = snapshot.data()!;
      return data['currentScore'];
    });
  }

  // NEED TO SET THE CURRENT SCORE
  Future<void> incrementScore(String userId) {
    return score(userId).update({'currentScore': FieldValue.increment(1)});
  }

  Future<void> decrementScore(String userId) {
    return score(userId).update({'currentScore': FieldValue.increment(-1)});
  }
}
