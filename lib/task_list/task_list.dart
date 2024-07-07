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
          if (snapshot.hasError || !snapshot.hasData) {
            _tasks = [];
          }

          _tasks = snapshot.data!;
          List<Widget> _children = [];
          for (int i = 0; i < _tasks!.length; i++) {
            final task = _tasks![i];
            // _children.add(ReorderableDragStartListener(
            //     key: ValueKey(task.id!), index: i, child: TaskItem(task: task)));
            _children.add(TaskItem(task: task, index: i, key: ValueKey(task.id!)));
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
                      final userId = AuthService().user!.uid;
                      TaskService().updateTaskOrder(userId, list);
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
}
