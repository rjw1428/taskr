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
  Task? _dragElement;

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
          print(snapshot.connectionState);
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen();
          }
          if (snapshot.hasError) {
            print("LIST ERROR: ${snapshot.error}");
            return const ErrorMessage(message: 'Oh Shit');
          }
          print("ELEMENTS: ${snapshot.hasData}");
          var tasks = snapshot.hasError || !snapshot.hasData ? [] : snapshot.data!;
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
                  // onReorderStart: (index) => _dragElement = tasks[index],
                  onReorder: (int oldIndex, int newIndex) async {
                    print("$oldIndex -- $newIndex");
                    final userId = AuthService().user!.uid;
                    var list = await TaskService().getTaskOrder(userId);
                    if (newIndex == list.length) {
                      var item = list.removeAt(oldIndex);
                      list.add(item);
                    } else {
                      var item = list.removeAt(oldIndex);
                      list.insert(newIndex, item);
                    }
                    TaskService().updateTaskOrder(userId, list);
                    // _dragElement = null;
                  },
                  children:
                      tasks.map((task) => TaskItem(task: task, key: ValueKey(task.id!))).toList()
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
