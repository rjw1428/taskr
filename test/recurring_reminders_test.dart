import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fake;
  late TaskService tasks;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    PerformanceService().db = fake;
    tasks = TaskService()..db = fake;
  });

  Task occurrence({String? reminderTime, String? reminderTaskName}) => Task(
        id: 'x',
        added: 1,
        title: 'standup',
        priority: Effort.medium,
        completed: false,
        reminderTime: reminderTime,
        reminderTaskName: reminderTaskName,
        tags: const [],
      );

  String inDays(int days) => DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();

  group('enqueueDueReminders selection', () {
    // scheduleReminder cannot reach Cloud Functions in a unit test, so the
    // deferred count is what these assert: which occurrences the pass *chose*.
    test('skips occurrences with no reminder', () async {
      final deferred = await ReminderService().enqueueDueReminders([occurrence()]);
      expect(deferred, 0);
    });

    test('skips occurrences already scheduled', () async {
      final deferred = await ReminderService().enqueueDueReminders([
        occurrence(reminderTime: inDays(1), reminderTaskName: 'queues/x/tasks/y'),
      ]);
      expect(deferred, 0);
    });

    test('defers nothing when the batch fits under the cap', () async {
      final due = List.generate(
        RecurringSeries.reminderEnqueueCapPerPass,
        (i) => occurrence(reminderTime: inDays(i + 1)),
      );
      expect(await ReminderService().enqueueDueReminders(due), 0);
    });

    test('defers the overflow past the per-pass cap', () async {
      final due = List.generate(
        RecurringSeries.reminderEnqueueCapPerPass + 5,
        (i) => occurrence(reminderTime: inDays(i + 1)),
      );
      // Exactly the overflow, so a caller with user context can say scheduling
      // is still in progress.
      expect(await ReminderService().enqueueDueReminders(due), 5);
    });

    test('occurrences beyond the Cloud Tasks ceiling are not counted as deferred', () async {
      // They are not enqueue work yet — they simply aren't in range.
      final due = List.generate(20, (i) => occurrence(reminderTime: inDays(31 + i)));
      expect(await ReminderService().enqueueDueReminders(due), 0);
    });

    test('past-due reminders are ignored', () async {
      final due = [occurrence(reminderTime: inDays(-1))];
      expect(await ReminderService().enqueueDueReminders(due), 0);
    });

    test('a mixed series only counts the in-window overflow', () async {
      final due = [
        ...List.generate(RecurringSeries.reminderEnqueueCapPerPass + 3, (i) => occurrence(reminderTime: inDays(i + 1))),
        ...List.generate(10, (i) => occurrence(reminderTime: inDays(40 + i))),
        occurrence(),
      ];
      expect(await ReminderService().enqueueDueReminders(due), 3);
    });
  });

  group('seriesInstances degradation', () {
    test('returns null when the collection-group query is unavailable', () async {
      // No authenticated user is the one failure mode reachable without a real
      // backend; the failed-precondition path returns null the same way.
      AuthService().user = null;
      expect(await tasks.seriesInstances('abc'), isNull);
    });

    test('a null result leaves delete-series working via the per-date fallback', () async {
      final template = RecurringTask(
        recurrenceType: 'Daily',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 3)),
      );
      final written = await tasks.createRecurringSeries(
        template,
        Task(added: 1, title: 'standup', priority: Effort.medium, completed: false, tags: const []),
      );
      expect(written.occurrences, isNotEmpty);

      // Exercise the degraded path directly.
      await tasks.deleteRecurringTemplate(
        written.occurrences.first.copyWith(recurringTemplateId: written.templateId),
        template,
      );

      final dates = await fake.collection('todos').doc(uid).collection('tasks').get();
      var remaining = 0;
      for (final d in dates.docs) {
        final items =
            await fake.collection('todos').doc(uid).collection('tasks').doc(d.id).collection('items').get();
        remaining += items.size;
      }
      expect(remaining, 0);
    });
  });

  group('pushTask reminder re-derivation', () {
    Future<String> seedSeries({String? reminder}) async {
      final written = await tasks.createRecurringSeries(
        RecurringTask(
          recurrenceType: 'Daily',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 10)),
          reminderTimeOfDay: reminder,
        ),
        Task(added: 1, title: 'standup', priority: Effort.medium, completed: false, tags: const []),
      );
      return written.templateId;
    }

    // A non-today occurrence: pushing today's also decrements the day's score,
    // which is unrelated to reminder re-derivation and needs a perf doc.
    final futureDate = DateService().getString(DateTime.now().add(const Duration(days: 3)));

    Future<Task?> reload(String date, String id) async {
      final doc =
          await fake.collection('todos').doc(uid).collection('tasks').doc(date).collection('items').doc(id).get();
      if (!doc.exists) return null;
      return Task.fromJson({...doc.data()!, 'id': doc.id, 'tags': <dynamic>[]});
    }

    test('a series reminder follows the task to its new date', () async {
      final templateId = await seedSeries(reminder: '08:30');
      final instances = await tasks.seriesInstances(templateId);
      final target = instances!.firstWhere((t) => t.dueDate == futureDate);

      // pushTask mutates the task in place, so capture the next day up front.
      final newDate = DateService().incrementDate(DateService().getDate(target.dueDate!));
      await tasks.pushTask(target);
      final moved = await reload(newDate, target.id!);
      expect(moved, isNotNull);
      final local = DateTime.parse(moved!.reminderTime!).toLocal();
      expect(local.hour, 8);
      expect(local.minute, 30);
      expect(DateService().getString(local), newDate);
    });

    test('a series with no reminder time clears the reminder as before', () async {
      final templateId = await seedSeries();
      final instances = await tasks.seriesInstances(templateId);
      final target = instances!.firstWhere((t) => t.dueDate == futureDate);

      // pushTask mutates the task in place, so capture the next day up front.
      final newDate = DateService().incrementDate(DateService().getDate(target.dueDate!));
      await tasks.pushTask(target);
      final moved = await reload(newDate, target.id!);
      expect(moved!.reminderTime, isNull);
    });

    test('a one-off task clears the reminder as before', () async {
      final id = await tasks.addTask(Task(
        added: 1,
        title: 'one-off',
        dueDate: futureDate,
        priority: Effort.medium,
        reminderTime: inDays(1),
        tags: const [],
      ));
      final task = (await reload(futureDate, id))!;

      final newDate = DateService().incrementDate(DateService().getDate(futureDate));
      await tasks.pushTask(task);
      final moved = await reload(newDate, id);
      expect(moved!.reminderTime, isNull);
    });

    test('an occurrence whose template is gone still pushes, without a reminder', () async {
      final templateId = await seedSeries(reminder: '08:30');
      final instances = await tasks.seriesInstances(templateId);
      final target = instances!.firstWhere((t) => t.dueDate == futureDate);

      // Orphan the occurrence — a state the app already tolerates.
      await fake.collection('todos').doc(uid).collection('recurring').doc(templateId).delete();

      // pushTask mutates the task in place, so capture the next day up front.
      final newDate = DateService().incrementDate(DateService().getDate(target.dueDate!));
      await tasks.pushTask(target);
      final moved = await reload(newDate, target.id!);
      expect(moved, isNotNull);
      expect(moved!.reminderTime, isNull);
    });
  });
}
