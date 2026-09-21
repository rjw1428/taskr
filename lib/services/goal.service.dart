import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskr/services/goal_planning.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/services/firebase_refs.dart';

class GoalService with ChangeNotifier {
  // `late` so a test can inject a fake via [db] before the real instance is
  // touched (Firebase isn't initialized under `flutter test`).
  late FirebaseFirestore _db = FirebaseRefs.firestore;
  final _taskService = TaskService();

  @visibleForTesting
  set db(FirebaseFirestore db) {
    _db = db;
    // ignore: invalid_use_of_visible_for_testing_member
    _taskService.db = db; // keep the wrapped TaskService on the same fake
  }

  /// The model call, swappable so generation can be tested without the network.
  @visibleForTesting
  Future<List<Map<String, dynamic>>> Function(String prompt)? llm;

  /// Clock, swappable so week targeting and task lookups are deterministic.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// Mutable so a test can point the call at a local stub server.
  @visibleForTesting
  static String geminiEndpoint =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

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

  Future<void> pauseGoal(Goal goal) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');
    await _goalCollection(user.uid).doc(goal.id).update({
      'status': 'paused',
      'modifiedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> resumeGoal(Goal goal) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');
    await _goalCollection(user.uid).doc(goal.id).update({
      'status': 'active',
      'modifiedAt': DateTime.now().millisecondsSinceEpoch,
    });
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
    final prompt = GoalPlanning.buildPrompt(goal, generations);
    final call = llm ?? _callLLM;

    List<Map<String, dynamic>> taskData;
    try {
      taskData = await call(prompt);
    } catch (e) {
      debugPrint('First LLM attempt failed: $e. Retrying with stricter prompt.');
      try {
        taskData = await call('$prompt\n\nIMPORTANT: Return ONLY a valid JSON array. No markdown, no explanation.');
      } catch (e2) {
        debugPrint('Second LLM attempt failed: $e2');
        rethrow;
      }
    }

    final now = clock();
    final today = DateTime(now.year, now.month, now.day);
    final monday = GoalPlanning.targetMonday(now);
    final weekStart = DateService().getString(monday);
    final weekEnd = DateService().getString(monday.add(const Duration(days: 6)));

    if (isRegeneration) {
      await _deleteUncompletedGoalTasksForWeek(user.uid, goal.id!, weekStart, weekEnd);
    }

    final createdTasks = <Task>[];
    final taskIds = <String>[];

    for (final td in taskData) {
      final taskDate = GoalPlanning.dateForOffset(monday, (td['dayOffset'] as num?)?.toInt());
      if (taskDate.isBefore(today)) continue;

      final effort = GoalPlanning.parseEffort(td['effort'] as String?);
      final task = Task(
        added: now.millisecondsSinceEpoch,
        title: td['title'] as String? ?? 'Goal task',
        description: td['description'] as String?,
        priority: effort,
        completed: false,
        dueDate: DateService().getString(taskDate),
        goalId: goal.id,
        tags: [],
      );

      final taskId = await _taskService.addTask(task);
      taskIds.add(taskId);
      createdTasks.add(task.copyWith(id: taskId));
    }

    final generation = Generation(
      generatedAt: now.millisecondsSinceEpoch,
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

  /// Progress for a goal, counted from the tasks actually tagged to it rather
  /// than from a generation's derived `completedTaskIds` list. The old tally
  /// silently undercounted whenever a task's id changed (e.g. a push) or a
  /// completion happened outside the checkbox backfill. `weeksActive` still
  /// comes from the number of generations.
  ///
  /// The live count uses a collection-group query on `(userId, goalId)`; if that
  /// index is still building (or a task predates the `userId` stamp), it throws
  /// and we fall back to the generation-based tally so the page still renders.
  Future<Map<String, int>> getGoalStats(String goalId) async {
    final user = AuthService().user;
    final generations = await getGenerations(goalId);
    if (user != null) {
      try {
        final snap = await _db
            .collectionGroup('items')
            .where('userId', isEqualTo: user.uid)
            .where('goalId', isEqualTo: goalId)
            .get();
        final total = snap.size;
        final completed = snap.docs.where((d) => d.data()['completed'] == true).length;
        return {
          'totalTasks': total,
          'completedTasks': completed,
          'weeksActive': generations.length,
        };
      } catch (e) {
        debugPrint('getGoalStats live count failed, falling back to generations: $e');
      }
    }

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

  Future<List<Map<String, dynamic>>> _callLLM(String prompt) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    if (apiKey.isEmpty) throw Exception('GEMINI_API_KEY not set in .env');

    final url = Uri.parse('$geminiEndpoint?key=$apiKey');

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
    return GoalPlanning.parseTaskList(GoalPlanning.responseText(data));
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
    final now = clock();
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
