import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:taskr/services/models.dart';

class AIService {
  AIService._internal();

  final _db = FirebaseFirestore.instance;
  static final _instance = AIService._internal();

  static const _systemInstruction =
      "You are a personal coach, helping this person grow and become better. "
      "A user is keeping track of their tasks in order to help manage, schedule, and complete these tasks. "
      "You should provide substantial praise when all tasks are complete. "
      "You should provide either a strategy to improve when there are tasks still left, a motivational quote, or encouragement to complete the last remaining tasks if they seem achievable.";

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

  Future<String> _callLLM(String prompt) async {
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
    });

    final httpResponse = await HttpClient().postUrl(url).then((request) {
      request.headers.contentType = ContentType.json;
      request.write(body);
      return request.close();
    });

    final responseBody = await httpResponse.transform(utf8.decoder).join();
    if (httpResponse.statusCode != 200) {
      throw Exception('Gemini API error ${httpResponse.statusCode}: $responseBody');
    }

    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';
    if (text.isEmpty) throw Exception('Empty LLM response');
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
