import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  late FakeFirebaseFirestore fake;
  late HabitService habits;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    habits = HabitService()..db = fake;
  });

  // Count how many instances exist per date for [habitId].
  Future<Map<String, int>> instancesPerDate(String habitId) async {
    final counts = <String, int>{};
    final dates = await fake.collection('todos').doc(uid).collection('tasks').get();
    for (final dd in dates.docs) {
      final items = await fake
          .collection('todos').doc(uid).collection('tasks').doc(dd.id)
          .collection('items').where('habitId', isEqualTo: habitId).get();
      if (items.size > 0) counts[dd.id] = items.size;
    }
    return counts;
  }

  // Regression: ensureInstances used to dedupe only via lastMaterializedDate,
  // so a null/stale value (which every habit edit produces) re-materialized the
  // whole window and piled up duplicate instances. It must now be idempotent.
  test('ensureInstances never duplicates instances across repeated runs', () async {
    final today = DateService().getString(DateTime.now());
    final h = Habit(id: 'h1', title: 'Shave', effort: Effort.low, startDate: today, recurrenceType: 'Daily');
    // The habit doc must exist so the lastMaterializedDate bookkeeping .update() succeeds.
    await fake.collection('todos').doc(uid).collection('habits').doc('h1').set({'title': 'Shave', 'status': 'active'});

    await habits.ensureInstances(h, horizonDays: 5);
    final first = await instancesPerDate('h1');
    expect(first, isNotEmpty, reason: 'first run should materialize instances');
    expect(first.values.every((c) => c == 1), isTrue);

    // Simulate what a habit edit does: clear the bookkeeping, then top up again.
    h.lastMaterializedDate = null;
    await habits.ensureInstances(h, horizonDays: 5);
    await habits.ensureInstances(h, horizonDays: 5);

    final after = await instancesPerDate('h1');
    expect(after.length, first.length, reason: 'no new dates should appear');
    expect(after.values.every((c) => c == 1), isTrue,
        reason: 'each date must still have exactly one instance');
  });
}
