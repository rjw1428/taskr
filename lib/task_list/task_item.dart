import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/goals/goal_detail_page.dart';
import 'package:taskr/services/goal.service.dart';
import 'package:taskr/task_list/copy_task.dart';
import 'package:taskr/task_list/task_feedback_dialog.dart';
import 'package:taskr/task_list/view_series.dart';

class TaskItem extends StatefulWidget {
  final Task task;
  final int index;
  final Function onComplete;
  final bool isBacklog;
  final Function(Task) onDelete;
  final TaskService taskService;
  const TaskItem(
      {super.key,
      required this.task,
      required this.index,
      required this.onComplete,
      required this.isBacklog,
      required this.taskService,
      required this.onDelete});

  @override
  TaskItemState createState() => TaskItemState();
}

class TaskItemState extends State<TaskItem> {
  bool expanded = false;
  bool isExpandable = false;
  bool _calendarConnected = false;
  bool _sendingToCalendar = false;
  StreamSubscription<bool>? _calendarSub;

  TaskItemState();

  @override
  void initState() {
    super.initState();
    final user = AuthService().user;
    if (user != null) {
      _calendarSub = CalendarService().watchConnected(user.uid).listen((connected) {
        if (mounted) setState(() => _calendarConnected = connected);
      });
    }
  }

  @override
  void dispose() {
    _calendarSub?.cancel();
    super.dispose();
  }

