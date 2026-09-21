import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  group('JournalEntry', () {
    test('hasData needs at least one non-empty field', () {
      expect(JournalEntry(date: '2026-01-01').hasData, isFalse);
      expect(JournalEntry(date: '2026-01-01', thinking: '').hasData, isFalse);
      expect(JournalEntry(date: '2026-01-01', thinking: 'a').hasData, isTrue);
      expect(JournalEntry(date: '2026-01-01', feeling: 'b').hasData, isTrue);
      expect(JournalEntry(date: '2026-01-01', gratitude: 'c').hasData, isTrue);
    });

    test('round-trips through json', () {
      final e = JournalEntry(id: 'j', date: '2026-01-01', thinking: 't', feeling: 'f', gratitude: 'g');
      final back = JournalEntry.fromJson(e.toJson());
      expect(back.id, 'j');
      expect(back.gratitude, 'g');
    });
  });

  group('HealthEntry', () {
    test('hasData looks at the headline metrics', () {
      expect(HealthEntry(date: 'd').hasData, isFalse);
      expect(HealthEntry(date: 'd', sleepScore: 80).hasData, isFalse);
      expect(HealthEntry(date: 'd', sleepSeconds: 1).hasData, isTrue);
      expect(HealthEntry(date: 'd', steps: 1).hasData, isTrue);
      expect(HealthEntry(date: 'd', stressAvg: 1).hasData, isTrue);
      expect(HealthEntry(date: 'd', bodyBatteryHigh: 1).hasData, isTrue);
    });

    test('round-trips through json', () {
      final e = HealthEntry(
        id: 'h',
        date: 'd',
        sleepScore: 1,
        sleepSeconds: 2,
        deepSeconds: 3,
        lightSeconds: 4,
        remSeconds: 5,
        awakeSeconds: 6,
        bodyBatteryHigh: 7,
        bodyBatteryLow: 8,
        bodyBatteryCharged: 9,
        bodyBatteryDrained: 10,
        stressAvg: 11,
        stressMax: 12,
        steps: 13,
        floorsClimbed: 14,
        activeCalories: 15,
        restingHeartRate: 16,
      );
      final back = HealthEntry.fromJson(e.toJson());
      expect(back.restingHeartRate, 16);
      expect(back.deepSeconds, 3);
    });
  });

  group('Goal', () {
    Goal goal({GoalTimeframe tf = GoalTimeframe.oneWeek, GoalFrequency f = GoalFrequency.daily, int? count}) => Goal(
          title: 'Run',
          timeframe: tf,
          frequency: f,
          frequencyCount: count,
          startDate: '2026-01-31',
          endDate: '2026-02-07',
          createdAt: 1,
          modifiedAt: 2,
        );

    test('computeEndDate for every timeframe', () {
      expect(Goal.computeEndDate('2026-01-31', GoalTimeframe.oneWeek), '2026-02-07');
      expect(Goal.computeEndDate('2026-01-31', GoalTimeframe.oneMonth), '2026-03-03');
      expect(Goal.computeEndDate('2026-01-15', GoalTimeframe.threeMonths), '2026-04-15');
      expect(Goal.computeEndDate('2026-01-15', GoalTimeframe.sixMonths), '2026-07-15');
      expect(Goal.computeEndDate('2026-01-15', GoalTimeframe.oneYear), '2027-01-15');
    });

    test('labels', () {
      expect(goal(tf: GoalTimeframe.oneWeek).timeframeLabel, '1 Week');
      expect(goal(tf: GoalTimeframe.oneMonth).timeframeLabel, '1 Month');
      expect(goal(tf: GoalTimeframe.threeMonths).timeframeLabel, '3 Months');
      expect(goal(tf: GoalTimeframe.sixMonths).timeframeLabel, '6 Months');
      expect(goal(tf: GoalTimeframe.oneYear).timeframeLabel, '1 Year');
      expect(goal(f: GoalFrequency.daily).frequencyLabel, 'Daily');
      expect(goal(f: GoalFrequency.nTimesWeek, count: 3).frequencyLabel, '3x / week');
      expect(goal(f: GoalFrequency.auto).frequencyLabel, 'Auto');
    });

    test('copyWith overrides only what is given', () {
      final g = goal();
      final c = g.copyWith(id: 'g1', title: 'Swim', status: GoalStatus.paused, description: 'd');
      expect(c.id, 'g1');
      expect(c.title, 'Swim');
      expect(c.status, GoalStatus.paused);
      expect(c.description, 'd');
      expect(c.startDate, g.startDate);
      expect(c.createdAt, 1);
      final same = g.copyWith();
      expect(same.title, 'Run');
      expect(same.status, GoalStatus.active);
    });

    test('round-trips through json', () {
      final back = Goal.fromJson(goal(tf: GoalTimeframe.threeMonths, f: GoalFrequency.nTimesWeek, count: 2).toJson());
      expect(back.timeframe, GoalTimeframe.threeMonths);
      expect(back.frequency, GoalFrequency.nTimesWeek);
      expect(back.frequencyCount, 2);
    });
  });

  test('Generation round-trips through json', () {
    final g = Generation(
      id: 'gen',
      generatedAt: 5,
      weekStart: 'a',
      weekEnd: 'b',
      taskIds: const ['t1'],
      prompt: 'p',
      response: 'r',
      completedTaskIds: const ['t1'],
      skippedTaskIds: const [],
      taskFeedback: const {'t1': 'nice'},
    );
    final back = Generation.fromJson(g.toJson());
    expect(back.taskIds, ['t1']);
    expect(back.taskFeedback, {'t1': 'nice'});
  });

  test('Accomplishment round-trips through json', () {
    final back = Accomplishment.fromJson(Accomplishment(id: 'a', title: 'Ran', date: 'd', difficultyScore: 3).toJson());
    expect(back.difficultyScore, 3);
    expect(Accomplishment(title: 'x', date: 'd').difficultyScore, 1);
  });

  group('Task', () {
    test('kind getters', () {
      final t = Task(added: 1, title: 'x');
      expect(t.isDivider, isFalse);
      expect(t.isMultiDay, isFalse);
      expect(t.isSubtask, isFalse);
      expect(t.isParent, isFalse);
      expect(Task(added: 1, title: 'x', type: 'divider').isDivider, isTrue);
      final md = Task(added: 1, title: 'x', multiDayGroupId: 'g', multiDayPosition: 'start');
      expect(md.isMultiDay, isTrue);
      expect(md.isMultiDayStart, isTrue);
      expect(md.isMultiDayEnd, isFalse);
      expect(md.isMultiDayMiddle, isFalse);
      expect(Task(added: 1, title: 'x', multiDayPosition: 'end').isMultiDayEnd, isTrue);
      expect(Task(added: 1, title: 'x', multiDayPosition: 'middle').isMultiDayMiddle, isTrue);
      expect(Task(added: 1, title: 'x', parentId: 'p').isSubtask, isTrue);
      expect(Task(added: 1, title: 'x', childCount: 2).isParent, isTrue);
    });

    test('toDbTask flattens tags to ids', () {
      final t = Task(added: 1, title: 'x', tags: [Tag(id: 'a', label: 'A'), Tag(id: 'b', label: 'B')]);
      expect(t.toDbTask()['tags'], ['a', 'b']);
      expect(t.toJson()['tags'].first, isA<Tag>());
    });

    test('copyWith overrides every field it is given and keeps the rest', () {
      final t = Task(added: 1, title: 'x', dueDate: '2026-01-01', priority: Effort.high, countdown: true);
      final c = t.copyWith(
        id: 'i',
        added: 2,
        modified: 'm',
        title: 'y',
        description: 'd',
        completed: true,
        type: 'divider',
        tags: [Tag(id: 't', label: 'T')],
        dueDate: '2026-02-02',
        startTime: '09:00',
        endTime: '10:00',
        completedTime: 'ct',
        parentId: 'p',
        parentTitle: 'pt',
        userId: 'u',
        habitId: 'h',
        childCount: 3,
        childCompletedCount: 1,
        priority: Effort.info,
        pushCount: 4,
        countdown: false,
        countdownLabel: 'cl',
        recurringTemplateId: 'r',
        goalId: 'g',
        calendarEventId: 'c',
        feedback: 'f',
        multiDayGroupId: 'mg',
        multiDayPosition: 'end',
        reminderTime: 'rt',
        reminderTaskName: 'rn',
      );
      expect(c.id, 'i');
      expect(c.added, 2);
      expect(c.modified, 'm');
      expect(c.title, 'y');
      expect(c.description, 'd');
      expect(c.completed, isTrue);
      expect(c.type, 'divider');
      expect(c.tags.single.id, 't');
      expect(c.dueDate, '2026-02-02');
      expect(c.startTime, '09:00');
      expect(c.endTime, '10:00');
      expect(c.parentId, 'p');
      expect(c.parentTitle, 'pt');
      expect(c.userId, 'u');
      expect(c.habitId, 'h');
      expect(c.childCount, 3);
      expect(c.childCompletedCount, 1);
      expect(c.priority, Effort.info);
      expect(c.pushCount, 4);
      expect(c.countdown, isFalse);
      expect(c.countdownLabel, 'cl');
      expect(c.recurringTemplateId, 'r');
      expect(c.goalId, 'g');
      expect(c.calendarEventId, 'c');
      expect(c.feedback, 'f');
      expect(c.multiDayGroupId, 'mg');
      expect(c.multiDayPosition, 'end');
      expect(c.reminderTime, 'rt');
      expect(c.reminderTaskName, 'rn');

      final same = t.copyWith();
      expect(same.title, 'x');
      expect(same.priority, Effort.high);
      expect(same.countdown, isTrue);
    });

    test('fromJson applies defaults', () {
      final t = Task.fromJson({'title': 'x'});
      expect(t.priority, Effort.low);
      expect(t.completed, isFalse);
      expect(t.tags, isEmpty);
      expect(t.type, 'task');
      final full = Task.fromJson({
        'title': 'x',
        'priority': 'medium',
        'completedTime': 'ct',
        'tags': [
          {'id': 'a', 'label': 'A', 'deleted': true, 'archived': true}
        ],
      });
      expect(full.priority, Effort.medium);
      expect(full.completedTime, 'ct');
      expect(full.tags.single.deleted, isTrue);
    });
  });

  test('Tag round-trips through json', () {
    final back = Tag.fromJson(Tag(id: 'a', label: 'A', archived: true).toJson());
    expect(back.archived, isTrue);
    expect(back.deleted, isFalse);
  });

  group('RecurringTask', () {
    test('copyWith keeps the id and overrides fields', () {
      final r = RecurringTask(recurrenceType: 'Daily', startDate: DateTime.utc(2026, 1, 1))..id = 'r1';
      final c = r.copyWith(recurrenceType: 'Weekly', frequency: 2, daysOfWeek: {'Mo': true}, dayOfMonth: 3);
      expect(c.id, 'r1');
      expect(c.recurrenceType, 'Weekly');
      expect(c.frequency, 2);
      expect(c.startDate, DateTime.utc(2026, 1, 1));
      final other = r.copyWith(
        id: 'r2',
        startDate: DateTime.utc(2026, 2, 1),
        endDate: DateTime.utc(2026, 3, 1),
        lastMaterializedDate: '2026-02-10',
        reminderTimeOfDay: '08:00',
      );
      expect(other.id, 'r2');
      expect(other.endDate, DateTime.utc(2026, 3, 1));
      expect(other.lastMaterializedDate, '2026-02-10');
      expect(other.reminderTimeOfDay, '08:00');
    });

    test('round-trips through json', () {
      final r = RecurringTask(
        recurrenceType: 'Weekly',
        daysOfWeek: {'Mo': true, 'Tu': false},
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 6, 1),
        reminderTimeOfDay: '07:15',
      )..id = 'r';
      final back = RecurringTask.fromJson(r.toJson());
      expect(back.id, 'r');
      expect(back.daysOfWeek, {'Mo': true, 'Tu': false});
      expect(back.endDate, DateTime.utc(2026, 6, 1));
      expect(RecurringTask.fromJson({'recurrenceType': 'Daily'}).frequency, 1);
    });
  });

  test('Person, Kid and ConversationLog round-trip through json', () {
    final p = Person(
      id: 'p',
      name: 'Sam',
      age: 40,
      birthday: 'b',
      job: 'j',
      spouse: 's',
      kids: [Kid(name: 'K', age: 3, birthday: 'kb', dateAdded: 'd')],
      logs: [ConversationLog(id: 'l', date: 'd', entry: 'e', createdAt: 1, updatedAt: 2)],
      createdAt: 1,
      lastUpdated: 2,
    );
    final json = p.toJson();
    expect(json['kids'].first, isA<Map<String, dynamic>>());
    final back = Person.fromJson(json);
    expect(back.kids.single.name, 'K');
    expect(back.logs.single.entry, 'e');
    expect(Person(name: 'x').kids, isEmpty);
  });

  test('Habit round-trips through json with defaults', () {
    final back = Habit.fromJson(Habit(
      id: 'h',
      title: 'Stretch',
      effort: Effort.medium,
      recurrenceType: 'Weekly',
      frequency: 2,
      daysOfWeek: const {'Mo': true},
      dayOfMonth: 1,
      startDate: '2026-01-01',
      reminderTime: '08:00',
      status: 'paused',
      currentStreak: 2,
      longestStreak: 5,
      lastCompletedDate: '2026-01-02',
      lastMaterializedDate: '2026-01-03',
      createdAt: 1,
      modifiedAt: 2,
    ).toJson());
    expect(back.effort, Effort.medium);
    expect(back.status, 'paused');
    expect(back.longestStreak, 5);
    final defaults = Habit(title: 'x', startDate: 'd');
    expect(defaults.effort, Effort.low);
    expect(defaults.recurrenceType, 'Daily');
    expect(defaults.status, 'active');
  });

  test('AppNotification round-trips through json', () {
    final back = AppNotification.fromJson(
        AppNotification(id: 'n', title: 't', body: 'b', data: const {'k': 'v'}, type: 'x', sentAt: 9, read: true)
            .toJson());
    expect(back.data, {'k': 'v'});
    expect(back.read, isTrue);
    expect(AppNotification(title: 't', body: 'b', sentAt: 1).read, isFalse);
  });
}
