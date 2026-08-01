import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/services.dart';

void main() {
  late FakeFirebaseFirestore fake;
  const uid = 'u1';
  const goalId = 'g1';

  Future<void> seedTask(String date, String id, {required bool completed, String? goal = goalId}) {
    return fake
        .collection('todos').doc(uid)
        .collection('tasks').doc(date)
        .collection('items').doc(id)
        .set({
      'title': id,
      'completed': completed,
      'userId': uid,
      if (goal != null) 'goalId': goal,
    });
  }

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
  });

  // Regression: goal progress used to be summed from a generation's
  // completedTaskIds, which undercounted after a push (new id) or non-checkbox
  // completion. It now counts the tasks actually tagged to the goal.
  test('getGoalStats counts tagged tasks across date partitions', () async {
    await seedTask('2026-08-01', 't1', completed: true);
    await seedTask('2026-08-02', 't2', completed: true);
    await seedTask('2026-08-03', 't3', completed: false);
    // Not part of this goal -> must be excluded.
    await seedTask('2026-08-03', 't4', completed: true, goal: null);
    await seedTask('2026-08-04', 't5', completed: true, goal: 'other-goal');

    final service = GoalService()..db = fake;
    final stats = await service.getGoalStats(goalId);

    expect(stats['totalTasks'], 3);
    expect(stats['completedTasks'], 2);
  });

  test('getGoalStats returns zeros for a goal with no tasks', () async {
    final service = GoalService()..db = fake;
    final stats = await service.getGoalStats('empty-goal');
    expect(stats['totalTasks'], 0);
    expect(stats['completedTasks'], 0);
  });
}
