import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

class TaskItem extends StatelessWidget {
  final Task task;
  const TaskItem({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task.title,
                style: const TextStyle(fontSize: 20),
              ),
              if (task.description != null)
                Text(task.description!, style: const TextStyle(fontSize: 14)),
              Text(
                task.id ?? '',
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
              )
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Checkbox(
                  value: task.completed,
                  onChanged: (value) =>
                      TaskService().updateTaskByKey({"completed": value}, task.id!)),
              IconButton(
                  onPressed: () => TaskService().deleteTask(task.id!),
                  icon: const Icon(FontAwesomeIcons.trashCan))
            ],
          )
        ]));
  }
}
