import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

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
                        const Text("Add a task"),
                        const TaskForm(),
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
  final String _dueDate = '';
  final String _startTime = '';
  final String _endTime = '';
  int _priority = 1;
  // List<String> _tags = const [];
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
        tags: [],
        subtasks: []);
    await TaskService().addTasks(newTask);

    setState(() {
      apiPending = false;
    });

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
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
          DropdownButtonFormField(
            items: const [
              DropdownMenuItem(value: 1, child: Text('1')),
              DropdownMenuItem(value: 2, child: Text('2')),
              DropdownMenuItem(value: 3, child: Text('3')),
            ],
            onChanged: (value) => setState(() {
              _priority = value!;
            }),
            value: _priority,
          ),
          ElevatedButton(
            onPressed: apiPending ? null : () => _submit(),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
