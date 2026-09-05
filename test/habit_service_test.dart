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

  // The Goals tab tops habits up from inside its StreamBuilder, so the top-up
  // used to run — and read the habit's whole instance history — on every
  // rebuild. The list now goes through ensureInstancesOnce, which must do the
  // work exactly once per launch and still let a direct call run again.
  test('ensureInstancesOnce tops up a habit only once per launch', () async {
    HabitService.resetLaunchGuard();
    final today = DateService().getString(DateTime.now());
    final h = Habit(id: 'h1', title: 'Shave', effort: Effort.low, startDate: today, recurrenceType: 'Daily');
    await fake.collection('todos').doc(uid).collection('habits').doc('h1').set({'title': 'Shave', 'status': 'active'});

    await habits.ensureInstancesOnce(h);
    final first = await instancesPerDate('h1');
    expect(first, isNotEmpty);

    // Wipe the instances behind the guard's back: a second once-call must not
    // notice, a direct call must.
    for (final date in first.keys) {
      final items = await fake
          .collection('todos').doc(uid).collection('tasks').doc(date)
          .collection('items').where('habitId', isEqualTo: 'h1').get();
      for (final d in items.docs) {
        await d.reference.delete();
      }
    }
    await habits.ensureInstancesOnce(h);
    expect(await instancesPerDate('h1'), isEmpty, reason: 'guarded call must be a no-op');

    await habits.ensureInstances(h);
    expect((await instancesPerDate('h1')).length, first.length, reason: 'direct call still materializes');
    HabitService.resetLaunchGuard();
  });

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

  // Regression (2026-08): "No Vending Machine" — a Tue/Wed/Thu habit whose title
  // was edited — ended up with lastMaterializedDate two months ahead of its last
  // real instance, so every upcoming occurrence was missing and could never come
  // back. updateHabit deletes the future before regenerating it, and the
  // regenerating writes did not land; the watermark advanced anyway, because it
  // moves on loop completion and addTask cannot report failure (ackWrite
  // swallows errors and offline timeouts by design).
  group('backfill behind a stale watermark', () {
    Habit tueWedThu() => Habit(
          title: 'No Vending Machine',
          effort: Effort.low,
          recurrenceType: 'Weekly',
          frequency: 1,
          daysOfWeek: const {
            'Su': false, 'Mo': false, 'Tu': true, 'We': true,
            'Th': true, 'Fr': false, 'Sa': false,
          },
          startDate: DateService().getString(DateTime.now()),
        );

    test('instances missing behind the watermark are regenerated', () async {
      final h = tueWedThu();
      final id = await habits.addHabit(h);
      final full = (await instancesPerDate(id)).length;
      expect(full, greaterThan(0));

      // Exactly the observed corruption: every future instance gone, watermark
      // still claiming the whole horizon.
      final todayStr = DateService().getString(DateTime.now());
      final wm = h.lastMaterializedDate!;
      for (final dd in (await fake.collection('todos').doc(uid).collection('tasks').get()).docs) {
        final items = await fake
            .collection('todos').doc(uid).collection('tasks').doc(dd.id)
            .collection('items').where('habitId', isEqualTo: id).get();
        for (final i in items.docs) {
          if (dd.id.compareTo(todayStr) >= 0) await i.reference.delete();
        }
      }
      expect((await instancesPerDate(id)).length, 0);

      h.lastMaterializedDate = wm;
      await habits.ensureInstances(h);

      expect((await instancesPerDate(id)).length, full);
    });

    test('editing the title leaves the habit fully materialized', () async {
      final h = tueWedThu();
      final id = await habits.addHabit(h);
      final full = (await instancesPerDate(id)).length;

      h.title = 'No Vending Machine - including soda';
      await habits.updateHabit(h);

      final after = await instancesPerDate(id);
      expect(after.length, full);
      expect(after.values.every((n) => n == 1), isTrue, reason: 'no duplicates');
    });

    test('a repeated pass does not duplicate', () async {
      final h = tueWedThu();
      final id = await habits.addHabit(h);
      final full = (await instancesPerDate(id)).length;
      await habits.ensureInstances(h);
      await habits.ensureInstances(h);
      expect((await instancesPerDate(id)).length, full);
    });
  });
}
