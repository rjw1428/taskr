import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/performance/performance_history.dart';

Map<String, dynamic> doc(DateTime date, int all) =>
    {'date': Timestamp.fromDate(date), 'completed': {'ALL': all}};

void main() {
  final d1 = DateTime(2026, 9, 1);
  final d2 = DateTime(2026, 9, 2);
  final d3 = DateTime(2026, 9, 3);
  final history = PerformanceHistory([
    doc(d1, 1),
    doc(d2, 5),
    doc(d3, 2),
    // A pushed-only doc has no completed map (see PerformanceService.recordPush).
    {'date': Timestamp.fromDate(DateTime(2026, 9, 4)), 'pushed': {'ALL': 3}},
    {'completed': {'ALL': 99}}, // no date: never counted
  ]);

  // The 7-day chart used to come from its own `date > cutoff` query; slicing the
  // shared history must keep that exclusive lower bound.
  test('between is exclusive of after and inclusive of until', () {
    final sliced = history.between(after: d1, until: d3);
    expect(sliced.map((d) => (d['date'] as Timestamp).toDate()), [d2, d3]);
  });

  test('between drops docs without a date', () {
    expect(history.between().length, 4);
  });

  test('scoresByDay keys by day, treats a pushed-only doc as zero and honours until', () {
    final scores = history.scoresByDay(until: DateTime(2026, 9, 3, 12));
    expect(scores, {d1: 1, d2: 5, d3: 2});
    expect(history.scoresByDay()[DateTime(2026, 9, 4)], 0);
  });
}
