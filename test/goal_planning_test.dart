import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/goal_planning.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/constants.dart';

void main() {
  Goal goal({GoalFrequency frequency = GoalFrequency.auto, int? count, String? description}) => Goal(
        id: 'g1',
        title: 'Run more',
        description: description,
        timeframe: GoalTimeframe.oneMonth,
        frequency: frequency,
        frequencyCount: count,
        startDate: '2026-09-01',
        endDate: '2026-10-01',
        createdAt: 1,
        modifiedAt: 1,
      );

  Generation gen({
    List<String> taskIds = const ['a', 'b', 'c'],
    List<String> completed = const [],
    String response = '[{"title":"T1"},{"title":"T2"},{"title":"T3"}]',
    Map<String, String> feedback = const {},
  }) =>
      Generation(
        generatedAt: 1,
        weekStart: '2026-09-07',
        weekEnd: '2026-09-13',
        taskIds: taskIds,
        completedTaskIds: completed,
        prompt: '',
        response: response,
        taskFeedback: feedback,
      );

  group('targetMonday', () {
    // 2026-09-14 is a Monday.
    test('early in the week targets the current Monday', () {
      expect(GoalPlanning.targetMonday(DateTime(2026, 9, 14, 15)), DateTime(2026, 9, 14)); // Mon
      expect(GoalPlanning.targetMonday(DateTime(2026, 9, 16)), DateTime(2026, 9, 14)); // Wed
      expect(GoalPlanning.targetMonday(DateTime(2026, 9, 18)), DateTime(2026, 9, 14)); // Fri: 3 days left
    });

    test('with fewer than three days left, rolls to next Monday', () {
      expect(GoalPlanning.targetMonday(DateTime(2026, 9, 19)), DateTime(2026, 9, 21)); // Sat
      expect(GoalPlanning.targetMonday(DateTime(2026, 9, 20, 23, 59)), DateTime(2026, 9, 21)); // Sun
    });

    test('strips the time of day', () {
      expect(GoalPlanning.targetMonday(DateTime(2026, 9, 15, 23, 59, 59)), DateTime(2026, 9, 14));
    });
  });

  group('dateForOffset', () {
    final monday = DateTime(2026, 9, 14);
    test('maps 0..6 onto the week', () {
      expect(GoalPlanning.dateForOffset(monday, 0), monday);
      expect(GoalPlanning.dateForOffset(monday, 6), DateTime(2026, 9, 20));
    });
    test('clamps out-of-range offsets and defaults null to Monday', () {
      expect(GoalPlanning.dateForOffset(monday, 9), DateTime(2026, 9, 20));
      expect(GoalPlanning.dateForOffset(monday, -2), monday);
      expect(GoalPlanning.dateForOffset(monday, null), monday);
    });
  });

  group('parseEffort', () {
    test('is case-insensitive and defaults to low', () {
      expect(GoalPlanning.parseEffort('HIGH'), Effort.high);
      expect(GoalPlanning.parseEffort('Medium'), Effort.medium);
      expect(GoalPlanning.parseEffort('low'), Effort.low);
      expect(GoalPlanning.parseEffort('extreme'), Effort.low);
      expect(GoalPlanning.parseEffort(null), Effort.low);
    });
  });

  group('parseTaskList', () {
    test('parses a bare JSON array', () {
      final rows = GoalPlanning.parseTaskList('[{"title":"a","dayOffset":1}]');
      expect(rows, [
        {'title': 'a', 'dayOffset': 1}
      ]);
    });

    test('strips a markdown code fence', () {
      final rows = GoalPlanning.parseTaskList('```json\n[{"title":"a"}]\n```');
      expect(rows.single['title'], 'a');
    });

    test('rejects empty text and non-array JSON', () {
      expect(() => GoalPlanning.parseTaskList('   '), throwsException);
      expect(() => GoalPlanning.parseTaskList('{"title":"a"}'), throwsException);
      expect(() => GoalPlanning.parseTaskList('not json'), throwsFormatException);
    });
  });

  group('responseText', () {
    test('digs the first candidate text out of a Gemini body', () {
      final body = {
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': 'hello'}
              ]
            }
          }
        ]
      };
      expect(GoalPlanning.responseText(body), 'hello');
    });
    test('is empty when the shape is missing', () {
      expect(GoalPlanning.responseText({}), '');
      expect(GoalPlanning.responseText({'candidates': []}), '');
      expect(GoalPlanning.responseText({'candidates': [{}]}), '');
      expect(GoalPlanning.responseText({'candidates': [{'content': {'parts': 'nope'}}]}), '');
      expect(GoalPlanning.responseText({'candidates': [{'content': {'parts': []}}]}), '');
    });
  });

  group('buildPrompt', () {
    test('first week has no history and asks for an auto plan', () {
      final p = GoalPlanning.buildPrompt(goal(description: 'because'), []);
      expect(p, contains('Goal: Run more'));
      expect(p, contains('Description: because'));
      expect(p, contains('Timeframe: 1 Month'));
      expect(p, contains('This is week 1 of the goal.'));
      expect(p, isNot(contains('History')));
      expect(p, contains('Decide the best number and distribution'));
    });

    test('omits an empty description', () {
      expect(GoalPlanning.buildPrompt(goal(description: ''), []), isNot(contains('Description:')));
    });

    test('daily and n-times frequencies set the task count', () {
      expect(GoalPlanning.buildPrompt(goal(frequency: GoalFrequency.daily), []),
          contains('Generate 7 tasks, one for each day of the week (dayOffset 0-6).'));
      expect(GoalPlanning.buildPrompt(goal(frequency: GoalFrequency.nTimesWeek, count: 3), []),
          contains('Generate 3 tasks, spread across the week.'));
    });

    test('n-times without a count, or a count on another frequency, falls back to auto', () {
      expect(GoalPlanning.buildPrompt(goal(frequency: GoalFrequency.nTimesWeek), []),
          contains('Decide the best number and distribution'));
      expect(GoalPlanning.buildPrompt(goal(frequency: GoalFrequency.auto, count: 3), []),
          contains('Decide the best number and distribution'));
    });

    test('history lists completed and skipped titles from the stored response', () {
      final p = GoalPlanning.buildPrompt(goal(), [gen(completed: ['a'])]);
      expect(p, contains('This is week 2 of the goal.'));
      expect(p, contains('History of previous weeks:'));
      expect(p, contains('Week 2026-09-07 to 2026-09-13:'));
      expect(p, contains('Tasks generated: 3'));
      expect(p, contains('Completed: 1'));
      expect(p, contains('Skipped: 0'));
      expect(p, contains('Completed tasks: T1'));
      expect(p, contains('Skipped tasks: T2, T3'));
      expect(p, isNot(contains('User feedback:')), reason: 'no feedback given');
    });

    test('feedback is keyed back to the task title by id position', () {
      final p = GoalPlanning.buildPrompt(
          goal(), [gen(feedback: {'a': 'nice', 'b': 'too hard', 'zzz': 'orphan'})]);
      expect(p, contains('User feedback:'));
      expect(p, contains('"T1": nice'));
      expect(p, contains('"T2": too hard'));
      expect(p, contains('"Task": orphan'));
    });

    test('every prompt ends with the standing instructions', () {
      for (final gens in [<Generation>[], [gen()]]) {
        final p = GoalPlanning.buildPrompt(goal(), gens);
        expect(p, contains('Build on prior progress. Do not repeat completed tasks.'));
        expect(p, contains('Incorporate user feedback when provided'));
      }
    });

    test('a corrupt stored response does not break the prompt', () {
      final p = GoalPlanning.buildPrompt(goal(), [gen(response: '{oops', feedback: {'a': 'x'})]);
      expect(p, contains('Tasks generated: 3'));
      expect(p, isNot(contains('Completed tasks:')));
    });

    test('only the three most recent weeks are itemised; older ones are summed', () {
      final gens = [
        gen(),
        gen(),
        gen(),
        gen(completed: ['a', 'b']),
        gen(completed: ['a']),
      ];
      final p = GoalPlanning.buildPrompt(goal(), gens);
      expect('Week 2026-09-07'.allMatches(p).length, 3);
      expect(p, contains('Older weeks (2 weeks): 3/6 tasks completed'));
    });
  });
}
