import 'dart:convert';

import 'package:taskr/services/models.dart';
import 'package:taskr/shared/constants.dart';

/// Pure planning logic behind [GoalService.generateTasksForGoal]: which week to
/// target, how to turn the model's reply into task rows, and the prompt itself.
/// Nothing here touches Firebase, the clock or the network, so it is unit
/// testable without fakes.
class GoalPlanning {
  GoalPlanning._();

  // If fewer than this many days remain in the current week (including today),
  // generate tasks for next week instead. Otherwise a goal created late in the
  // week has most of its days already in the past, and those tasks get dropped.
  static const minDaysForCurrentWeek = 3;

  /// The Monday whose week new goal tasks should land in. Rolls forward to next
  /// week when little of the current one is left, so mid/late-week goal creation
  /// doesn't silently drop most of its tasks.
  static DateTime targetMonday(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    // Monday of the current week (weekday: Mon=1 .. Sun=7).
    var monday = today.subtract(Duration(days: now.weekday - 1));
    final daysLeftInWeek = 7 - (now.weekday - 1); // includes today
    if (daysLeftInWeek < minDaysForCurrentWeek) {
      monday = monday.add(const Duration(days: 7));
    }
    return monday;
  }

  /// Date a task with [dayOffset] (0=Monday .. 6=Sunday) lands on. Out-of-range
  /// offsets are clamped rather than rejected so a slightly-off model reply still
  /// produces a usable week.
  static DateTime dateForOffset(DateTime monday, int? dayOffset) {
    return monday.add(Duration(days: (dayOffset ?? 0).clamp(0, 6)));
  }

  static Effort parseEffort(String? effort) {
    switch (effort?.toLowerCase()) {
      case 'high':
        return Effort.high;
      case 'medium':
        return Effort.medium;
      default:
        return Effort.low;
    }
  }

  /// Turns the model's text reply into task rows. Tolerates a markdown code
  /// fence around the JSON; throws on anything that isn't a JSON array.
  static List<Map<String, dynamic>> parseTaskList(String text) {
    var body = text.trim();
    if (body.isEmpty) throw Exception('Empty LLM response');
    if (body.startsWith('```')) {
      body = body.replaceAll(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'\n?```$'), '');
    }
    final parsed = jsonDecode(body);
    if (parsed is! List) throw Exception('LLM response is not a JSON array');
    return parsed.map((e) => e as Map<String, dynamic>).toList();
  }

  /// Pulls the reply text out of a Gemini generateContent response body.
  static String responseText(Map<String, dynamic> data) {
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) return '';
    final parts = candidates.first?['content']?['parts'];
    if (parts is! List || parts.isEmpty) return '';
    return parts.first?['text'] as String? ?? '';
  }

  static String buildPrompt(Goal goal, List<Generation> generations) {
    final buffer = StringBuffer();
    buffer.writeln('Goal: ${goal.title}');
    if (goal.description != null && goal.description!.isNotEmpty) {
      buffer.writeln('Description: ${goal.description}');
    }
    buffer.writeln('Timeframe: ${goal.timeframeLabel}');
    buffer.writeln('Frequency: ${goal.frequencyLabel}');

    final weekNumber = generations.length + 1;
    buffer.writeln('This is week $weekNumber of the goal.');

    if (generations.isNotEmpty) {
      buffer.writeln('\nHistory of previous weeks:');
      final recentGens = generations.take(3);
      for (final gen in recentGens) {
        buffer.writeln('  Week ${gen.weekStart} to ${gen.weekEnd}:');
        buffer.writeln('    Tasks generated: ${gen.taskIds.length}');
        buffer.writeln('    Completed: ${gen.completedTaskIds.length}');
        buffer.writeln('    Skipped: ${gen.skippedTaskIds.length}');
        if (gen.response.isNotEmpty) {
          try {
            final tasks = jsonDecode(gen.response) as List;
            final completedTitles = <String>[];
            final skippedTitles = <String>[];
            for (int i = 0; i < tasks.length; i++) {
              final title = tasks[i]['title'] as String? ?? '';
              if (gen.completedTaskIds.length > i) {
                completedTitles.add(title);
              } else {
                skippedTitles.add(title);
              }
            }
            if (completedTitles.isNotEmpty) {
              buffer.writeln('    Completed tasks: ${completedTitles.join(", ")}');
            }
            if (skippedTitles.isNotEmpty) {
              buffer.writeln('    Skipped tasks: ${skippedTitles.join(", ")}');
            }
          } catch (_) {}
        }
        if (gen.taskFeedback.isNotEmpty && gen.response.isNotEmpty) {
          try {
            final tasks = jsonDecode(gen.response) as List;
            buffer.writeln('    User feedback:');
            for (final entry in gen.taskFeedback.entries) {
              final taskIndex = gen.taskIds.indexOf(entry.key);
              final title = taskIndex >= 0 && taskIndex < tasks.length
                  ? tasks[taskIndex]['title'] as String? ?? 'Task'
                  : 'Task';
              buffer.writeln('      "$title": ${entry.value}');
            }
          } catch (_) {}
        }
      }

      if (generations.length > 3) {
        final older = generations.skip(3);
        int olderTotal = 0;
        int olderCompleted = 0;
        for (final gen in older) {
          olderTotal += gen.taskIds.length;
          olderCompleted += gen.completedTaskIds.length;
        }
        buffer.writeln('  Older weeks (${older.length} weeks): $olderCompleted/$olderTotal tasks completed');
      }
    }

    if (goal.frequency == GoalFrequency.daily) {
      buffer.writeln('\nGenerate 7 tasks, one for each day of the week (dayOffset 0-6).');
    } else if (goal.frequency == GoalFrequency.nTimesWeek && goal.frequencyCount != null) {
      buffer.writeln('\nGenerate ${goal.frequencyCount} tasks, spread across the week.');
    } else {
      buffer.writeln('\nDecide the best number and distribution of tasks for this week.');
    }

    buffer.writeln('Build on prior progress. Do not repeat completed tasks. Adapt if tasks were skipped.');
    buffer.writeln('Incorporate user feedback when provided — adjust difficulty, relevance, and task types accordingly.');
    return buffer.toString();
  }
}
