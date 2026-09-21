import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

/// A Firestore whose collection-group queries fail the way the real one does
/// while a composite index is still building.
class _NoCollectionGroups extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collectionGroup(String collectionPath) => _FailingQuery();
}

// ignore: subtype_of_sealed_class
/// Accepts any query shaping and fails on read, which is where the real SDK
/// reports a missing index.
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late TaskService tasks;
  late RecurringSeriesService series;

  setUp(() async {
    env = await TestEnv.create();
    tasks = TaskService();
    series = RecurringSeriesService();
    env.functions['scheduleReminder'] = (payload) => {'reminderTaskName': 'queues/q/tasks/${payload['taskId']}'};
  });
  tearDown(() => env.dispose());

  RecurringTask template({DateTime? start, DateTime? end, String? reminder}) => RecurringTask(
        recurrenceType: 'Daily',
        startDate: start ?? DateTime.now(),
        endDate: end ?? DateTime.now().add(const Duration(days: 365)),
        reminderTimeOfDay: reminder,
      );

  Task prototype() => Task(added: 1, title: 'standup', completed: false);

  Future<int> occurrenceCount() async {
    var n = 0;
    final dates = await env.col('tasks').get();
    for (final d in dates.docs) {
      n += (await env.col('tasks').doc(d.id).collection('items').get()).size;
    }
    return n;
  }

  group('runLaunchPass', () {
    test('runs once per launch', () async {
      final written = await tasks.createRecurringSeries(template(reminder: '23:59'), prototype());
      await series.runLaunchPass();
      final calls = env.functionCalls.where((c) => c.name == 'scheduleReminder').length;
      expect(calls, greaterThan(0));
      await series.runLaunchPass();
      expect(env.functionCalls.where((c) => c.name == 'scheduleReminder').length, calls);
      expect(await tasks.seriesInstances(written.templateId), hasLength(RecurringSeries.horizonDays + 1));
    });
  });

  group('topUpAllSeries', () {
    test('does nothing when signed out', () async {
      await tasks.createRecurringSeries(template(), prototype());
      AuthService().user = null;
      await series.topUpAllSeries();
      expect(env.functionCalls, isEmpty);
    });

    test('survives a template it cannot parse', () async {
      await env.col('recurring').add({'bogus': true});
      await series.topUpAllSeries();
    });
  });

  group('ensureInstances', () {
    test('ignores a template with no id', () async {
      await series.ensureInstances(template());
      expect(await occurrenceCount(), 0);
    });

    test('ignores a series past its end date', () async {
      final t = template(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now().subtract(const Duration(days: 2)),
      )..id = 'old';
      await series.ensureInstances(t);
      expect(await occurrenceCount(), 0);
    });

    test('extends a short series to the horizon and enqueues reminders in range', () async {
      final written = await tasks.createRecurringSeries(
        template(end: DateTime.now().add(const Duration(days: 3)), reminder: '23:59'),
        prototype(),
      );
      final t = (await tasks.getRecurringTemplate(written.templateId))
        ..id = written.templateId
        ..endDate = DateTime.now().add(const Duration(days: 40));
      await env.col('recurring').doc(written.templateId).update({'endDate': t.endDate!.toIso8601String()});

      await series.ensureInstances(t);
      expect(await tasks.seriesInstances(written.templateId), hasLength(41));
      expect(env.functionCalls.where((c) => c.name == 'scheduleReminder').length, greaterThan(4));
    });

    test('models new occurrences on a completed one when nothing is outstanding', () async {
      final written = await tasks.createRecurringSeries(
        template(start: DateTime.now().subtract(const Duration(days: 2)), end: DateTime.now().subtract(const Duration(days: 1))),
        prototype(),
      );
      for (final occ in written.occurrences) {
        await env.col('tasks').doc(occ.dueDate).collection('items').doc(occ.id).update({'completed': true});
      }
      final t = template(start: DateTime.now().subtract(const Duration(days: 2)))..id = written.templateId;
      await series.ensureInstances(t);
      final all = await tasks.seriesInstances(written.templateId);
      expect(all!.length, greaterThan(2));
      expect(all.where((x) => !x.completed).every((x) => x.title == 'standup'), isTrue);
    });

    test('a concurrent pass over the same series is skipped', () async {
      final written = await tasks.createRecurringSeries(template(), prototype());
      final t = template()..id = written.templateId;
      await Future.wait([series.ensureInstances(t), series.ensureInstances(t)]);
      expect(await tasks.seriesInstances(written.templateId), hasLength(RecurringSeries.horizonDays + 1));
    });

    test('concurrent passes with work to do write the extension once', () async {
      final written = await tasks.createRecurringSeries(
        template(end: DateTime.now().add(const Duration(days: 3))),
        prototype(),
      );
      final t = (await tasks.getRecurringTemplate(written.templateId))
        ..id = written.templateId
        ..endDate = DateTime.now().add(const Duration(days: 40));
      await Future.wait([series.ensureInstances(t), series.ensureInstances(t)]);
      expect(await tasks.seriesInstances(written.templateId), hasLength(41));
    });

    test('a later pass over the same series runs again once the first has finished', () async {
      final written = await tasks.createRecurringSeries(
        template(end: DateTime.now().add(const Duration(days: 3))),
        prototype(),
      );
      final t = (await tasks.getRecurringTemplate(written.templateId))
        ..id = written.templateId
        ..endDate = DateTime.now().add(const Duration(days: 10));
      await series.ensureInstances(t);
      expect(await tasks.seriesInstances(written.templateId), hasLength(11));

      t.endDate = DateTime.now().add(const Duration(days: 20));
      await series.ensureInstances(t);
      expect(await tasks.seriesInstances(written.templateId), hasLength(21));
    });

    test('a series with no end date is extended to the horizon', () async {
      final written = await tasks.createRecurringSeries(
        template(end: DateTime.now().add(const Duration(days: 3))),
        prototype(),
      );
      final t = (await tasks.getRecurringTemplate(written.templateId))
        ..id = written.templateId
        ..endDate = null;
      await series.ensureInstances(t);
      expect(await tasks.seriesInstances(written.templateId), hasLength(RecurringSeries.horizonDays + 1));
    });

    group('while the collection-group index is building', () {
      setUp(() => series.db = _NoCollectionGroups());

      test('the pass is skipped whatever the watermark says', () async {
        // The template has no title or effort of its own, so without a readable
        // occurrence there is nothing to extend with; the watermark is not a
        // substitute for the query, and no write or reminder call happens.
        for (final t in [
          template(reminder: '08:00')
            ..id = 'r1'
            ..lastMaterializedDate = DateService().getString(DateTime.now()),
          template()..id = 'r2',
        ]) {
          await series.ensureInstances(t);
        }
        expect(await occurrenceCount(), 0);
        expect(env.functionCalls, isEmpty);
      });
    });
  });
}
