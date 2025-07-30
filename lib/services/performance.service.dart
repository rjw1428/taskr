import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

class PerformanceService {
  PerformanceService._internal();
  final _db = FirebaseFirestore.instance;
  static final _instance = PerformanceService._internal();

  factory PerformanceService() {
    return _instance;
  }

  DocumentReference<Map<String, dynamic>> score(String userId) {
    return _db.collection('todos').doc(userId);
  }

  Stream<List<Map<String, dynamic>>> streamPerformance(String userId, DateTime timestamp) {
    return score(userId)
        .collection('performance')
        .where("date", isGreaterThan: Timestamp.fromDate(timestamp))
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  Stream<List<Map<String, dynamic>>> streamPerformanceForMonth(
      String userId, DateTime startDate, DateTime endDate) {

      print('streamPerformanceForMonth: $startDate to $endDate');
    return score(userId)
        .collection('performance')
        .where("date", isGreaterThanOrEqualTo: startDate)
        .where("date", isLessThanOrEqualTo: endDate)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  Future<void> incrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(value)});
  }

  Future<void> decrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(-1 * value)});
  }

  Future<void> updatePerfomanceStats(String userId, Task task, bool shouldAdd) async {
    final date = task.dueDate ?? DateService().getString(DateTime.now());
    final currentRef = await score(userId).collection('performance').doc(date).get();
    final completed = currentRef.exists ? currentRef.data()!['completed'] : {};
    final points = getScore(task.priority);
    var update = Map.from(completed);
    if (update.containsKey('ALL')) {
      update['ALL'] += points * (shouldAdd ? 1 : -1);
    } else {
      update['ALL'] = points;
    }
    if (task.tags.isEmpty) {
      if (update.containsKey('Other')) {
        update['Other'] += points * (shouldAdd ? 1 : -1);
      } else {
        update['Other'] = points;
      }
    }
    for (final tag in task.tags) {
      if (update.containsKey(tag.id)) {
        update[tag.id] += points * (shouldAdd ? 1 : -1);
      } else {
        update[tag.id] = points;
      }
    }

    await score(userId)
        .collection('performance')
        .doc(date)
        .set({'completed': update, 'date': DateService().getDate(date)}, SetOptions(merge: true));
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
