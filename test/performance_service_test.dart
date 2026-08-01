import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  late FakeFirebaseFirestore fake;
  const uid = 'u1';
  const date = '2026-08-01';

  Task task({Effort priority = Effort.high}) =>
      Task(added: 1, title: 'T', priority: priority, dueDate: date);

  setUp(() {
    fake = FakeFirebaseFirestore();
    PerformanceService().db = fake;
  });

  // Regression: recordPush creates a perf doc with `pushed`/`date` but no
  // `completed` map. updatePerfomanceStats used to do Map.from(null) on that
  // doc and throw, which aborted task completion.
  test('updatePerfomanceStats does not throw when the day has pushed-only perf doc', () async {
    await fake.collection('todos').doc(uid).collection('performance').doc(date).set({
      'pushed': {'ALL': 3},
      'date': DateTime(2026, 8, 1),
    });

    await PerformanceService().updatePerfomanceStats(uid, task(), true);

    final data = (await fake.collection('todos').doc(uid).collection('performance').doc(date).get()).data()!;
    expect(data['completed']['ALL'], 3); // high effort scores 3
    expect(data['pushed']['ALL'], 3); // left untouched
  });

  test('updatePerfomanceStats accumulates and can subtract', () async {
    await PerformanceService().updatePerfomanceStats(uid, task(priority: Effort.high), true); // +3
    await PerformanceService().updatePerfomanceStats(uid, task(priority: Effort.low), true); // +1
    await PerformanceService().updatePerfomanceStats(uid, task(priority: Effort.low), false); // -1
    final data = (await fake.collection('todos').doc(uid).collection('performance').doc(date).get()).data()!;
    expect(data['completed']['ALL'], 3);
  });

  test('recordPush accumulates deferred points', () async {
    await PerformanceService().recordPush(uid, task(priority: Effort.high), date); // +3
    await PerformanceService().recordPush(uid, task(priority: Effort.low), date); // +1
    final data = (await fake.collection('todos').doc(uid).collection('performance').doc(date).get()).data()!;
    expect(data['pushed']['ALL'], 4);
  });
}
