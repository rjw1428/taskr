import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

/// A Firestore whose collection-group queries fail the way the real one does
/// while a composite index is still building.
class _NoCollectionGroups extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collectionGroup(String collectionPath) => _FailingQuery();
}

// ignore: subtype_of_sealed_class
class _FailingQuery implements CollectionReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #get) {
      return Future<QuerySnapshot<Map<String, dynamic>>>.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'failed-precondition', message: 'index building'),
      );
    }
    return this;
  }
}

void main() {
  late FakeFirebaseFirestore fake;
  late HabitService habits;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    habits = HabitService()..db = fake;
    PerformanceService().db = fake; // toggleComplete records points through TaskService
  });

  // Calendar-day arithmetic: adding a Duration crosses the DST change an hour short.
  String dayStr(int offset) {
    final now = DateTime.now();
    return DateService().getString(DateTime(now.year, now.month, now.day + offset));
  }

  // A raw instance row the way TaskService.addTask stores one.
  Future<void> seedInstance(String habitId, String date, {required bool completed, String? id}) async {
    final day = fake.collection('todos').doc(uid).collection('tasks').doc(date);
    final ref = day.collection('items').doc(id ?? '$habitId-$date');
    // The date doc itself must exist for the partition to be listable.
    await day.set({'taskOrder': FieldValue.arrayUnion([ref.id])}, SetOptions(merge: true));
    await ref.set({
      'title': habitId, 'completed': completed, 'priority': 'low', 'added': 1, 'tags': [],
      'userId': uid, 'dueDate': date, 'habitId': habitId,
    });
  }

  Future<Map<String, dynamic>?> habitDoc(String id) async =>
      (await fake.collection('todos').doc(uid).collection('habits').doc(id).get()).data();

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

  group('while the collection-group index is building', () {
    setUp(() {
      fake = _NoCollectionGroups();
      habits.db = fake;
      PerformanceService().db = fake;
    });

    test('the watermark decides where materialization resumes', () async {
      final h = Habit(id: 'hb', title: 'Read', startDate: dayStr(0), lastMaterializedDate: dayStr(2));
      await fake.collection('todos').doc(uid).collection('habits').doc('hb').set(h.toJson()..remove('id'));
      for (var d = 0; d <= 2; d++) {
        await seedInstance('hb', dayStr(d), completed: false);
      }

      await habits.ensureInstances(h, horizonDays: 5);

      // Nothing can be read back to dedupe against, so only the days after the
      // watermark are written — exactly once each.
      final perDate = await instancesPerDate('hb');
      expect(perDate, {for (var d = 0; d <= 5; d++) dayStr(d): 1});
      expect((await habitDoc('hb'))!['lastMaterializedDate'], dayStr(5));
    });
  });

  group('reads', () {
    test('getHabit returns null for a missing doc and the habit otherwise', () async {
      expect(await habits.getHabit('nope'), isNull);
      final id = await habits.addHabit(Habit(title: 'Floss', startDate: dayStr(0)));
      final h = await habits.getHabit(id);
      expect(h?.title, 'Floss');
      expect(h?.id, id);
      expect(h?.lastMaterializedDate, isNotNull, reason: 'addHabit tops up immediately');
    });

    test('streamHabits orders newest first', () async {
      final col = fake.collection('todos').doc(uid).collection('habits');
      await col.doc('old').set({'title': 'Old', 'startDate': dayStr(0), 'createdAt': 1});
      await col.doc('new').set({'title': 'New', 'startDate': dayStr(0), 'createdAt': 2});
      await col.doc('none').set({'title': 'None', 'startDate': dayStr(0)});
      final list = await habits.streamHabits().first;
      expect(list.map((h) => h.id), ['new', 'old', 'none']);
    });
  });

  group('materialization guards', () {
    test('ensureInstances is a no-op for paused, id-less, or far-future habits', () async {
      await habits.ensureInstances(Habit(id: 'p', title: 'P', startDate: dayStr(0), status: 'paused'));
      await habits.ensureInstances(Habit(title: 'NoId', startDate: dayStr(0)));
      expect(await instancesPerDate('p'), isEmpty);

      await fake.collection('todos').doc(uid).collection('habits').doc('far').set({'title': 'Far'});
      final far = Habit(id: 'far', title: 'Far', startDate: dayStr(90));
      await habits.ensureInstances(far, horizonDays: 60);
      expect(await instancesPerDate('far'), isEmpty);
      expect(far.lastMaterializedDate, isNull, reason: 'nothing written, nothing bookkept');
    });

    test('ensureInstances skips a habit that is already being materialized', () async {
      await fake.collection('todos').doc(uid).collection('habits').doc('h1').set({'title': 'S'});
      final h = Habit(id: 'h1', title: 'S', startDate: dayStr(0));
      await Future.wait([habits.ensureInstances(h, horizonDays: 3), habits.ensureInstances(h, horizonDays: 3)]);
      final counts = await instancesPerDate('h1');
      expect(counts.length, 4);
      expect(counts.values.every((c) => c == 1), isTrue);
    });

    test('ensureInstancesOnce ignores paused and id-less habits', () async {
      HabitService.resetLaunchGuard();
      await habits.ensureInstancesOnce(Habit(id: 'p', title: 'P', startDate: dayStr(0), status: 'paused'));
      await habits.ensureInstancesOnce(Habit(title: 'NoId', startDate: dayStr(0)));
      expect(await instancesPerDate('p'), isEmpty);
    });

    test('ensureInstancesOnce releases the launch guard when the top-up throws', () async {
      HabitService.resetLaunchGuard();
      final bad = Habit(id: 'bad', title: 'Bad', startDate: 'not-a-date');
      await expectLater(habits.ensureInstancesOnce(bad), throwsA(anything));
      // The guard was released, so the next rebuild tries (and fails) again
      // rather than silently treating the habit as done.
      await expectLater(habits.ensureInstancesOnce(bad), throwsA(anything));
      HabitService.resetLaunchGuard();
    });
  });

  group('streaks', () {
    test('recomputeStreak counts the trailing run of completed occurrences, treating today as pending', () async {
      await fake.collection('todos').doc(uid).collection('habits').doc('h1').set({'title': 'S', 'longestStreak': 5});
      final h = Habit(id: 'h1', title: 'S', startDate: dayStr(-5), longestStreak: 5);
      await seedInstance('h1', dayStr(-4), completed: false);
      await seedInstance('h1', dayStr(-3), completed: true);
      await seedInstance('h1', dayStr(-2), completed: true);
      await seedInstance('h1', dayStr(-1), completed: true);
      await seedInstance('h1', dayStr(0), completed: false);

      await habits.recomputeStreak(h);
      final doc = (await habitDoc('h1'))!;
      expect(doc['currentStreak'], 3);
      expect(doc['longestStreak'], 5, reason: 'longest is never lowered');
      expect(doc['lastCompletedDate'], dayStr(-1));
    });

    test('a completed today counts, and a miss yesterday resets the streak', () async {
      await fake.collection('todos').doc(uid).collection('habits').doc('h1').set({'title': 'S'});
      final h = Habit(id: 'h1', title: 'S', startDate: dayStr(-2));
      await seedInstance('h1', dayStr(-2), completed: true);
      await seedInstance('h1', dayStr(-1), completed: false);
      await seedInstance('h1', dayStr(0), completed: true);

      await habits.recomputeStreak(h);
      final doc = (await habitDoc('h1'))!;
      expect(doc['currentStreak'], 1);
      expect(doc['longestStreak'], 1);
      expect(doc['lastCompletedDate'], dayStr(0));
    });

    test('recomputeStreak ignores a habit without an id; recomputeStreakById ignores a missing habit', () async {
      await habits.recomputeStreak(Habit(title: 'x', startDate: dayStr(0)));
      await habits.recomputeStreakById('missing');
      expect((await fake.collection('todos').doc(uid).collection('habits').get()).size, 0);
    });

    test('toggleComplete marks the instance and recomputes the streak either way', () async {
      final h = Habit(title: 'Stretch', startDate: dayStr(0));
      final id = await habits.addHabit(h);
      final today = dayStr(0);
      final items = await fake
          .collection('todos').doc(uid).collection('tasks').doc(today)
          .collection('items').where('habitId', isEqualTo: id).get();
      final inst = Task.fromJson({...items.docs.single.data(), 'id': items.docs.single.id});

      await habits.toggleComplete(inst, true);
      var row = (await items.docs.single.reference.get()).data()!;
      expect(row['completed'], isTrue);
      expect(row['completedTime'], startsWith(today));
      expect((await habitDoc(id))!['currentStreak'], 1);

      await habits.toggleComplete(inst, false);
      row = (await items.docs.single.reference.get()).data()!;
      expect(row['completed'], isFalse);
      expect(row['completedTime'], isNull);
      expect((await habitDoc(id))!['currentStreak'], 0);
      expect((await habitDoc(id))!['longestStreak'], 1);
    });

    test('toggleComplete on a plain task leaves habits alone', () async {
      await fake
          .collection('todos').doc(uid).collection('tasks').doc(dayStr(0))
          .collection('items').doc('t1').set({'title': 't', 'completed': false});
      await habits.toggleComplete(Task(id: 't1', added: 1, title: 't', dueDate: dayStr(0)), true);
      expect((await fake.collection('todos').doc(uid).collection('habits').get()).size, 0);
    });
  });

  group('pause, resume, delete', () {
    test('pauseHabit removes future incomplete instances but keeps completed history', () async {
      final h = Habit(title: 'Read', startDate: dayStr(0));
      final id = await habits.addHabit(h);
      final before = await instancesPerDate(id);
      expect(before.length, greaterThan(1));
      await seedInstance(id, dayStr(-1), completed: true, id: 'done-yesterday');
      // Mark today's instance done so it must survive the cleanup.
      final todayItems = await fake
          .collection('todos').doc(uid).collection('tasks').doc(dayStr(0))
          .collection('items').where('habitId', isEqualTo: id).get();
      await todayItems.docs.single.reference.update({'completed': true});

      await habits.pauseHabit(h);

      expect((await habitDoc(id))!['status'], 'paused');
      final after = await instancesPerDate(id);
      expect(after.keys, unorderedEquals([dayStr(-1), dayStr(0)]));
    });

    test('resumeHabit reactivates and re-materializes the horizon', () async {
      final h = Habit(title: 'Read', startDate: dayStr(0));
      final id = await habits.addHabit(h);
      final full = (await instancesPerDate(id)).length;
      await habits.pauseHabit(h);
      h.status = 'paused';
      expect(await instancesPerDate(id), isEmpty);

      await habits.resumeHabit(h);

      expect(h.status, 'active');
      expect((await habitDoc(id))!['status'], 'active');
      expect((await instancesPerDate(id)).length, full);
    });

    test('deleteHabit removes the template immediately and its future instances shortly after', () async {
      final h = Habit(title: 'Read', startDate: dayStr(0));
      final id = await habits.addHabit(h);
      await seedInstance(id, dayStr(-3), completed: true, id: 'history');

      await habits.deleteHabit(h);
      expect(await habitDoc(id), isNull);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect((await instancesPerDate(id)).keys, [dayStr(-3)], reason: 'completed history is kept');
    });
  });
}
