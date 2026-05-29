import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class GoalService with ChangeNotifier {
  final _db = FirebaseFirestore.instance;
  final _taskService = TaskService();

  static const _systemInstruction =
    "You are a personal development coach. Given a user's goal, generate a list of concrete, actionable tasks for the coming week. "
    "Each task should be specific and achievable in a single session. "
    "Return ONLY a JSON array of objects with these fields: "
    '"title" (string, concise task name), '
    '"description" (string, brief details on what to do), '
    '"dayOffset" (int, 0=Monday through 6=Sunday, which day of the week to schedule this task), '
    '"effort" (string, one of "low", "medium", "high"). '
    "Do not include any text outside the JSON array.";

  CollectionReference<Map<String, dynamic>> _goalCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('goals');
  }

  CollectionReference<Map<String, dynamic>> _generationCollection(String userId, String goalId) {
    return _db.collection('todos').doc(userId).collection('goals').doc(goalId).collection('generations');
  }

  // --- Goal CRUD ---

  Stream<List<Goal>> streamGoals() {
    final user = AuthService().user;
    if (user == null) return Stream.value([]);
    return _goalCollection(user.uid).snapshots().map((snapshot) {
      final goals = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return Goal.fromJson(data);
      }).toList();
      goals.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return goals;
    });
  }

  Future<Goal?> getGoal(String goalId) async {
    final user = AuthService().user;
    if (user == null) return null;
    final doc = await _goalCollection(user.uid).doc(goalId).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = doc.id;
    return Goal.fromJson(data);
  }

  Future<String> addGoal(Goal goal) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');
    final data = removeNulls(goal.toJson());
    data.remove('id');
    final ref = await _goalCollection(user.uid).add(data);
    return ref.id;
  }

  Future<void> updateGoal(Goal goal) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');
    final data = removeNulls(goal.toJson());
    data.remove('id');
    await _goalCollection(user.uid).doc(goal.id).update(data);
  }

  Future<void> deleteGoal(Goal goal) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');

    await _goalCollection(user.uid).doc(goal.id).update({'status': 'deleted'});
    await _deleteUncompletedGoalTasks(user.uid, goal.id!);
  }

  // --- Generation Records ---

  Future<void> addGeneration(String goalId, Generation generation) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');
    final data = generation.toJson();
    data.remove('id');
    await _generationCollection(user.uid, goalId).add(data);
  }

  Future<Generation?> getLatestGeneration(String goalId) async {
    final user = AuthService().user;
    if (user == null) return null;
    final snapshot = await _generationCollection(user.uid, goalId)
        .orderBy('generatedAt', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    final data = snapshot.docs.first.data();
    data['id'] = snapshot.docs.first.id;
    return Generation.fromJson(data);
  }

  Future<List<Generation>> getGenerations(String goalId) async {
    final user = AuthService().user;
    if (user == null) return [];
    final snapshot = await _generationCollection(user.uid, goalId)
        .orderBy('generatedAt', descending: true)
        .get();
    return snapshot.docs.map((doc) {
      final data = doc.data();
      data['id'] = doc.id;
      return Generation.fromJson(data);
    }).toList();
  }

  Future<void> updateGenerationCompletedTask(String goalId, String generationId, String taskId) async {
    final user = AuthService().user;
    if (user == null) return;
    await _generationCollection(user.uid, goalId).doc(generationId).update({
      'completedTaskIds': FieldValue.arrayUnion([taskId]),
    });
  }

  Future<void> submitTaskFeedback(Task task, String feedback) async {
    final user = AuthService().user;
    if (user == null || task.goalId == null || task.id == null) return;

    final date = task.dueDate ?? 'unassigned';
    await _db.collection('todos').doc(user.uid)
        .collection('tasks').doc(date)
        .collection('items').doc(task.id)
        .update({'feedback': feedback});

    final generations = await getGenerations(task.goalId!);
    for (final gen in generations) {
      if (gen.taskIds.contains(task.id)) {
        await _generationCollection(user.uid, task.goalId!).doc(gen.id).update({
          'taskFeedback.${task.id}': feedback,
        });
        break;
      }
    }
  }

  // --- Task Generation ---

  Future<List<Task>> generateTasksForGoal(Goal goal, {bool isRegeneration = false}) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');

    final generations = await getGenerations(goal.id!);
    final prompt = _buildPrompt(goal, generations);

    List<Map<String, dynamic>> taskData;
    try {
      taskData = await _callLLM(prompt);
    } catch (e) {
      debugPrint('First LLM attempt failed: $e. Retrying with stricter prompt.');
      try {
        taskData = await _callLLM('$prompt\n\nIMPORTANT: Return ONLY a valid JSON array. No markdown, no explanation.');
      } catch (e2) {
        debugPrint('Second LLM attempt failed: $e2');
        rethrow;
      }
    }

    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekStart = DateService().getString(monday);
    final weekEnd = DateService().getString(monday.add(const Duration(days: 6)));

    if (isRegeneration) {
      await _deleteUncompletedGoalTasksForWeek(user.uid, goal.id!, weekStart, weekEnd);
    }

    final createdTasks = <Task>[];
    final taskIds = <String>[];

    for (final td in taskData) {
      final dayOffset = (td['dayOffset'] as num?)?.toInt() ?? 0;
      final taskDate = monday.add(Duration(days: dayOffset.clamp(0, 6)));
      if (taskDate.isBefore(DateTime(now.year, now.month, now.day))) continue;

      final effort = _parseEffort(td['effort'] as String?);
      final task = Task(
        added: DateTime.now().millisecondsSinceEpoch,
        title: td['title'] as String? ?? 'Goal task',
        description: td['description'] as String?,
        priority: effort,
        completed: false,
        dueDate: DateService().getString(taskDate),
        goalId: goal.id,
        tags: [],
        subtasks: [],
      );

      final taskId = await _taskService.addTask(task);
      taskIds.add(taskId);
      createdTasks.add(task.copyWith(id: taskId));
    }

    final generation = Generation(
      generatedAt: DateTime.now().millisecondsSinceEpoch,
      weekStart: weekStart,
      weekEnd: weekEnd,
      taskIds: taskIds,
      prompt: prompt,
      response: jsonEncode(taskData),
    );
    await addGeneration(goal.id!, generation);

    return createdTasks;
  }

  // --- Goal Task Queries ---

  Future<Map<String, int>> getGoalStats(String goalId) async {
    final generations = await getGenerations(goalId);
    int totalTasks = 0;
    int completedTasks = 0;
    for (final gen in generations) {
      totalTasks += gen.taskIds.length;
      completedTasks += gen.completedTaskIds.length;
    }
    return {
      'totalTasks': totalTasks,
      'completedTasks': completedTasks,
      'weeksActive': generations.length,
    };
  }

  // --- Private Helpers ---

  String _buildPrompt(Goal goal, List<Generation> generations) {
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

  Future<List<Map<String, dynamic>>> _callLLM(String prompt) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) throw Exception('GEMINI_API_KEY not set in .env');

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey',
    );

    final body = jsonEncode({
      'system_instruction': {
        'parts': [{'text': _systemInstruction}],
      },
      'contents': [
        {'role': 'user', 'parts': [{'text': prompt}]},
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
      },
    });

    final httpResponse = await HttpClient()
        .postUrl(url)
        .then((request) {
          request.headers.contentType = ContentType.json;
          request.write(body);
          return request.close();
        });

    final responseBody = await httpResponse.transform(utf8.decoder).join();
    if (httpResponse.statusCode != 200) {
      throw Exception('Gemini API error ${httpResponse.statusCode}: $responseBody');
    }

    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    var text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
    if (text.isEmpty) throw Exception('Empty LLM response');

    text = text.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'\n?```$'), '');
    }

    final parsed = jsonDecode(text);
    if (parsed is! List) throw Exception('LLM response is not a JSON array');
    return parsed.map((e) => e as Map<String, dynamic>).toList();
  }

  Effort _parseEffort(String? effort) {
    switch (effort?.toLowerCase()) {
      case 'high':
        return Effort.high;
      case 'medium':
        return Effort.medium;
      default:
        return Effort.low;
    }
  }

  Future<void> _deleteUncompletedGoalTasks(String userId, String goalId) async {
    final generations = await getGenerations(goalId);
    for (final gen in generations) {
      for (final taskId in gen.taskIds) {
        if (gen.completedTaskIds.contains(taskId)) continue;
        await _tryDeleteTask(userId, taskId);
      }
    }
  }

  Future<void> _deleteUncompletedGoalTasksForWeek(
      String userId, String goalId, String weekStart, String weekEnd) async {
    final latestGen = await getLatestGeneration(goalId);
    if (latestGen == null) return;
    for (final taskId in latestGen.taskIds) {
      if (latestGen.completedTaskIds.contains(taskId)) continue;
      await _tryDeleteTask(userId, taskId);
    }
  }

  Future<void> _tryDeleteTask(String userId, String taskId) async {
    final now = DateTime.now();
    const daysToCheck = 14;

    for (int i = -7; i < daysToCheck; i++) {
      final date = DateService().getString(now.add(Duration(days: i)));
      try {
        final doc = await _db
            .collection('todos')
            .doc(userId)
            .collection('tasks')
            .doc(date)
            .collection('items')
            .doc(taskId)
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          if (data['completed'] == true) return;
          await doc.reference.delete();
          await _db.collection('todos').doc(userId).collection('tasks').doc(date).update({
            'taskOrder': FieldValue.arrayRemove([taskId]),
          });
          return;
        }
      } catch (e) {
        debugPrint('Error checking task $taskId on $date: $e');
      }
    }
  }
}
