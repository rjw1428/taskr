import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/progress_bar.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/task_list/task_item.dart';
import '../shared/shared.dart';

class TaskListScreen extends StatefulWidget {
  const TaskListScreen({super.key});

  @override
  TaskListState createState() => TaskListState();
}

class TaskListState extends State<TaskListScreen> {
  List<Task>? _tasks;
  int _completedCount = 0;
  int _totalCount = 0;
  String selectedDate = DateService().getString(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
        stream: AuthService().userStream.switchMap((user) {
          if (user == null) {
            return Stream.value([]);
          }
          var userId = user.uid;
          return TaskService().streamTasks(userId, selectedDate);
        }),
        builder: (context, snapshot) {
          final userId = AuthService().user!.uid;
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
              var taskId = list!.removeAt(taskIndex);
              list!.add(taskId);
              TaskService().updateTaskOrder(userId, list, selectedDate);
            });
          }

          List<Widget> _children = [];
          for (int i = 0; i < _tasks!.length; i++) {
            final task = _tasks![i];
            _children.add(displayTask(task, i, onComplete));
            // if (task.dueDate == null) {
            //   if (DateService().getString(DateTime.now()) == selectedDate) {
            //     _children.add(displayTask(task, i));
            //   }
            // } else {
            //   if (task.dueDate == selectedDate) {
            //     _children.add(displayTask(task, i));
            //   }
            // }
          }
          return Scaffold(
              appBar: AppBar(
                title: const Text('Taskr'),
                actions: [
                  IconButton(
                      onPressed: () => AuthService().signOut(),
                      icon: const Icon(FontAwesomeIcons.userAstronaut))
                ],
              ),
              body: ReorderableListView(
                  header: Column(children: [
                    DailyProgress(numberator: _completedCount, denominator: _totalCount),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                                DateService().getDayOfWeek(DateService().getDate(selectedDate))),
                          ),
                        ),
                        IconButton(
                            onPressed: () => setState(() {
                                  print("LEFT");
                                  selectedDate = DateService()
                                      .decrementDate(DateService().getDate(selectedDate));
                                  DateService()
                                      .setSelectedDate(DateService().getDate(selectedDate));
                                }),
                            icon: const Icon(FontAwesomeIcons.caretLeft)),
                        Text(selectedDate),
                        IconButton(
                            onPressed: () => setState(() {
                                  print("RIGHT");
                                  selectedDate = DateService()
                                      .incrementDate(DateService().getDate(selectedDate));
                                  DateService()
                                      .setSelectedDate(DateService().getDate(selectedDate));
                                }),
                            icon: const Icon(FontAwesomeIcons.caretRight)),
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

                      TaskService().updateTaskOrder(userId, list, selectedDate);
                    });
                  },
                  children: _children),
              bottomNavigationBar: const BottomNavBar(),
              floatingActionButton: FloatingActionButton(
                  child: const Icon(FontAwesomeIcons.plus, size: 20),
                  onPressed: () => showDialog(
                      context: context, builder: (BuildContext context) => const AddTaskScreen())));
        });
  }

  displayTask(Task task, int i, Function onComplete) {
    _totalCount++;
    if (task.completed) {
      _completedCount++;
    }
    return TaskItem(task: task, index: i, key: ValueKey(task.id!), onComplete: onComplete);
  }
}
