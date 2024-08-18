import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/shared/constants.dart';

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
  Future<void> incrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(value)});
  }

  Future<void> decrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(-1 * value)});
  }

  int getScore(Effort priority) {
    if (priority == Effort.high) {
      return 3;
    }
    if (priority == Effort.medium) {
      return 2;
    }
    if (priority == Effort.low) {
      return 1;
    }
    print("Unknown Priority: $priority");
    return 0;
  }
}
