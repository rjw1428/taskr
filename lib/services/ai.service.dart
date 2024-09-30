// import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:taskr/services/models.dart';

class AIService {
  AIService._internal();

  final _db = FirebaseFirestore.instance;
  static final _instance = AIService._internal();

  static final systemInstruction = Content.system(
      "You are a personal coach, helping this person grow and become better. "
      "A user is keeping track of there tasks in order to help manage, schedule, and complete these tasks"
      "You should provide substantial praise when all tasks are complete."
      "You should provide either a strategy to improve when there are tasks still left, a motivational quote, or encouragement to complete the last remaining tasks if they seem achievable.");

  final model = FirebaseVertexAI.instance
      .generativeModel(model: 'gemini-1.5-flash', systemInstruction: systemInstruction);

  factory AIService() {
    return _instance;
  }

  CollectionReference<Map<String, dynamic>> feedbackCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('coaching');
  }

  Future<String> giveFeedback(List<Task> tasks) async {
    final completed = tasks.where((tsk) => tsk.completed).map((tsk) =>
        "${tsk.title} - ${tsk.description} relating to my ${tsk.tags.map((t) => t.label).join(",")}");
    final incompleted = tasks.where((tsk) => !tsk.completed).map((tsk) =>
        "${tsk.title} - ${tsk.description} relating to my ${tsk.tags.map((t) => t.label).join(",")}");
    final prompt = [
      Content.text('I completed the following tasks today: $completed'),
      if (incompleted.length > 0)
        Content.text('I was unable to do the following tasks today: $completed')
      else
        Content.text("I completed all my tasks today!")
    ];

    print(prompt.map((e) => e.toString()));

    try {
      final response = await model.generateContent(prompt);
      print(response.text);
      if (response.text == null) {
        throw Error();
      }
      return response.text!;
    } catch (err) {
      return "Good Job!!! Nothing for you today...";
    }
  }

  Future<void> storeFeedback(String userId, String date, String feedback) {
    return feedbackCollection(userId).doc(date).set({feedback: feedback});
  }

  Future<String> getFeedback(String userId, String date) async {
    final response = await feedbackCollection(userId).doc(date).get();
    return response.data()!['feedback'];
  }
}
