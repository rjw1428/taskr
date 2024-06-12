import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/task_list/task_item.dart';

import '../shared/shared.dart';

class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
        stream: TaskService().streamTasks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen();
          }
          if (snapshot.hasError) {
            return Center(child: ErrorMessage(message: snapshot.error.toString()));
          }
          if (!snapshot.hasData) {
            return const Center(child: ErrorMessage(message: "No Data"));
          }
          var tasks = snapshot.data!;
          return Scaffold(
              appBar: AppBar(
                title: const Text('Taskr'),
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tasks.map((task) => TaskItem(task: task)).toList(),
              ),
              floatingActionButton: FloatingActionButton(
                  child: const Icon(FontAwesomeIcons.plus, size: 20),
                  onPressed: () => showDialog(
                      context: context, builder: (BuildContext context) => const AddTaskScreen())));
        });
  }
}
