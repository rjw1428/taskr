import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class CopyTaskScreen extends StatelessWidget {
  final Task task;
  const CopyTaskScreen({super.key, required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(Corners.md),
                ),
                child: Padding(
                    padding: const EdgeInsets.all(Insets.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Copy Task", style: theme.textTheme.headlineMedium),
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
  TaskFormState createState() => TaskFormState();
}

class TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late Task task;
  String? _dueDate;
  bool apiPending = false;
  DateTime? initialDueDate;
  List<bool> repeatDayValues = List.generate(7, (index) => false);
  List<DateTime> repeatedDates = List.generate(7, (index) => DateTime(index));
  final TextEditingController _title = TextEditingController();
  final TaskService _taskService = TaskService();

  @override
  void initState() {
    super.initState();
    task = widget.task;
    initialDueDate = _dueDate == null ? DateService().getSelectedDate() : DateService().getDate(_dueDate!);
    _dueDate = DateService().getString(initialDueDate!);
    _title.text = widget.task.title;
    if (initialDueDate != null) {
      _updateRepeatedDays(initialDueDate!, true);
    }
  }

  List<bool> _updateRepeatDays(int index, bool value) {
    repeatDayValues[index] = value;
    debugPrint(repeatedDates[index].toString());
    return repeatDayValues;
  }

  List<DateTime> _updateRepeatedDays(DateTime selectedDate, bool initial) {
    final offset = selectedDate.weekday - 1;
    DateTime prev = selectedDate.subtract(Duration(days: offset));
    repeatedDates = List.generate(7, (index) => prev.add(Duration(days: index)));

    // Reset current selection except for selected date
    for (int i = 0; i < repeatDayValues.length; i++) {
      repeatDayValues[i] = initial ? false : i == selectedDate.weekday - 1;
    }

    return repeatedDates;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      apiPending = true;
    });

    _formKey.currentState!.save();

    List<Future> tasks = [];
    for (int i = 0; i < repeatDayValues.length; i++) {
      if (repeatDayValues[i]) {
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
            );
        newTask.dueDate = DateService().getString(repeatedDates[i]);
        tasks.add(_taskService.addTask(newTask));
      }
    }

    await Future.forEach(tasks, (x) => debugPrint(x.toString()));

    setState(() {
      apiPending = false;
    });

    if (mounted) {
      Navigator.of(context).pop();
    }
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
                setState(() {
                  _dueDate = DateService().getString(date);
                  repeatedDates = _updateRepeatedDays(date, false);
                });
              },
              child: const Text('Set a due date')),
          if (_dueDate != null) Text(_dueDate!),
          if (_dueDate != null)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: Insets.sm),
                    child: Text(
                      'Repeat:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                        7,
                        (index) => Column(
                              children: [
                                Text(
                                  DateService().getDayOfWeekByIndex(index),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  DateService().getShortDay(repeatedDates[index]),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Checkbox(
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    value: repeatDayValues[index],
                                    onChanged: (val) => setState(() => _updateRepeatDays(index, val!)))
                              ],
                            )),
                  ),
                ],
              ),
            ),
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
