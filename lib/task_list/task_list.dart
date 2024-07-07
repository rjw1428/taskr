import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Task>>(
        stream: AuthService().userStream.switchMap((user) {
          if (user == null) {
            return Stream.value([]);
          }
          var userId = user.uid;
          return TaskService().streamTasks(userId);
        }),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && _tasks == null) {
            return const LoadingScreen();
          }
          if (snapshot.hasError) {
            print("LIST ERROR: ${snapshot.error}");
            return const ErrorMessage(message: 'Oh Shit');
          }
          print("FETCHING NEW TASK DATA");
          _tasks = snapshot.hasError || !snapshot.hasData ? [] : snapshot.data!;

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
                      final userId = AuthService().user!.uid;
                      TaskService().updateTaskOrder(userId, list);
                    });
                  },
                  children:
                      _tasks!.map((task) => TaskItem(task: task, key: ValueKey(task.id!))).toList()
                  // tasks.toList().map((task, index) => ReorderableDragStartListener(index: 0,
                  // child: TaskItem(key: ValueKey(task.id!), task: task))),
                  ),
              bottomNavigationBar: const BottomNavBar(),
              floatingActionButton: FloatingActionButton(
                  child: const Icon(FontAwesomeIcons.plus, size: 20),
                  onPressed: () => showDialog(
                      context: context, builder: (BuildContext context) => const AddTaskScreen())));
        });
  }
}
