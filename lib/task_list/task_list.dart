import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/progress_bar.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/task_list/task_item.dart';
import '../shared/shared.dart';

class TaskListScreen extends StatefulWidget {
  final bool isBacklog;
  final String userId;
  const TaskListScreen({super.key, required this.isBacklog, required this.userId});

  @override
  TaskListState createState() => TaskListState();
}

class TaskListState extends State<TaskListScreen> {
  List<Task>? _tasks;
  int _completedCount = 0;
  int _totalCount = 0;
  String today = DateService().getString(DateTime.now());
  String selectedDate = DateService().getString(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
        stream: TaskService().streamTasks(widget.userId, widget.isBacklog ? null : selectedDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _tasks == null) {
            return const LoadingScreen(message: 'Loading Tasks...');
          }
          if (snapshot.hasError) {
            print("LIST ERROR: ${snapshot.error}");
            return const ErrorMessage(message: 'Oh Shit');
          }
          print("FETCHING NEW TASK DATA");
          if (snapshot.hasError || !snapshot.hasData) {
            _tasks = [];
          }

          _tasks = snapshot.data!;
          _completedCount = 0;
          _totalCount = 0;
          onComplete(int taskIndex) {
            setState(() {
              var list = _tasks!.map((task) => task.id!).toList();
              var taskId = list.removeAt(taskIndex);
              list.add(taskId);
              TaskService().updateTaskOrder(widget.userId, list, widget.isBacklog ? null : selectedDate);
            });
          }

          FirebaseMessageService().initPushNotifications(context, _tasks!);
          List<Widget> children = [];
          for (int i = 0; i < _tasks!.length; i++) {
            final task = _tasks![i];
            children.add(displayTask(task, i, onComplete, widget.isBacklog));
          }

          if (children.isEmpty) {
            children.add(const Padding(
              key: ValueKey(0),
              padding: EdgeInsets.only(top: 80.0),
              child: Text(
                "You have nothing scheduled 🎉",
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ));
          }
          double? dragStart;
          return Scaffold(
              appBar: AppBar(
                title: const Text('Taskr'),
                actions: [
                  IconButton(onPressed: () => AuthService().signOut(), icon: const Icon(FontAwesomeIcons.userAstronaut))
                ],
              ),
              body: GestureDetector(
                  onHorizontalDragStart: (details) => dragStart = details.globalPosition.dx,
                  onHorizontalDragEnd: (details) {
                    final dragEnd = details.globalPosition.dx;
                    final dragDelta = dragEnd - dragStart!;
                    if (dragDelta > 10) {
                      setState(() {
                        selectedDate = DateService().decrementDate(DateService().getDate(selectedDate));
                        DateService().setSelectedDate(DateService().getDate(selectedDate));
                      });
                    } else if (dragDelta < -10) {
                      setState(() {
                        selectedDate = DateService().incrementDate(DateService().getDate(selectedDate));
                        DateService().setSelectedDate(DateService().getDate(selectedDate));
                      });
                    }
                  },
                  child: ReorderableListView(
                      header: Column(children: [
                        if (!widget.isBacklog) DailyProgress(numerator: _completedCount, denominator: _totalCount),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Expanded(
                                child: Center(
                                    child: Text(widget.isBacklog
                                        ? "Backlog"
                                        : DateService().getDayOfWeek(DateService().getDate(selectedDate))))),
                            if (!widget.isBacklog)
                              Row(
                                children: [
                                  if (DateService().isDateLessThan(today, selectedDate))
                                    IconButton(
                                        onPressed: () => setState(() {
                                              print("BACK TO TODAY");
                                              selectedDate = today;
                                              DateService().setSelectedDate(DateService().getDate(selectedDate));
                                            }),
                                        icon: const Icon(FontAwesomeIcons.backwardStep)),
                                  IconButton(
                                      onPressed: () => setState(() {
                                            print("LEFT");
                                            selectedDate =
                                                DateService().decrementDate(DateService().getDate(selectedDate));
                                            DateService().setSelectedDate(DateService().getDate(selectedDate));
                                          }),
                                      icon: const Icon(FontAwesomeIcons.caretLeft)),
                                  Text(selectedDate),
                                  IconButton(
                                      onPressed: () => setState(() {
                                            print("RIGHT");
                                            selectedDate =
                                                DateService().incrementDate(DateService().getDate(selectedDate));
                                            DateService().setSelectedDate(DateService().getDate(selectedDate));
                                          }),
                                      icon: const Icon(FontAwesomeIcons.caretRight)),
                                  if (DateService().isDateLessThan(selectedDate, today))
                                    IconButton(
                                        onPressed: () => setState(() {
                                              print("FORWARD TO TODAY");
                                              selectedDate = today;
                                              DateService().setSelectedDate(DateService().getDate(selectedDate));
                                            }),
                                        icon: const Icon(FontAwesomeIcons.forwardStep)),
                                ],
                              )
                          ],
                        ),
                      ]),
                      buildDefaultDragHandles: false,
                      onReorder: (int oldIndex, int newIndex) {
                        setState(() {
                          final delta = newIndex > oldIndex ? -1 : 0;
                          var list = _tasks!.map((task) => task.id!).toList();
                          if (newIndex == list.length) {
                            var swapId = list.removeAt(oldIndex);
                            list.add(swapId);

                            var swapItem = _tasks!.removeAt(oldIndex);
                            _tasks!.add(swapItem);
                          } else {
                            var item = list.removeAt(oldIndex);
                            list.insert(newIndex + delta, item);

                            var swapItem = _tasks!.removeAt(oldIndex);
                            _tasks!.insert(newIndex + delta, swapItem);
                          }

                          TaskService().updateTaskOrder(widget.userId, list, widget.isBacklog ? null : selectedDate);
                        });
                      },
                      children: children)),
              bottomNavigationBar: BottomNavBar(selectedIndex: widget.isBacklog ? 2 : 0),
              floatingActionButton: FloatingActionButton(
                  child: const Icon(FontAwesomeIcons.plus, size: 20),
                  onPressed: () => showModalBottomSheet(
                      isScrollControlled: true,
                      useSafeArea: true,
                      context: context,
                      builder: (BuildContext context) => AddTaskScreen(isBacklog: widget.isBacklog))));
        });
  }

  displayTask(Task task, int i, Function onComplete, bool isBacklog) {
    _totalCount += PerformanceService().getScore(task.priority);
    if (task.completed) {
      _completedCount += PerformanceService().getScore(task.priority);
    }
    return TaskItem(task: task, index: i, key: ValueKey(task.id!), onComplete: onComplete, isBacklog: isBacklog);
  }
}
