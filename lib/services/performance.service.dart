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

  Future<void> checkRolloverCurrentDay(userId) async {
    final ref = await score(userId).get();
    final lastAccessed = ref.data()!['lastAccessDate'];
    final current = DateService().getString(DateTime.now());
    if (lastAccessed == null) {
      final update = {'lastAccessDate': current};
      await score(userId).set(update, SetOptions(merge: true));
    } else if (lastAccessed != current) {
      final data = ref.data()!['currentDay'];
      await score(userId)
          .collection('performance')
          .doc(lastAccessed)
          .set({'completed': data, 'date': DateService().getDate(lastAccessed)});
      await score(userId)
          .set({'currentDay': {}, 'lastAccessDate': current}, SetOptions(merge: true));
      print('Rollover tasks for $lastAccessed');
    }
    print('Rollover completed Tasks check completed');
  }

  DocumentReference<Map<String, dynamic>> score(String userId) {
    return _db.collection('todos').doc(userId);
  }

  Stream<Map<String, dynamic>> streamPerformance(String userId) {
    return score(userId).snapshots().map((snapshot) {
      return snapshot.data()!;
    });
  }

  Future<void> incrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(value)});
  }

  Future<void> decrementScore(String userId, int value) {
    return score(userId).update({'currentScore': FieldValue.increment(-1 * value)});
  }

  Future<void> updateToday(String userId, Task task, bool shouldAdd) async {
    final currentRef = await score(userId).get();
    final currentDay = currentRef.data()!['currentDay'] as Map;
    final points = getScore(task.priority);
    var update = Map.from(currentDay);
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
    for (final tagId in task.tags) {
      if (update.containsKey(tagId)) {
        update[tagId] += points * (shouldAdd ? 1 : -1);
      } else {
        update[tagId] = points;
      }
    }

    await score(userId).set({'currentDay': update}, SetOptions(merge: true));
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
