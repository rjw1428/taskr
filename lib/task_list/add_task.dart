import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:taskr/shared/loading.dart';

class AddTaskScreen extends StatelessWidget {
  const AddTaskScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(20),
        child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text("Add a task",
                            style: TextStyle(fontSize: 40, color: Colors.black)),
                        SizedBox(
                          width: MediaQuery.of(context).size.width * .5,
                          height: 300,
                          child: const TaskForm(),
                        ),
                        ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Close'))
                      ],
                    )),
              ),
            )));
  }
}

class TaskForm extends StatefulWidget {
  const TaskForm({super.key});

  @override
  TaskFormState createState() => TaskFormState();
}

class TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();

  // String _added = '';
  // String _modified = '';
  // bool _completed = false;
  String _title = '';
  String? _description;
  // final String _dueDate = '';
  // final String _startTime = '';
  // final String _endTime = '';
  String _priority = 'low';
  List<String> _tags = const [];
  // List<String> _subTasks = const [];

  bool apiPending = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      apiPending = true;
    });

    _formKey.currentState!.save();
    Task newTask = Task(
        title: _title,
        description: _description,
        priority: _priority,
        completed: false,
        dueDate: 'tomorrow',
        startTime: 'later',
        added: DateTime.now().millisecondsSinceEpoch,
        tags: _tags,
        subtasks: []);
    await TaskService().addTasks(newTask);

    setState(() {
      apiPending = false;
    });

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: TagService().streamTagsArray(AuthService().user!.uid),
        builder: (context, snapshot) {
          print(snapshot.connectionState.toString());
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen();
          }
          if (snapshot.hasError) {
            print(snapshot.error.toString());
          }
          final colorOptions = priorityColors.entries
              .map((color) => DropdownMenuItem(
                  value: color.key, child: Text(color.key, style: TextStyle(color: color.value))))
              .toList();
          // final selectedPriorityOption = Provider.of<String>(context);
          var tags = snapshot.hasError || !snapshot.hasData ? [] as List<Tag> : snapshot.data!;
          return Form(
            key: _formKey, // Assign the form key
            child: Column(
              children: [
                // Text input fields and other form elements
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter the title';
                    }
                    return null;
                  },
                  onSaved: (value) => _title = value!,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Description'),
                  onSaved: (value) => _description = value!,
                ),
                DropdownButton(
                  items: colorOptions,
                  hint: const Text('Set Priority'),
                  onChanged: (value) => setState(() {
                    _priority = value!;
                  }),
                  value: _priority,
                ),

                MultiSelectDialogField(
                  title: const Text(
                    "Tags",
                    style: TextStyle(color: Colors.white),
                  ),
                  isDismissible: true,
                  itemsTextStyle: const TextStyle(color: Colors.white),
                  selectedColor: Colors.red,
                  selectedItemsTextStyle: const TextStyle(color: Colors.black),
                  backgroundColor: Colors.black,
                  items: tags.map((tag) => MultiSelectItem(tag.id, tag.label)).toList(),
                  listType: MultiSelectListType.CHIP,
                  onConfirm: (result) => _tags = result,
                  buttonIcon: const Icon(
                    FontAwesomeIcons.tag,
                    color: Colors.black,
                  ),
                  buttonText: const Text(
                    "Tags",
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: apiPending ? null : () => _submit(),
                  child: const Text('Submit'),
                ),
              ],
            ),
          );
        });
  }
}
