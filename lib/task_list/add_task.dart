import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:taskr/shared/loading.dart';

class AddTaskScreen extends StatelessWidget {
  final Task? task;
  const AddTaskScreen({super.key, this.task});

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
                        Text(task == null ? "Add a task" : "Edit task",
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
  final Task? task;
  const TaskForm({super.key, this.task});

  @override
  TaskFormState createState() => TaskFormState(task: task);
}

class TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  final Task? task;

  // String _modified = '';
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _dueDate;
  String? _startTime;
  // final String _endTime = '';
  String _priority = 'low';
  List<String>? _tags;
  List<String> _initTagLabels = [];
  // List<String> _subTasks = const [];
  DateTime? initialDueDate;
  bool apiPending = false;
  bool _showSelectDate = true;

  TaskFormState({this.task}) {
    if (task != null) {
      _title.text = task!.title;
      _description.text = task!.description ?? '';
      _dueDate = task!.dueDate;
      _startTime = task!.startTime;
      _priority = task!.priority;
      _initTagLabels = task!.tags;
    }

    initialDueDate =
        _dueDate == null ? DateService().getSelectedDate() : DateService().getDate(_dueDate!);
    _dueDate = DateService().getString(initialDueDate!);
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
        description: _description.value.text,
        priority: _priority,
        completed: false,
        dueDate: _dueDate,
        startTime: _startTime,
        added: DateTime.now().millisecondsSinceEpoch,
        tags: _tags ?? [],
        subtasks: []);

    if (task == null) {
      // ADD NEW TASK
      await TaskService().addTask(newTask);
    } else {
      if (task!.dueDate != newTask.dueDate) {
        // MOVE TO NEW DAY
        await TaskService().deleteTask(task!);
        await TaskService().addTask(newTask);
      } else {
        // UPDATE WITHIN THE SAME DAY
        await TaskService().updateTask(task!.id!, newTask);
      }
    }

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

          var initTags = _initTagLabels.where((label) => label != '<NOT FOUND>').map((label) {
            return tags.firstWhere((tag) => tag.label == label).id;
          }).toList();
          _tags ??= initTags;

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
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Description'),
                  controller: _description,
                ),
                DropdownButton(
                  items: colorOptions,
                  hint: const Text('Set Priority'),
                  onChanged: (value) => setState(() {
                    _priority = value!;
                  }),
                  value: _priority,
                ),

                if (_showSelectDate)
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
                if (_dueDate != null && _showSelectDate)
                  ElevatedButton(
                      onPressed: () async {
                        final initial = _startTime == null
                            ? TimeOfDay.now()
                            : DateService().getTime(_startTime!);
                        final time = await _selectTime(context, initial);
                        if (time == null) {
                          return;
                        }
                        setState(() {
                          DateTime tempDateTime = DateTime(2024, 1, 1, time.hour, time.minute);
                          _startTime = DateService().getTimeStr(tempDateTime);
                        });
                      },
                      child: const Text('Set a start time')),
                if (_startTime != null) Text(DateService().displayTime(_startTime!)),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('Add to backlog'),
                  Checkbox(
                      value: !_showSelectDate,
                      onChanged: (value) => setState(() {
                            if (value == true) {
                              _dueDate = null;
                              _showSelectDate = false;
                            } else {
                              _dueDate = DateService().getString(initialDueDate!);
                              _showSelectDate = true;
                            }
                          }))
                ]),
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
                  initialValue: _tags!,
                  onConfirm: (result) => setState(() => _tags = result),
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

  Future<TimeOfDay?> _selectTime(BuildContext context, TimeOfDay initial) async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    return selectedTime;
  }
}
