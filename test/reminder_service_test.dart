import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/error_reporting.dart';

import 'helpers/harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late TaskService tasks;
  late ReminderService reminders;

  setUp(() async {
    env = await TestEnv.create();
    tasks = TaskService();
    reminders = ReminderService();
    env.functions['scheduleReminder'] = (payload) => {'reminderTaskName': 'queues/q/tasks/${payload['taskId']}'};
    env.functions['cancelReminder'] = (_) => null;
  });
  tearDown(() => env.dispose());

  String inDays(int days) => DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();

  Future<Task> seed({String? reminderTime, String? reminderTaskName, String? date = '2027-05-30'}) async {
    final task = Task(
      added: 1,
      title: 'standup',
      dueDate: date,
      reminderTime: reminderTime,
      reminderTaskName: reminderTaskName,
    );
    final id = await tasks.addTask(task);
    return task.copyWith(id: id);
  }

  Future<Map<String, dynamic>> stored(Task t) async =>
      (await tasks.taskCollection(env.uid, t.dueDate ?? TaskService.defaultUnassignedDate).doc(t.id).get()).data()!;

  Iterable<String> calls() => env.functionCalls.map((c) => c.name);

  group('scheduleReminder', () {
    test('hands an in-window reminder to Cloud Tasks and stores its name', () async {
      final task = await seed(reminderTime: inDays(2));
      await reminders.scheduleReminder(task);
      expect(env.functionCalls.single.name, 'scheduleReminder');
      expect(env.functionCalls.single.payload, {
        'taskId': task.id,
        'taskDate': '2027-05-30',
        'reminderTime': task.reminderTime,
        'title': 'standup',
      });
      expect((await stored(task))['reminderTaskName'], 'queues/q/tasks/${task.id}');
    });

    test('a backlog task is scheduled under the unassigned date', () async {
      final task = await seed(reminderTime: inDays(2), date: null);
      await reminders.scheduleReminder(task);
      expect(env.functionCalls.single.payload['taskDate'], TaskService.defaultUnassignedDate);
    });

    test('does nothing without a reminder or an id', () async {
      await reminders.scheduleReminder(await seed());
      await reminders.scheduleReminder(Task(added: 1, title: 'x', reminderTime: inDays(1)));
      expect(calls(), isEmpty);
    });

    test('defers a reminder outside the enqueue window', () async {
      final task = await seed(reminderTime: inDays(RecurringSeries.reminderEnqueueWindowDays + 2));
      await reminders.scheduleReminder(task);
      expect(calls(), isEmpty);
      expect((await stored(task)).containsKey('reminderTaskName'), isFalse);
    });
  });

  group('cancelReminder', () {
    test('cancels the Cloud Task and clears both fields', () async {
      final task = await seed(reminderTime: inDays(2), reminderTaskName: 'queues/q/tasks/old');
      await reminders.cancelReminder(task);
      expect(env.functionCalls.single.name, 'cancelReminder');
      expect(env.functionCalls.single.payload, {'reminderTaskName': 'queues/q/tasks/old'});
      final row = await stored(task);
      expect(row['reminderTaskName'], isNull);
      expect(row['reminderTime'], isNull);
    });

    test('is a no-op when nothing was scheduled', () async {
      await reminders.cancelReminder(await seed(reminderTime: inDays(2)));
      expect(calls(), isEmpty);
    });
  });

  group('updateReminder', () {
    test('cancels the old task, stores the new time and reschedules', () async {
      final task = await seed(reminderTime: inDays(2), reminderTaskName: 'queues/q/tasks/old');
      final newTime = inDays(3);
      await reminders.updateReminder(task, newTime);
      expect(calls(), ['cancelReminder', 'scheduleReminder']);
      final row = await stored(task);
      expect(row['reminderTime'], newTime);
      expect(row['reminderTaskName'], 'queues/q/tasks/${task.id}');
    });

    test('with nothing scheduled yet it only schedules', () async {
      final task = await seed();
      await reminders.updateReminder(task, inDays(3));
      expect(calls(), ['scheduleReminder']);
    });

    test('a new time outside the window leaves no stale task name behind', () async {
      final task = await seed(reminderTime: inDays(2), reminderTaskName: 'queues/q/tasks/old');
      await reminders.updateReminder(task, inDays(RecurringSeries.reminderEnqueueWindowDays + 5));
      expect(calls(), ['cancelReminder']);
      expect((await stored(task))['reminderTaskName'], isNull);
    });
  });

  group('enqueueDueReminders', () {
    test('schedules what is due and reports the overflow', () async {
      final due = [
        for (var i = 0; i < RecurringSeries.reminderEnqueueCapPerPass + 2; i++) await seed(reminderTime: inDays(i + 1)),
      ];
      final deferred = await reminders.enqueueDueReminders(due);
      expect(deferred, 2);
      expect(calls().where((c) => c == 'scheduleReminder'), hasLength(RecurringSeries.reminderEnqueueCapPerPass));
    });

    test('a scheduling failure is reported and leaves the task retryable', () async {
      env.functions['scheduleReminder'] = (_) => throw Exception('down');
      final task = await seed(reminderTime: inDays(1));
      expect(await reminders.enqueueDueReminders([task]), 0);
      expect(await reminders.enqueueDueReminders([task], reportFailures: false), 0);
      expect((await stored(task)).containsKey('reminderTaskName'), isFalse);
    });

    testWidgets('a scheduling failure is shown to the user only when asked for', (tester) async {
      resetErrorSnackDedupe();
      await pumpApp(tester, const SizedBox(), wrapInScaffold: true);
      env.functions['scheduleReminder'] = (_) => throw Exception('down');
      final task = await seed(reminderTime: inDays(1));

      await reminders.enqueueDueReminders([task], reportFailures: false);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing, reason: 'background passes stay silent');

      await reminders.enqueueDueReminders([task]);
      await tester.pump();
      expect(find.textContaining("Couldn't schedule a reminder"), findsOneWidget);
    });

    test('honours an explicit now', () async {
      final task = await seed(reminderTime: inDays(1));
      final deferred = await reminders.enqueueDueReminders([task], now: DateTime.now().add(const Duration(days: 5)));
      expect(deferred, 0);
      expect(calls(), isEmpty);
    });
  });

  group('topUpPendingReminders', () {
    test('does nothing when nothing is pending', () async {
      await reminders.topUpPendingReminders();
      expect(calls(), isEmpty);
    });

    test('schedules pending reminders that came into range', () async {
      final a = await seed(reminderTime: inDays(3));
      await seed(reminderTime: inDays(3), reminderTaskName: 'queues/q/tasks/done');
      await reminders.topUpPendingReminders();
      expect(calls(), ['scheduleReminder']);
      expect((await stored(a))['reminderTaskName'], 'queues/q/tasks/${a.id}');
    });

    test('reports what the per-pass cap deferred', () async {
      for (var i = 0; i < RecurringSeries.reminderEnqueueCapPerPass + 1; i++) {
        await seed(reminderTime: inDays(i + 1));
      }
      await reminders.topUpPendingReminders();
      expect(calls().where((c) => c == 'scheduleReminder'), hasLength(RecurringSeries.reminderEnqueueCapPerPass));
    });
  });
}
