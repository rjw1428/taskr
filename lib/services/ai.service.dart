import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/firebase_refs.dart';

class AIService {
  AIService._internal();

  late FirebaseFirestore _db = FirebaseRefs.firestore;

  @visibleForTesting
  set db(FirebaseFirestore db) => _db = db;
  static AIService _instance = AIService._internal();

  /// Drops all state so the next `AIService()` starts fresh.
  @visibleForTesting
  static void resetInstance() => _instance = AIService._internal();

  factory AIService() {
    return _instance;
  }

  CollectionReference<Map<String, dynamic>> feedbackCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('feedback');
  }

  setEndOfDayNotification(List<Task> tasks) {
    // DateTime now = DateTime.now();
    // DateTime coachingNotificationTime = DateTime(now.year, now.month, now.day, 22, 0, 0);
    // DateTime coachingNotificationTime = now.add(const Duration(seconds: 5));
    // Duration delay = coachingNotificationTime.difference(now);
    // timer = Timer(delay, () async {
    //   final response = await AIService().giveFeedback(tasks);
    //   showDialog(
    //       context: context, builder: (BuildContext context) => CoachingDialog(response: response));
    // });
  }

  Future<String> giveFeedback(List<Task> tasks) async {
    final completed = tasks
        .where((tsk) => tsk.completed)
        .map((tsk) => "${tsk.title} - ${tsk.description} relating to my ${tsk.tags.map((t) => t.label).join(",")}")
        .toList();
    final incompleted = tasks
        .where((tsk) => !tsk.completed)
        .map((tsk) => "${tsk.title} - ${tsk.description} relating to my ${tsk.tags.map((t) => t.label).join(",")}")
        .toList();

    final userMessage = StringBuffer()
      ..writeln('I completed the following tasks today: ${completed.join("; ")}');
    if (incompleted.isNotEmpty) {
      userMessage.writeln('I was unable to do the following tasks today: ${incompleted.join("; ")}');
    } else {
      userMessage.writeln('I completed all my tasks today!');
    }

    try {
      final text = await _callLLM(userMessage.toString());
      debugPrint(text);
      return text;
    } catch (err) {
      debugPrint('AIService.giveFeedback error: $err');
      return "Good Job!!! Nothing for you today...";
    }
  }

  /// Asks the `callGemini` callable for coaching feedback. The API key and the
  /// system instruction live server-side; see firebase/functions/src/gemini.logic.ts.
  Future<String> _callLLM(String prompt) async {
    final result = await FirebaseRefs.callFunction('callGemini', {'kind': 'coach', 'prompt': prompt});
    final text = (result is Map ? result['text'] : null) as String? ?? '';
    if (text.trim().isEmpty) throw Exception('Empty LLM response');
    return text.trim();
  }

  Future<void> storeFeedback(String userId, String date, String feedback) {
    return feedbackCollection(userId).doc(date).set({feedback: feedback});
  }

  Future<String> getFeedback(String userId, String date) async {
    final response = await feedbackCollection(userId).doc(date).get();
    return response.data()!['feedback'];
  }
}
