import 'dart:async';

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/goals/goal_detail_page.dart';
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
  late final ConfettiController _confetti;

  TaskItemState();

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 1));
    final user = AuthService().user;
    if (user != null) {
      _calendarSub = CalendarService().watchConnected(user.uid).listen((connected) {
        if (mounted) setState(() => _calendarConnected = connected);
      });
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
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
    final theme = Theme.of(context);
    final p = theme.appTokens.of(widget.task.priority);
    final done = widget.task.completed;
    final ink = done ? p.ink.withAlpha(150) : p.ink;
    final timeFrame = DateService().timeFrameBuilder(widget.task);

    isExpandable = widget.task.description != null || widget.task.tags.isNotEmpty;

    // Preserve the multi-day connected-corner logic; a full-round card otherwise.
    const double r = Corners.md;
    const double rTight = 4;
    BorderRadius borderRadius;
    if (widget.task.isMultiDayStart) {
      borderRadius = const BorderRadius.horizontal(left: Radius.circular(r), right: Radius.circular(rTight));
    } else if (widget.task.isMultiDayEnd) {
      borderRadius = const BorderRadius.horizontal(left: Radius.circular(rTight), right: Radius.circular(r));
    } else if (widget.task.isMultiDayMiddle) {
      borderRadius = const BorderRadius.all(Radius.circular(rTight));
    } else {
      borderRadius = BorderRadius.circular(r);
    }

    return Stack(children: [
      AnimatedContainer(
        duration: reduceMotion(context) ? Duration.zero : Motion.fast,
        curve: Motion.standard,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          // Completed cards recede: blend the priority fill hard toward the
          // page background so they read as "done" and don't compete with
          // active tasks. Keyline and border are muted too.
          color: done
              ? Color.alphaBlend(theme.scaffoldBackgroundColor.withAlpha(205), p.fill)
              : p.fill,
          border: Border.all(color: done ? theme.appTokens.hairline : p.border),
          borderRadius: borderRadius,
          boxShadow: done ? null : theme.appTokens.raisedShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isExpandable ? () => setState(() => expanded = !expanded) : null,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Severity keyline (muted once completed)
                Container(width: 4, color: done ? p.accent.withAlpha(70) : p.accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Checkbox(
                                  value: widget.task.completed,
                                  activeColor: p.accent,
                                  checkColor: theme.colorScheme.surface,
                                  side: BorderSide(color: p.accent, width: 2),
                                  onChanged: (value) async {
                                    if (value!) {
                                      if (!reduceMotion(context)) _confetti.play();
                                      PerformanceService().incrementScore(AuthService().user!.uid,
                                          PerformanceService().getScore(widget.task.priority));
                                      widget.onComplete(widget.index);
                                    } else {
                                      PerformanceService().decrementScore(AuthService().user!.uid,
                                          PerformanceService().getScore(widget.task.priority));
                                    }
                                    if (widget.task.isSubtask) {
                                      // Updates the child and rolls the parent's
                                      // completed-counter (auto-complete/reopen).
                                      await widget.taskService.toggleSubtaskComplete(widget.task, value);
                                    } else {
                                      const completeTimeFormat = "${DateService.stringFmt} ${DateService.dbTimeFormat}";
                                      // TAGS HERE ARE NAME, NOT ID
                                      await widget.taskService.updateTaskByKey({
                                        "completed": value,
                                        "completedTime": DateFormat(completeTimeFormat).format(DateTime.now())
                                      }, widget.task);
                                    }
                                    if (value && widget.task.goalId != null && widget.task.id != null) {
                                      _backfillGoalGeneration(widget.task);
                                    }
                                  }),
                              if (widget.task.pushCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Text('(${widget.task.pushCount})',
                                      style: theme.textTheme.labelMedium?.copyWith(
                                          color: ink.withAlpha(180), fontWeight: FontWeight.w700)),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.task.isSubtask && widget.task.parentTitle != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 1),
                                        child: Row(
                                          children: [
                                            Icon(FontAwesomeIcons.arrowTurnUp,
                                                size: 9, color: ink.withAlpha(150)),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(widget.task.parentTitle!,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                      fontSize: 10, color: ink.withAlpha(180))),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (widget.task.goalId != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 1),
                                        child: Row(
                                          children: [
                                            Icon(FontAwesomeIcons.bullseye, size: 9, color: theme.appTokens.goal),
                                            const SizedBox(width: 4),
                                            Text('GOAL',
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                    fontSize: 9, letterSpacing: 0.8, color: theme.appTokens.goal)),
                                          ],
                                        ),
                                      ),
                                    if (timeFrame != '')
                                      Text(timeFrame,
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: ink.withAlpha(200), fontWeight: FontWeight.w600)),
                                    Row(children: [
                                      Flexible(
                                        child: Text(
                                          widget.task.title,
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            color: ink,
                                            decoration: done ? TextDecoration.lineThrough : null,
                                            decorationColor: ink.withAlpha(140),
                                          ),
                                          maxLines: expanded ? null : 2,
                                          overflow: expanded ? null : TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isExpandable && !expanded)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 6),
                                          child: Icon(FontAwesomeIcons.solidCircle, size: 4, color: ink.withAlpha(140)),
                                        ),
                                    ]),
                                    AnimatedSize(
                                      duration: reduceMotion(context) ? Duration.zero : Motion.fast,
                                      curve: Motion.standard,
                                      alignment: Alignment.topLeft,
                                      child: (isExpandable && expanded)
                                          ? Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (widget.task.description != null)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                                                    child: SelectableText(widget.task.description!,
                                                        style: theme.textTheme.bodySmall
                                                            ?.copyWith(color: ink.withAlpha(210))),
                                                  ),
                                                if (widget.task.tags.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                                                    child: Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      children: widget.task.tags
                                                          .map((tag) => Container(
                                                                padding: const EdgeInsets.symmetric(
                                                                    horizontal: 8, vertical: 3),
                                                                decoration: BoxDecoration(
                                                                  color: ink.withAlpha(28),
                                                                  borderRadius: BorderRadius.circular(999),
                                                                ),
                                                                child: Text(tag.label,
                                                                    style: theme.textTheme.labelSmall?.copyWith(
                                                                        fontSize: 10, color: ink, letterSpacing: 0.2)),
                                                              ))
                                                          .toList(),
                                                    ),
                                                  ),
                                              ],
                                            )
                                          : const SizedBox(width: double.infinity),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Theme(
                          data: theme.copyWith(iconTheme: IconThemeData(color: ink.withAlpha(190))),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                            actionButtons(context, widget.isBacklog),
                            ReorderableDragStartListener(
                              index: widget.index,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Icon(FontAwesomeIcons.gripLines, size: 16, color: ink.withAlpha(120)),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: Center(
          child: ConfettiWidget(
            maximumSize: const Size(20, 10),
            minimumSize: const Size(10, 5),
            confettiController: _confetti,
            blastDirectionality: BlastDirectionality.explosive,
            maxBlastForce: 50,
            minBlastForce: 5,
            emissionFrequency: 0.03,
            numberOfParticles: 10,
            gravity: .7,
          ),
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

  Future<void> _showAddSubtaskDialog(BuildContext context) async {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add subtask'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Subtask'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Add')),
        ],
      ),
    );
    if (title == null || title.trim().isEmpty) return;
    try {
      await widget.taskService.addSubtask(widget.task, title.trim());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not add subtask: $e')));
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
          } else if (value == "ADD_SUBTASK") {
            _showAddSubtaskDialog(context);
          }
        },
        itemBuilder: (context) => [
              // Subtasks: only tasks that aren't already a subtask, recurring, or
              // multi-day can take subtasks (one level; guarded in the service too).
              if (!widget.task.isSubtask &&
                  widget.task.recurringTemplateId == null &&
                  !widget.task.isMultiDay)
                const PopupMenuItem(
                    value: "ADD_SUBTASK",
                    child: Row(
                      children: [
                        Icon(FontAwesomeIcons.listUl),
                        Padding(padding: EdgeInsets.only(left: 8), child: Text('Add subtask'))
                      ],
                    )),
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
