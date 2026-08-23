import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  // reportError surfaces a snackbar through the global messenger, which needs a
  // binding. Reminder scheduling legitimately fails here (no Firebase app), and
  // that failure path is part of what these tests exercise.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fake;
  late TaskService tasks;
  late RecurringSeriesService series;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    PerformanceService().db = fake;
    tasks = TaskService()..db = fake;
    series = RecurringSeriesService()..db = fake;
    RecurringSeriesService.resetPassGuard();
  });

  RecurringTask template({DateTime? start, DateTime? end, String? reminder}) => RecurringTask(
        recurrenceType: 'Daily',
        startDate: start ?? DateTime.now(),
        endDate: end ?? DateTime.now().add(const Duration(days: 365)),
        reminderTimeOfDay: reminder,
      );

  Task prototype() => Task(
        added: 1,
        title: 'standup',
        priority: Effort.medium,
        completed: false,
        tags: const [],
      );

  Future<int> occurrenceCount() async {
    var n = 0;
    final dates = await fake.collection('todos').doc(uid).collection('tasks').get();
    for (final d in dates.docs) {
      final items =
          await fake.collection('todos').doc(uid).collection('tasks').doc(d.id).collection('items').get();
      n += items.size;
    }
    return n;
  }

  Future<RecurringTask> reloadTemplate(String id) async {
    final doc = await fake.collection('todos').doc(uid).collection('recurring').doc(id).get();
    return RecurringTask.fromJson(doc.data()!)..id = id;
  }

  group('ensureInstances idempotency', () {
    test('a second pass over an unchanged series writes nothing new', () async {
      final written = await tasks.createRecurringSeries(template(), prototype());
      final after = await occurrenceCount();

      await series.ensureInstances(await reloadTemplate(written.templateId));
      expect(await occurrenceCount(), after);

      await series.ensureInstances(await reloadTemplate(written.templateId));
      expect(await occurrenceCount(), after);
    });

    test('a series with no watermark does not duplicate', () async {
      // Exactly the shape of a series created before this change.
      final written = await tasks.createRecurringSeries(template(), prototype());
      final after = await occurrenceCount();

      await fake
          .collection('todos')
          .doc(uid)
          .collection('recurring')
          .doc(written.templateId)
          .update({'lastMaterializedDate': null});

      await series.ensureInstances(await reloadTemplate(written.templateId));
      // The collection-group query, not the watermark, is the authority.
      expect(await occurrenceCount(), after);
    });

    test('a stale watermark does not duplicate', () async {
      final written = await tasks.createRecurringSeries(template(), prototype());
      final after = await occurrenceCount();

      await fake
          .collection('todos')
          .doc(uid)
          .collection('recurring')
          .doc(written.templateId)
          .update({'lastMaterializedDate': DateService().getString(DateTime.now())});

      await series.ensureInstances(await reloadTemplate(written.templateId));
      expect(await occurrenceCount(), after);
    });

    test('a series past its end date materializes nothing', () async {
      final start = DateTime.now().subtract(const Duration(days: 30));
      final written = await tasks.createRecurringSeries(
        template(start: start, end: DateTime.now().subtract(const Duration(days: 10))),
        prototype(),
      );
      final after = await occurrenceCount();
      await series.ensureInstances(await reloadTemplate(written.templateId));
      expect(await occurrenceCount(), after);
    });

    test('a template with no id is ignored', () async {
      await series.ensureInstances(template());
      expect(await occurrenceCount(), 0);
    });
  });

  group('topUpAllSeries', () {
    test('extends a series whose watermark has fallen behind', () async {
      final written = await tasks.createRecurringSeries(template(), prototype());
      final before = await occurrenceCount();

      // Simulate time passing: drop the tail of the series and rewind the
      // watermark, so the horizon now reaches further than what exists.
      final cutoff = DateService().getString(DateTime.now().add(const Duration(days: 30)));
      final existing = await tasks.seriesInstances(written.templateId);
      for (final t in existing!.where((t) => t.dueDate!.compareTo(cutoff) > 0)) {
        await tasks.deleteTask(t);
      }
      await fake
          .collection('todos')
          .doc(uid)
          .collection('recurring')
          .doc(written.templateId)
          .update({'lastMaterializedDate': cutoff});

      expect(await occurrenceCount(), lessThan(before));
      await series.topUpAllSeries();
      expect(await occurrenceCount(), before);
    });

    test('runLaunchPass only runs once per launch', () async {
      await tasks.createRecurringSeries(template(), prototype());
      await series.runLaunchPass();
      final after = await occurrenceCount();
      // A second call is a no-op regardless of state.
      await series.runLaunchPass();
      expect(await occurrenceCount(), after);
    });

    test('a pass with no series is harmless', () async {
      await series.topUpAllSeries();
      expect(await occurrenceCount(), 0);
    });
  });

  group('delete series', () {
    test('removes outstanding occurrences and the template', () async {
      final written = await tasks.createRecurringSeries(template(), prototype());
      final first = written.occurrences.first;

      await tasks.deleteRecurringTemplate(
        first.copyWith(recurringTemplateId: written.templateId),
        await reloadTemplate(written.templateId),
      );

      expect(await occurrenceCount(), 0);
      final doc = await fake.collection('todos').doc(uid).collection('recurring').doc(written.templateId).get();
      expect(doc.exists, isFalse);
    });

    test('preserves completed occurrences as history', () async {
      final written = await tasks.createRecurringSeries(template(), prototype());
      final completed = written.occurrences[3];
      await fake
          .collection('todos')
          .doc(uid)
          .collection('tasks')
          .doc(completed.dueDate)
          .collection('items')
          .doc(completed.id)
          .update({'completed': true});

      await tasks.deleteRecurringTemplate(
        written.occurrences.first.copyWith(recurringTemplateId: written.templateId),
        await reloadTemplate(written.templateId),
      );

      expect(await occurrenceCount(), 1);
    });
  });

  group('edit series', () {
    test('re-materializes on the same horizon after a cadence change', () async {
      final written = await tasks.createRecurringSeries(template(), prototype());
      expect(await occurrenceCount(), RecurringSeries.horizonDays + 1);

      final edited = RecurringTask(
        recurrenceType: 'Weekly',
        frequency: 3,
        daysOfWeek: const {'Mo': true},
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 365)),
      );

      await tasks.updateRecurringTemplate(
        written.occurrences.first.copyWith(recurringTemplateId: written.templateId),
        edited,
      );

      // A 3-week cadence across the same 60-day horizon, not a different one.
      final remaining = await occurrenceCount();
      expect(remaining, lessThanOrEqualTo(4));
      expect(remaining, greaterThan(0));
    });

    test('a reminder-time change rewrites future occurrences', () async {
      final written = await tasks.createRecurringSeries(template(reminder: '08:30'), prototype());

      final edited = RecurringTask(
        recurrenceType: 'Daily',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 365)),
        reminderTimeOfDay: '19:45',
      );

      await tasks.updateRecurringTemplate(
        written.occurrences.first.copyWith(recurringTemplateId: written.templateId),
        edited,
      );

      final dates = await fake.collection('todos').doc(uid).collection('tasks').get();
      var checked = 0;
      for (final d in dates.docs) {
        final items =
            await fake.collection('todos').doc(uid).collection('tasks').doc(d.id).collection('items').get();
        for (final i in items.docs) {
          final reminder = i.data()['reminderTime'] as String?;
          if (reminder == null) continue;
          final local = DateTime.parse(reminder).toLocal();
          expect(local.hour, 19);
          expect(local.minute, 45);
          checked++;
        }
      }
      expect(checked, greaterThan(0));
    });
  });
}
