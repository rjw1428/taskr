import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/task_list/add_task.dart';

class TaskItem extends StatelessWidget {
  final Task task;
  final int index;
  const TaskItem({super.key, required this.task, required this.index});

  @override
  Widget build(BuildContext context) {
    final confetti = ConfettiController(duration: const Duration(seconds: 1));
    final timeFrame = DateService().timeFrameBuilder(task);

    return Stack(children: [
      Container(
          // width: MediaQuery.of(context).size.width * .7,
          decoration: BoxDecoration(
            color: priorityColors[task.priority]!.withOpacity(task.completed ? 0.5 : 1),
            border: Border.all(color: Colors.black45),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Colors.black45, offset: Offset(2.0, 4.0), blurRadius: 5.0)
            ],
          ),
          margin: const EdgeInsets.all(4),
          child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: Row(
                  // TASK
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                            value: task.completed,
                            onChanged: (value) {
                              if (value!) {
                                confetti.play();
                                ScoreService().incrementScore(AuthService().user!.uid);
                              } else {
                                ScoreService().decrementScore(AuthService().user!.uid);
                              }
                              TaskService().updateTaskByKey({"completed": value}, task);
                            }),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (timeFrame != '')
                                  Text(timeFrame,
                                      style: const TextStyle(fontSize: 14, color: Colors.white)),
                              ],
                            ),
                            Text(
                              task.title,
                              style: const TextStyle(fontSize: 16, color: Colors.white),
                            ),
                            if (task.description != null)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(task.description!,
                                      style: const TextStyle(fontSize: 12, color: Colors.white))),
                            if (task.tags.isNotEmpty)
                              Wrap(
                                  spacing: 10,
                                  children: task.tags
                                      .map((tag) => Chip(
                                          labelPadding: const EdgeInsets.all(0),
                                          label: Text(
                                            tag,
                                            style: const TextStyle(fontSize: 10),
                                          )))
                                      .toList()),
                          ],
                        ),
                      ],
                    ),
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      ReorderableDragStartListener(
                        index: index,
                        child: IconButton(
                          icon: const Icon(FontAwesomeIcons.gripLines),
                          onPressed: () => print("HERE"),
                        ),
                      ),
                      actionButtons(context),
                    ])
                  ]))),
      Center(
        child: ConfettiWidget(
          maximumSize: const Size(20, 10),
          minimumSize: const Size(10, 5),
          confettiController: confetti,
          blastDirectionality: BlastDirectionality.explosive,
          maxBlastForce: 50,
          minBlastForce: 5,
          emissionFrequency: 0.03,
          numberOfParticles: 10,
          gravity: .7,
        ),
      )
    ]);
  }

  Widget actionButtons(BuildContext context) {
    return PopupMenuButton(
        onSelected: (value) {
          if (value == "PUSH") {
            TaskService().pushTask(task);
          } else if (value == "EDIT") {
            showDialog(
                context: context, builder: (BuildContext context) => AddTaskScreen(task: task));
          } else if (value == "REMOVE") {
            TaskService().deleteTask(task);
          }
        },
        itemBuilder: (context) => [
              const PopupMenuItem(
                  value: "PUSH",
                  child: Row(
                    children: [
                      Icon(FontAwesomeIcons.arrowRightToBracket),
                      Padding(padding: EdgeInsets.only(left: 8), child: Text('Push'))
                    ],
                  )),

              const PopupMenuItem(
                  value: "EDIT",
                  child: Row(
                    children: [
                      Icon(FontAwesomeIcons.penToSquare),
                      Padding(padding: EdgeInsets.only(left: 8), child: Text('Edit'))
                    ],
                  )),
              // // ON PUSH TASK
              const PopupMenuItem(
                  value: "REMOVE",
                  child: Row(
                    children: [
                      Icon(FontAwesomeIcons.trashCan),
                      Padding(padding: EdgeInsets.only(left: 8), child: Text('Remove'))
                    ],
                  ))
            ]);
  }
}
