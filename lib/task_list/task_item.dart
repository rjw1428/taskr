import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/task_list/copy_task.dart';

class TaskItem extends StatelessWidget {
  final Task task;
  final int index;
  final Function onComplete;
  final bool isBacklog;
  const TaskItem(
      {super.key,
      required this.task,
      required this.index,
      required this.onComplete,
      required this.isBacklog});

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
                            onChanged: (value) async {
                              if (value!) {
                                confetti.play();
                                PerformanceService().incrementScore(AuthService().user!.uid,
                                    PerformanceService().getScore(task.priority));
                                onComplete(index);
                              } else {
                                PerformanceService().decrementScore(AuthService().user!.uid,
                                    PerformanceService().getScore(task.priority));
                              }
                              const completeTimeFormat =
                                  "${DateService.stringFmt} ${DateService.dbTimeFormat}";
                              await TaskService().updateTaskByKey({
                                "completed": value,
                                "completedTime":
                                    DateFormat(completeTimeFormat).format(DateTime.now())
                              }, task);
                              // TAGS HERE ARE NAME, NOT ID
                              await PerformanceService()
                                  .updateToday(AuthService().user!.uid, task, value);
                            }),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * .6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (timeFrame != '')
                                Text(timeFrame,
                                    style: const TextStyle(fontSize: 14, color: Colors.white)),
                              Text(
                                task.title,
                                style: const TextStyle(fontSize: 16, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (task.description != null)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      task.description!,
                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                    )),
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
                        )
                      ],
                    ),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      actionButtons(context, isBacklog),
                      ReorderableDragStartListener(
                        index: index,
                        child: IconButton(
                          icon: const Icon(FontAwesomeIcons.gripLines),
                          onPressed: () => print("HERE"),
                        ),
                      ),
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

  Widget actionButtons(BuildContext context, bool isBacklog) {
    return PopupMenuButton(
        onSelected: (value) {
          if (value == "PUSH") {
            TaskService().pushTask(task);
          } else if (value == "EDIT") {
            showDialog(
                context: context,
                builder: (BuildContext context) => AddTaskScreen(task: task, isBacklog: isBacklog));
          } else if (value == "REMOVE") {
            TaskService().deleteTask(task);
          } else if (value == "COPY") {
            showDialog(
                context: context, builder: (BuildContext context) => CopyTaskScreen(task: task));
          }
        },
        itemBuilder: (context) => [
              if (!isBacklog && !task.completed)
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
              const PopupMenuItem(
                  value: "COPY",
                  child: Row(
                    children: [
                      Icon(FontAwesomeIcons.copy),
                      Padding(padding: EdgeInsets.only(left: 8), child: Text('Copy'))
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
