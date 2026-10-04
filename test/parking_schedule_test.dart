import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/parking_schedule.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

void main() {
  // reportError draws a snack, which needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  const today = '2026-10-02';

  Task train({String? id = 't1', String title = 'Work Train', String? start = '09:40', String? date = today}) =>
      Task(id: id, added: 1, title: title, startTime: start, dueDate: date);

  group('ParkingSchedule.shouldRequest', () {
    bool should(Task after, {Task? before}) => ParkingSchedule.shouldRequest(before: before, after: after, today: today);

    test("requests for a new timed Work Train dated today", () {
      expect(should(train()), isTrue);
    });

    test('requests when the departure is retimed', () {
      expect(should(train(start: '10:15'), before: train()), isTrue);
    });

    test('requests when an existing task is renamed to Work Train', () {
      expect(should(train(), before: train(title: 'Train')), isTrue);
    });

    test('requests when a start time is added', () {
      expect(should(train(), before: train(start: null)), isTrue);
    });

    test('requests when the task is moved to today', () {
      expect(should(train(), before: train(date: '2026-10-03')), isTrue);
    });

    test('skips an edit that leaves the departure alone', () {
      expect(should(train(), before: train()), isFalse);
    });

    test('skips other titles, including near misses the server would reject', () {
      expect(should(train(title: 'Gym')), isFalse);
      expect(should(train(title: 'work train')), isFalse);
    });

    test('skips untimed, undated-today and id-less tasks', () {
      expect(should(train(start: null)), isFalse);
      expect(should(train(start: '')), isFalse);
      expect(should(train(date: '2026-10-03')), isFalse);
      expect(should(train(date: null)), isFalse);
      expect(should(train(id: null)), isFalse);
    });
  });

  group('TaskService', () {
    late TestEnv env;
    late TaskService service;
    final todayStr = DateService().getString(DateTime.now());
    final tomorrowStr = DateService().getString(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day + 1));

    setUp(() async {
      env = await TestEnv.create();
      AuthService().user = MockUser(uid: env.uid);
      service = TaskService();
    });
    tearDown(() => env.dispose());

    Iterable<dynamic> parkingCalls() =>
        env.functionCalls.where((c) => c.name == 'scheduleParkingPromptForTask').map((c) => c.payload);

    Task task({String title = 'Work Train', String? start = '09:40', String? date}) =>
        Task(added: 1, title: title, startTime: start, dueDate: date ?? todayStr, completed: false, tags: const []);

    test('adding a Work Train for today asks the server to schedule the prompt', () async {
      final id = await service.addTask(task());
      expect(parkingCalls(), [
        {'taskId': id, 'taskDate': todayStr}
      ]);
    });

    test('adding any other task makes no call', () async {
      await service.addTask(task(title: 'Groceries'));
      await service.addTask(task(date: tomorrowStr));
      expect(parkingCalls(), isEmpty);
    });

    test('retiming a Work Train asks again; other edits do not', () async {
      final id = await service.addTask(task());
      final saved = task().copyWith(id: id);
      env.functionCalls.clear();

      await service.updateTask(id, saved.copyWith(description: 'bring umbrella'), saved);
      expect(parkingCalls(), isEmpty);

      await service.updateTask(id, saved.copyWith(startTime: '10:15'), saved);
      expect(parkingCalls(), [
        {'taskId': id, 'taskDate': todayStr}
      ]);
    });

    test("a recurring Work Train series asks only for today's occurrence", () async {
      final now = DateTime.now();
      final written = await service.createRecurringSeries(
        RecurringTask(
          recurrenceType: 'Daily',
          startDate: now,
          endDate: now.add(const Duration(days: 30)),
        ),
        task(),
      );
      final todays = written.occurrences.singleWhere((t) => t.dueDate == todayStr);
      expect(parkingCalls(), [
        {'taskId': todays.id, 'taskDate': todayStr}
      ]);
    });

    test('a failing call does not fail the save', () async {
      env.functions['scheduleParkingPromptForTask'] = (_) => throw Exception('offline');
      final id = await service.addTask(task());
      expect(id, isNotEmpty);
    });
  });
}
