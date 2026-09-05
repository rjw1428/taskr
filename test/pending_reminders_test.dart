import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fake;
  late TaskService tasks;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    PerformanceService().db = fake;
    tasks = TaskService()..db = fake;
  });

  String inDays(int days) => DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();

  Future<void> write({
    required String id,
    String? reminderTime,
    String? reminderTaskName,
    bool completed = false,
    String owner = uid,
    String date = '2027-05-30',
  }) async {
    await fake.collection('todos').doc(owner).collection('tasks').doc(date).collection('items').doc(id).set({
      'title': id,
      'priority': Effort.medium.name,
      'completed': completed,
      'added': 1,
      'dueDate': date,
      'userId': owner,
      if (reminderTime != null) 'reminderTime': reminderTime,
      if (reminderTaskName != null) 'reminderTaskName': reminderTaskName,
    });
  }

  group('tasksWithPendingReminders', () {
    test('returns a reminder inside the window that was never scheduled', () async {
      await write(id: 'a', reminderTime: inDays(3));
      final pending = await tasks.tasksWithPendingReminders();
      expect(pending.map((t) => t.id), ['a']);
    });

    test('skips a reminder already handed to Cloud Tasks', () async {
      await write(id: 'a', reminderTime: inDays(3), reminderTaskName: 'queues/q/tasks/t');
      expect(await tasks.tasksWithPendingReminders(), isEmpty);
    });

    test('skips a reminder still beyond the Cloud Tasks window', () async {
      await write(id: 'a', reminderTime: inDays(RecurringSeries.reminderEnqueueWindowDays + 5));
      expect(await tasks.tasksWithPendingReminders(), isEmpty);
    });

    test('skips a reminder already in the past', () async {
      await write(id: 'a', reminderTime: inDays(-1));
      expect(await tasks.tasksWithPendingReminders(), isEmpty);
    });

    test('skips completed tasks', () async {
      await write(id: 'a', reminderTime: inDays(3), completed: true);
      expect(await tasks.tasksWithPendingReminders(), isEmpty);
    });

    test('skips another user’s tasks', () async {
      await write(id: 'a', reminderTime: inDays(3), owner: 'someone-else');
      expect(await tasks.tasksWithPendingReminders(), isEmpty);
    });
  });

  group('enqueue window', () {
    test('a far-future reminder is outside the window', () {
      final at = DateTime.utc(2027, 5, 30, 17, 0);
      expect(
        RecurringSeries.isWithinEnqueueWindow(at.toIso8601String(), now: DateTime.utc(2026, 9, 4)),
        isFalse,
      );
    });

    test('the same reminder is inside it once it comes into range', () {
      final at = DateTime.utc(2027, 5, 30, 17, 0);
      expect(
        RecurringSeries.isWithinEnqueueWindow(at.toIso8601String(), now: DateTime.utc(2027, 5, 10)),
        isTrue,
      );
    });
  });
}
