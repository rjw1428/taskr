import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

class CopyTaskScreen extends StatelessWidget {
  final Task task;
  const CopyTaskScreen({super.key, required this.task});

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
                        const Text("Copy Task",
                            style: TextStyle(fontSize: 40, color: Colors.black)),
                        SizedBox(
                          // width: MediaQuery.of(context).size.width * .5,
                          height: 500,
                          child: TaskForm(task: task),
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
  final Task task;
  const TaskForm({super.key, required this.task});

  @override
  TaskFormState createState() => TaskFormState(task: task);
}

class TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  final Task task;
  String? _dueDate;
  bool apiPending = false;
  DateTime? initialDueDate;
  final TextEditingController _title = TextEditingController();

  TaskFormState({required this.task}) {
    initialDueDate =
        _dueDate == null ? DateService().getSelectedDate() : DateService().getDate(_dueDate!);
    _dueDate = DateService().getString(initialDueDate!);
    _title.text = task.title;
  }
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      apiPending = true;
    });

    _formKey.currentState!.save();
    Task newTask = Task(
        title: _title.value.text,
        description: task.description,
        priority: task.priority,
        completed: false,
        dueDate: _dueDate,
        startTime: task.startTime,
        endTime: task.endTime,
        added: DateTime.now().millisecondsSinceEpoch,
        tags: task.tags,
        subtasks: []);
    await TaskService().addTask(newTask);

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
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Title'),
            controller: _title,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter the title';
              }
              return null;
            },
          ),

          ElevatedButton(
              onPressed: () async {
                final date = await _selectDate(context, initialDueDate!);
                if (date == null) {
                  return;
                }
                setState(() => _dueDate = DateService().getString(date));
              },
              child: const Text('Set a due date')),
          if (_dueDate != null) Text(_dueDate!),
          ElevatedButton(
            onPressed: apiPending ? null : () => _submit(),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _selectDate(BuildContext context, DateTime initial) async {
    final now = DateTime.now();
    final DateTime? selectedDate = await showDatePicker(
        context: context,
        initialDate: initial,
        initialDatePickerMode: DatePickerMode.day,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 1));
    return selectedDate;
  }
}
