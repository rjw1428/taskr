import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  late FakeFirebaseFirestore fake;
  late TaskService service;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    PerformanceService().db = fake;
    service = TaskService()..db = fake;
  });

  RecurringTask template({
    String type = 'Daily',
    int? every,
    Map<String, bool>? days,
    DateTime? start,
    DateTime? end,
    String? reminder,
  }) =>
      RecurringTask(
        recurrenceType: type,
        frequency: every,
        daysOfWeek: days,
        startDate: start ?? DateTime.now(),
        endDate: end ?? DateTime.now().add(const Duration(days: 365)),
        reminderTimeOfDay: reminder,
      );

  Task prototype({bool countdown = false, Effort priority = Effort.medium}) => Task(
        added: 1,
        title: 'standup',
        description: 'daily sync',
        priority: priority,
        completed: false,
        countdown: countdown,
        tags: const [],
      );

  Future<List<Map<String, dynamic>>> allOccurrences() async {
    final out = <Map<String, dynamic>>[];
    final dates = await fake.collection('todos').doc(uid).collection('tasks').get();
    for (final d in dates.docs) {
      final items = await fake
          .collection('todos')
          .doc(uid)
          .collection('tasks')
          .doc(d.id)
          .collection('items')
          .get();
      for (final i in items.docs) {
        out.add({...i.data(), 'id': i.id});
      }
    }
    return out;
  }

  Future<List<String>> order(String date) async {
    final doc = await fake.collection('todos').doc(uid).collection('tasks').doc(date).get();
    return List<String>.from(doc.data()?['taskOrder'] ?? const []);
  }

  group('createRecurringSeries', () {
    test('materializes only the horizon, not the whole series', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      // A year-long daily series bounded to today + 60.
      expect(written.occurrences.length, RecurringSeries.horizonDays + 1);
      expect((await allOccurrences()).length, RecurringSeries.horizonDays + 1);
    });

    test('writes the template and records the watermark', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      final doc = await fake.collection('todos').doc(uid).collection('recurring').doc(written.templateId).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['lastMaterializedDate'], written.occurrences.last.dueDate);
    });

    test('every occurrence carries userId and the template id', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      final occurrences = await allOccurrences();
      expect(occurrences.every((o) => o['userId'] == uid), isTrue);
      expect(occurrences.every((o) => o['recurringTemplateId'] == written.templateId), isTrue);
    });

    test('countdown applies to every occurrence, not just the first', () async {
      // The old path built the first task with `countdown` and dropped it from
      // every later one.
      await service.createRecurringSeries(template(), prototype(countdown: true));
      final occurrences = await allOccurrences();
      expect(occurrences.length, greaterThan(1));
      expect(occurrences.every((o) => o['countdown'] == true), isTrue);
    });

    test('each occurrence lands in its own date partition and taskOrder', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      for (final occurrence in written.occurrences.take(5)) {
        expect(await order(occurrence.dueDate!), contains(occurrence.id));
      }
    });

    test('the first occurrence is slotted, not blindly appended', () async {
      final today = DateService().getString(DateTime.now());
      final existing = await service.addTask(Task(added: 1, title: 'existing', dueDate: today, priority: Effort.low));

      // An untimed Info task pins to the top (TaskOrdering rule 1). arrayUnion
      // would append it instead, so index 0 is what distinguishes the ordered
      // insert from the read-free path the later occurrences use.
      final written = await service.createRecurringSeries(
        template(start: DateTime.now()),
        prototype(priority: Effort.info),
      );

      final dayOrder = await order(today);
      expect(dayOrder, contains(existing));
      expect(dayOrder.first, written.occurrences.first.id);
    });

    test('the day\'s existing tasks survive the first occurrence being inserted', () async {
      final today = DateService().getString(DateTime.now());
      final a = await service.addTask(Task(added: 1, title: 'a', dueDate: today, priority: Effort.low));
      final b = await service.addTask(Task(added: 1, title: 'b', dueDate: today, priority: Effort.low));

      await service.createRecurringSeries(template(start: DateTime.now()), prototype());

      final dayOrder = await order(today);
      expect(dayOrder, containsAllInOrder([a, b]));
      expect(dayOrder.length, 3);
    });

    test('later occurrences land alone on their own empty days', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      for (final occurrence in written.occurrences.skip(1).take(4)) {
        expect(await order(occurrence.dueDate!), [occurrence.id]);
      }
    });

    test('a series starting beyond the horizon still writes one occurrence', () async {
      final start = DateTime.now().add(const Duration(days: 180));
      final written = await service.createRecurringSeries(
        template(start: start, end: start.add(const Duration(days: 30))),
        prototype(),
      );
      expect(written.occurrences.length, 1);
      expect((await allOccurrences()).length, 1);
    });

    test('a time-of-day reminder resolves per occurrence', () async {
      final written = await service.createRecurringSeries(
        template(reminder: '08:30'),
        prototype(),
      );
      for (final occurrence in written.occurrences.take(5)) {
        final local = DateTime.parse(occurrence.reminderTime!).toLocal();
        expect(local.hour, 8);
        expect(local.minute, 30);
        expect(DateService().getString(local), occurrence.dueDate);
      }
    });

    test('no reminder time means no reminder on any occurrence', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      expect(written.occurrences.every((o) => o.reminderTime == null), isTrue);
    });

    test('a 3-week cadence over a year yields the horizon occurrences', () async {
      // The case that motivated the change.
      final written = await service.createRecurringSeries(
        template(type: 'Weekly', every: 3, days: const {'Mo': true}),
        prototype(),
      );
      expect(written.occurrences.length, lessThanOrEqualTo(4));
      expect(written.occurrences, isNotEmpty);
    });
  });

  group('materializeOccurrences', () {
    test('extends a series and advances the watermark', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      final before = (await allOccurrences()).length;

      final nextDates = [
        DateTime.now().add(const Duration(days: RecurringSeries.horizonDays + 1)),
        DateTime.now().add(const Duration(days: RecurringSeries.horizonDays + 2)),
      ];
      await service.materializeOccurrences(
        templateId: written.templateId,
        template: template(),
        prototype: prototype(),
        dates: nextDates,
      );

      expect((await allOccurrences()).length, before + 2);
      final doc = await fake.collection('todos').doc(uid).collection('recurring').doc(written.templateId).get();
      expect(doc.data()!['lastMaterializedDate'], DateService().getString(nextDates.last));
    });

    test('an empty date list is a no-op', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      final before = (await allOccurrences()).length;
      final result = await service.materializeOccurrences(
        templateId: written.templateId,
        template: template(),
        prototype: prototype(),
        dates: const [],
      );
      expect(result.occurrences, isEmpty);
      expect((await allOccurrences()).length, before);
    });
  });

  group('seriesInstances', () {
    test('finds every occurrence of a series across date partitions', () async {
      final written = await service.createRecurringSeries(template(), prototype());
      final found = await service.seriesInstances(written.templateId);
      expect(found, isNotNull);
      expect(found!.length, written.occurrences.length);
    });

    test('does not return occurrences of another series', () async {
      final a = await service.createRecurringSeries(template(), prototype());
      await service.createRecurringSeries(template(), prototype());
      final found = await service.seriesInstances(a.templateId);
      expect(found!.every((t) => t.recurringTemplateId == a.templateId), isTrue);
    });
  });
}
