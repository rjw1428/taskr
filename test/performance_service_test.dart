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

  group('service coverage', _moreTests);

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
    expect(data['completed']['ALL'], isA<int>(), reason: 'points stay whole numbers in Firestore');
  });

  test('untagged completions keep accumulating under Other', () async {
    await PerformanceService().updatePerfomanceStats(uid, task(priority: Effort.low), true); // +1
    await PerformanceService().updatePerfomanceStats(uid, task(priority: Effort.high), true); // +3
    await PerformanceService().updatePerfomanceStats(uid, task(priority: Effort.medium), false); // -2
    final data = (await fake.collection('todos').doc(uid).collection('performance').doc(date).get()).data()!;
    expect(data['completed']['Other'], 2);
    expect(data['completed']['Other'], isA<int>());
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

// ── Added coverage: streams, score counters, tag branches ─────────────────────

void _moreTests() {
  late FakeFirebaseFirestore fake;
  const uid = 'u1';

  Future<void> seed(String day, DateTime date, int all) =>
      fake.collection('todos').doc(uid).collection('performance').doc(day).set({
        'date': Timestamp.fromDate(date),
        'completed': {'ALL': all},
      });

  Future<Map<String, dynamic>> perfDoc(String day) async =>
      (await fake.collection('todos').doc(uid).collection('performance').doc(day).get()).data()!;

  setUp(() {
    PerformanceService.resetInstance();
    fake = FakeFirebaseFirestore();
    PerformanceService().db = fake;
  });

  test('getScore maps every effort level', () {
    final s = PerformanceService();
    expect(s.getScore(Effort.high), 3);
    expect(s.getScore(Effort.medium), 2);
    expect(s.getScore(Effort.low), 1);
    expect(s.getScore(Effort.info), 0);
  });

  test('incrementScore and decrementScore adjust the user doc counter', () async {
    await fake.collection('todos').doc(uid).set({'currentScore': 10});

    await PerformanceService().incrementScore(uid, 5);
    expect((await fake.collection('todos').doc(uid).get()).data()!['currentScore'], 15);

    await PerformanceService().decrementScore(uid, 2);
    expect((await fake.collection('todos').doc(uid).get()).data()!['currentScore'], 13);
  });

  test('streamPerformance yields docs dated strictly after the cutoff', () async {
    await seed('2026-08-01', DateTime(2026, 8, 1), 1);
    await seed('2026-08-05', DateTime(2026, 8, 5), 2);
    await seed('2026-08-09', DateTime(2026, 8, 9), 3);

    final docs = await PerformanceService().streamPerformance(uid, DateTime(2026, 8, 5)).first;

    expect(docs.map((d) => d['completed']['ALL']), [3]);
  });

  test('streamPerformanceForMonth yields docs within the inclusive bounds', () async {
    await seed('2026-07-31', DateTime(2026, 7, 31), 1);
    await seed('2026-08-01', DateTime(2026, 8, 1), 2);
    await seed('2026-08-15', DateTime(2026, 8, 15), 3);
    await seed('2026-08-31', DateTime(2026, 8, 31), 4);
    await seed('2026-09-01', DateTime(2026, 9, 1), 5);

    final docs =
        await PerformanceService().streamPerformanceForMonth(uid, DateTime(2026, 8, 1), DateTime(2026, 8, 31)).first;

    expect(docs.map((d) => d['completed']['ALL']).toSet(), {2, 3, 4});
  });

  test('updatePerfomanceStats tallies per tag and untagged work under Other', () async {
    final tagged = Task(
      added: 1,
      title: 'T',
      priority: Effort.medium,
      dueDate: '2026-08-02',
      tags: [Tag(id: 'work', label: 'Work'), Tag(id: 'home', label: 'Home')],
    );
    final untagged = Task(added: 1, title: 'U', priority: Effort.low, dueDate: '2026-08-02');

    await PerformanceService().updatePerfomanceStats(uid, tagged, true); // +2 to ALL, work, home
    await PerformanceService().updatePerfomanceStats(uid, tagged, true); // again
    await PerformanceService().updatePerfomanceStats(uid, untagged, true); // +1 ALL, Other
    await PerformanceService().updatePerfomanceStats(uid, tagged, false); // -2 ALL, work, home

    final completed = (await perfDoc('2026-08-02'))['completed'] as Map;
    expect(completed['ALL'], 3);
    expect(completed['work'], 2);
    expect(completed['home'], 2);
    expect(completed['Other'], 1);
    expect(completed.values, everyElement(isA<int>()));
    expect((await perfDoc('2026-08-02'))['date'], isA<Timestamp>());
  });

  test('updatePerfomanceStats falls back to today when the task has no due date', () async {
    final task = Task(added: 1, title: 'T', priority: Effort.high);
    await PerformanceService().updatePerfomanceStats(uid, task, true);

    final today = DateService().getString(DateTime.now());
    expect((await perfDoc(today))['completed']['ALL'], 3);
  });

  test('recordPush tallies per tag and untagged work under Other', () async {
    final tagged = Task(
      added: 1,
      title: 'T',
      priority: Effort.medium,
      dueDate: '2026-08-02',
      tags: [Tag(id: 'work', label: 'Work')],
    );
    final untagged = Task(added: 1, title: 'U', priority: Effort.low, dueDate: '2026-08-02');

    await PerformanceService().recordPush(uid, tagged, '2026-08-02');
    await PerformanceService().recordPush(uid, tagged, '2026-08-02');
    await PerformanceService().recordPush(uid, untagged, '2026-08-02');

    final pushed = (await perfDoc('2026-08-02'))['pushed'] as Map;
    expect(pushed['ALL'], 5);
    expect(pushed['work'], 4);
    expect(pushed['Other'], 1);
  });

  test('recordPush leaves an existing completed tally untouched', () async {
    await seed('2026-08-02', DateTime(2026, 8, 2), 7);
    final task = Task(added: 1, title: 'T', priority: Effort.high, dueDate: '2026-08-02');

    await PerformanceService().recordPush(uid, task, '2026-08-02');

    final doc = await perfDoc('2026-08-02');
    expect(doc['completed']['ALL'], 7);
    expect(doc['pushed']['ALL'], 3);
  });
}
