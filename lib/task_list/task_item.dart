import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

class TaskItem extends StatelessWidget {
  final Task task;
  const TaskItem({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          // color: const Color.fromARGB(255, 18, 18, 18),
          color: priorityColors[task.priority],
          border: Border.all(color: Colors.black45),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Colors.black45, offset: Offset(2.0, 4.0), blurRadius: 5.0)
          ],
        ),
        margin: const EdgeInsets.all(10),
        child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Checkbox(
                        value: task.completed,
                        onChanged: (value) {
                          TaskService().updateTaskByKey({"completed": value}, task.id!);
                          value!
                              ? ScoreService().incrementScore(AuthService().user!.uid)
                              : ScoreService().decrementScore(AuthService().user!.uid);
                        }),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(fontSize: 20, color: Colors.white),
                      ),
                      if (task.description != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(task.description!,
                                style: const TextStyle(fontSize: 14, color: Colors.white))),
                      if (task.tags.isNotEmpty)
                        Wrap(
                            spacing: 10,
                            children: task.tags
                                .map((tag) => Chip(
                                        label: Text(
                                      tag,
                                      style: const TextStyle(fontSize: 10),
                                    )))
                                .toList()),
                    ],
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                      onPressed: () => TaskService().deleteTask(task.id!),
                      icon: const Icon(FontAwesomeIcons.trashCan))
                ],
              )
            ])));
  }
}