  Future<void> _sendToCalendar() async {
    if (_sendingToCalendar) return;
    setState(() => _sendingToCalendar = true);
    try {
      await CalendarService().sendTaskToCalendar(widget.task);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent to Google Calendar')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingToCalendar = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final confetti = ConfettiController(duration: const Duration(seconds: 1));
    final timeFrame = DateService().timeFrameBuilder(widget.task);

    isExpandable = widget.task.description != null || widget.task.tags.isNotEmpty;

    const double r = 10;
    BorderRadius borderRadius;
    if (widget.task.isMultiDayStart) {
      borderRadius = const BorderRadius.only(
        topLeft: Radius.circular(r),
        bottomLeft: Radius.circular(r),
      );
    } else if (widget.task.isMultiDayEnd) {
      borderRadius = const BorderRadius.only(
        topRight: Radius.circular(r),
        bottomRight: Radius.circular(r),
      );
    } else if (widget.task.isMultiDayMiddle) {
      borderRadius = BorderRadius.zero;
    } else {
      borderRadius = BorderRadius.circular(r);
    }

    return Stack(children: [
      Container(
          decoration: BoxDecoration(
            color: priorityColors[widget.task.priority]!.withAlpha(widget.task.completed ? 128 : 255),
            border: Border.all(color: Colors.black45),
            borderRadius: borderRadius,
            boxShadow: const [BoxShadow(color: Colors.black45, offset: Offset(2.0, 4.0), blurRadius: 5.0)],
          ),
          margin: const EdgeInsets.all(4),
          child: Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => expanded = !expanded);
                    debugPrint("${widget.task.title}: $expanded");
                  },
                  child: Row(
                      // TASK
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                                value: widget.task.completed,
                                onChanged: (value) async {
                                  if (value!) {
                                    confetti.play();
                                    PerformanceService().incrementScore(
                                        AuthService().user!.uid, PerformanceService().getScore(widget.task.priority));
                                    widget.onComplete(widget.index);
                                  } else {
                                    PerformanceService().decrementScore(
                                        AuthService().user!.uid, PerformanceService().getScore(widget.task.priority));
                                  }
                                  const completeTimeFormat = "${DateService.stringFmt} ${DateService.dbTimeFormat}";
                                  // TAGS HERE ARE NAME, NOT ID
                                  await widget.taskService.updateTaskByKey({
                                    "completed": value,
                                    "completedTime": DateFormat(completeTimeFormat).format(DateTime.now())
                                  }, widget.task);
                                  if (value && widget.task.goalId != null && widget.task.id != null) {
                                    _backfillGoalGeneration(widget.task);
                                  }
                                }),
                            if (widget.task.pushCount > 0)
                              Text('(${widget.task.pushCount}) ',
                                  style: const TextStyle(fontSize: 18, color: Colors.white)),
                            SizedBox(
                              width: MediaQuery.of(context).size.width * .6 - (widget.task.pushCount > 0 ? 20 : 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.max,
                                children: [
                                  if (widget.task.goalId != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: Row(
                                        children: [
                                          const Icon(FontAwesomeIcons.bullseye, size: 10, color: Colors.orange),
                                          const SizedBox(width: 4),
                                          Text('Goal', style: TextStyle(fontSize: 10, color: Colors.orange.shade300)),
                                        ],
                                      ),
                                    ),
                                  if (timeFrame != '')
                                    Text(timeFrame, style: const TextStyle(fontSize: 14, color: Colors.white)),
                                  Row(children: [
                                    Flexible(
                                        // width: MediaQuery.of(context).size.width * .5,
                                        child: SelectableText(
                                      widget.task.title,
                                      style: const TextStyle(
                                          fontSize: 16, color: Colors.white, overflow: TextOverflow.ellipsis),
                                    )),
                                    if (isExpandable && !expanded)
                                      const Padding(
                                          padding: EdgeInsets.only(left: 8),
                                          child: Icon(
                                            FontAwesomeIcons.solidCircle,
                                            size: 4,
                                          ))
                                  ]),
                                  if (widget.task.description != null && expanded)
                                    Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: SelectableText(
                                          widget.task.description!,
                                          style: const TextStyle(fontSize: 12, color: Colors.white),
                                        )),
                                  if (widget.task.tags.isNotEmpty && expanded)
                                    Wrap(
                                        spacing: 4,
                                        children: widget.task.tags
                                            .map((tag) => Chip(
                                                labelPadding: const EdgeInsets.all(0),
                                                label: Text(
                                                  tag.label,
                                                  style: const TextStyle(fontSize: 10),
                                                )))
                                            .toList()),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          actionButtons(context, widget.isBacklog),
                          ReorderableDragStartListener(
                            index: widget.index,
                            child: IconButton(
                              icon: const Icon(FontAwesomeIcons.gripLines),
                              onPressed: () => debugPrint("HERE"),
                            ),
                          ),
                        ])
                      ])))),
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

  Future<void> _backfillGoalGeneration(Task task) async {
    try {
      final goalService = GoalService();
      final generations = await goalService.getGenerations(task.goalId!);
      for (final gen in generations) {
        if (gen.taskIds.contains(task.id)) {
          await goalService.updateGenerationCompletedTask(task.goalId!, gen.id!, task.id!);
          break;
        }
      }
    } catch (e) {
      debugPrint('Error backfilling goal generation: $e');
    }
  }

  Widget actionButtons(BuildContext context, bool isBacklog) {
    return PopupMenuButton(
        onSelected: (value) async {
          if (value == "PUSH") {
            widget.taskService.pushTask(widget.task);
          } else if (value == "EDIT") {
            showModalBottomSheet(
                useSafeArea: true,
                isScrollControlled: true,
                context: context,
                builder: (BuildContext context) => AddTaskScreen(task: widget.task, isBacklog: isBacklog));
          } else if (value == "REMOVE") {
            widget.onDelete(widget.task);
          } else if (value == "COPY") {
            showDialog(context: context, builder: (BuildContext context) => CopyTaskScreen(task: widget.task));
          } else if (value == "CHECK_TIME") {
            final data = ["userId", AuthService().user!.uid];
            widget.taskService.callRemoteMethod("trainScheduleTest", data);
          } else if (value == "VIEW_SERIES") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ViewSeries(task: widget.task),
              ),
            );
          } else if (value == "VIEW_GOAL") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GoalDetailPage(goalId: widget.task.goalId!),
              ),
            );
          } else if (value == "FEEDBACK") {
            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => TaskFeedbackDialog(existingFeedback: widget.task.feedback),
            );
            if (result != null && result.isNotEmpty && context.mounted) {
              await GoalService().submitTaskFeedback(widget.task, result);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Feedback saved')),
                );
              }
            }
          } else if (value == "SEND_TO_CALENDAR") {
            _sendToCalendar();
          }
        },
        itemBuilder: (context) => [
              if (!isBacklog && !widget.task.completed)
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
              if (widget.task.recurringTemplateId != null) ...[
                const PopupMenuItem(
                    value: "VIEW_SERIES",
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.eye),
                        Padding(padding: EdgeInsets.only(left: 8), child: Text('View Series'))
                      ],
                    )),
              ],
              if (widget.task.goalId != null) ...[
                const PopupMenuItem(
                    value: "VIEW_GOAL",
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.bullseye, color: Colors.orange),
                        Padding(padding: EdgeInsets.only(left: 8), child: Text('View Goal'))
                      ],
                    )),
                PopupMenuItem(
                    value: "FEEDBACK",
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.comment, color: widget.task.feedback != null ? Colors.orange : null),
                        Padding(padding: const EdgeInsets.only(left: 8), child: Text(widget.task.feedback != null ? 'Update Feedback' : 'Feedback'))
                      ],
                    )),
              ],
              if (_calendarConnected && widget.task.dueDate != null)
                PopupMenuItem(
                    value: "SEND_TO_CALENDAR",
                    child: Row(
                      children: [
                        const Icon(FontAwesomeIcons.calendarPlus),
                        Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(widget.task.calendarEventId != null
                                ? 'Update on Calendar'
                                : 'Send to Calendar')),
                      ],
                    )),
              if (!isBacklog)
                const PopupMenuItem(
                    value: "COPY",
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.copy),
                        Padding(padding: EdgeInsets.only(left: 8), child: Text('Copy'))
                      ],
                    )),
              const PopupMenuItem(
                  value: "REMOVE",
                  child: Row(
                    children: [
                      Icon(FontAwesomeIcons.trashCan),
                      Padding(padding: EdgeInsets.only(left: 8), child: Text('Remove'))
                    ],
                  )),
              if ((widget.task.title.trim().toLowerCase() == 'work train' ||
                      widget.task.title.trim().toLowerCase() == 'train home') &&
                  !widget.task.completed &&
                  !isBacklog &&
                  widget.task.startTime != null &&
                  DateService().isToday(widget.task.dueDate!))
                const PopupMenuItem(
                    value: "CHECK_TIME",
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.trainSubway),
                        Padding(padding: EdgeInsets.only(left: 8), child: Text('Check Status'))
                      ],
                    )),
            ]);
  }
}
