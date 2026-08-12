import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  late FakeFirebaseFirestore fake;
  late TaskService service;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    PerformanceService().db = fake; // pushTask records pushed points
    service = TaskService()..db = fake;
  });

  Task t(String title, {String? date, Effort priority = Effort.medium, String? id}) =>
      Task(id: id, added: 1, title: title, dueDate: date, priority: priority);

  Future<List<String>> order(String date) async {
    final doc = await fake.collection('todos').doc(uid).collection('tasks').doc(date).get();
    return List<String>.from(doc.data()?['taskOrder'] ?? const []);
  }

  Future<Map<String, dynamic>?> item(String date, String id) async {
    final doc =
        await fake.collection('todos').doc(uid).collection('tasks').doc(date).collection('items').doc(id).get();
    return doc.data();
  }

  test('addTask stamps userId and records the id in taskOrder', () async {
    final id = await service.addTask(t('a', date: '2026-08-01'));
    expect((await item('2026-08-01', id))!['userId'], uid);
    expect(await order('2026-08-01'), [id]);
  });

  test('addTask appends a second untimed task after the first', () async {
    final a = await service.addTask(t('a', date: '2026-08-01'));
    final b = await service.addTask(t('b', date: '2026-08-01'));
    expect(await order('2026-08-01'), [a, b]);
  });

  // Regression: taskOrder listing an id with no document (deleted on another
  // device, or a partially-populated offline cache) threw `Bad state: No
  // element` out of getTasksInOrder and aborted the whole save.
  test('a stale id in taskOrder is skipped instead of failing the save', () async {
    final a = await service.addTask(t('a', date: '2026-08-01'));
    await fake.collection('todos').doc(uid).collection('tasks').doc('2026-08-01').set({
      'taskOrder': [a, 'ghost-id']
    });

    expect(await service.getTasksInOrder(uid, '2026-08-01'), hasLength(1));

    final b = await service.addTask(t('b', date: '2026-08-01'));
    expect(await order('2026-08-01'), contains(b));
    expect((await item('2026-08-01', b))!['title'], 'b');
  });

  // Regression: push used to delete + re-add with a NEW id, breaking id-keyed
  // links (e.g. a goal generation's taskIds). It now moves the doc, same id.
  test('pushTask moves the task to the next day keeping the same document id', () async {
    // Use a non-today date so the today-only score decrement is skipped.
    final id = await service.addTask(t('goalie', date: '2020-01-01', priority: Effort.high));

    await service.pushTask(t('goalie', date: '2020-01-01', priority: Effort.high, id: id));

    // Gone from the old day.
    expect(await order('2020-01-01'), isNot(contains(id)));
    expect(await item('2020-01-01', id), isNull);

    // Present on the next day, SAME id, pushCount bumped.
    expect(await order('2020-01-02'), contains(id));
    final moved = await item('2020-01-02', id);
    expect(moved, isNotNull);
    expect(moved!['pushCount'], 1);
  });
}
