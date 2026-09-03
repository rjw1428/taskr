import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/performance/performance_page.dart';
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

  // Regression: the daily-score chart plots by list index while the axis labels
  // each index as "N days back from today". A day with no perf doc used to
  // shorten the list, shifting every earlier score onto a later weekday.
  group('alignDailyCompleted', () {
    Map<String, dynamic> doc(DateTime day, int all) =>
        {'date': Timestamp.fromDate(day), 'completed': {'ALL': all}};

    final today = DateTime(2026, 8, 26); // a Wednesday

    test('fills days that have no performance doc', () {
      final aligned = alignDailyCompleted([
        doc(DateTime(2026, 8, 24), 5), // Mon
        doc(today, 7), // Wed — nothing on Tue
      ], today);

      expect(aligned.length, 7);
      expect(aligned[4]['ALL'], 5); // Mon, two days back
      expect(aligned[5], isEmpty); // Tue
      expect(aligned[6]['ALL'], 7); // Wed, today
      expect(aligned.take(4).every((d) => d.isEmpty), isTrue);
    });

    test('ignores docs outside the window and orders oldest first', () {
      final aligned = alignDailyCompleted([
        doc(DateTime(2026, 8, 1), 99), // long before the window
        doc(DateTime(2026, 8, 20), 1),
        doc(DateTime(2026, 8, 22), 3),
      ], today);

      expect(aligned.map((d) => d['ALL'] ?? 0).toList(), [1, 0, 3, 0, 0, 0, 0]);
    });

    test('treats a pushed-only doc as an empty completed map', () {
      final aligned = alignDailyCompleted([
        {'date': Timestamp.fromDate(today), 'pushed': {'ALL': 3}},
      ], today);

      expect(aligned.last, isEmpty);
    });
  });
}
