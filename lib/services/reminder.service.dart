import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

class ReminderService {
  ReminderService._internal();
  static final _instance = ReminderService._internal();
  factory ReminderService() => _instance;

  final _functions = FirebaseFunctions.instance;
  final _taskService = TaskService();

  Future<void> scheduleReminder(Task task) async {
    if (task.reminderTime == null || task.id == null || task.dueDate == null) return;

    final callable = _functions.httpsCallable('scheduleReminder');
    final result = await callable.call<Map<String, dynamic>>({
      'taskId': task.id,
      'taskDate': task.dueDate,
      'reminderTime': task.reminderTime,
      'title': task.title,
    });

    final reminderTaskName = result.data['reminderTaskName'] as String;
    await _taskService.updateTaskByKey({'reminderTaskName': reminderTaskName}, task);
    debugPrint('Reminder scheduled: $reminderTaskName');
  }

  Future<void> cancelReminder(Task task) async {
    if (task.reminderTaskName == null) return;

    final callable = _functions.httpsCallable('cancelReminder');
    await callable.call({'reminderTaskName': task.reminderTaskName});
    await _taskService.updateTaskByKey({
      'reminderTaskName': null,
      'reminderTime': null,
    }, task);
    debugPrint('Reminder cancelled');
  }

  Future<void> updateReminder(Task task, String newTime) async {
    if (task.reminderTaskName != null) {
      final callable = _functions.httpsCallable('cancelReminder');
      await callable.call({'reminderTaskName': task.reminderTaskName});
    }

    await _taskService.updateTaskByKey({'reminderTime': newTime}, task);
    final updated = task.copyWith(reminderTime: newTime);
    await scheduleReminder(updated);
  }
}
