import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:taskr/shared/loading.dart';

class AddTaskScreen extends StatelessWidget {
  final Task? task;
  final bool isBacklog;
  const AddTaskScreen({super.key, this.task, required this.isBacklog});

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
                            style: const TextStyle(fontSize: 40, color: Colors.black)),
                        SizedBox(
                          // width: MediaQuery.of(context).size.width * .5,
                          height: 500,
                          child: TaskForm(task: task, isBacklog: isBacklog),
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
  final bool isBacklog;
  const TaskForm({super.key, this.task, required this.isBacklog});

  @override
  TaskFormState createState() => TaskFormState(task: task, isBacklog: isBacklog);
}

class TaskFormState extends State<TaskForm> {
  final _formKey = GlobalKey<FormState>();
  final Task? task;
  final bool isBacklog;
  // String _modified = '';
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _dueDate;
  String? _startTime;
  String? _endTime;
  Effort _priority = Effort.low;
  List<Tag>? _tags;
  List<Tag> _initTags = const [];
  bool _completed = false;
  // List<String> _subTasks = const [];
  DateTime? initialDueDate;
  bool apiPending = false;

  TaskFormState({this.task, required this.isBacklog}) {
    if (task != null) {
      _title.text = task!.title;
      _description.text = task!.description ?? '';
      _dueDate = task!.dueDate;
      _startTime = task!.startTime;
      _endTime = task!.endTime;
      _priority = task!.priority;
      _initTags = task!.tags;
      _completed = task!.completed;
    }

    initialDueDate =
        _dueDate == null ? DateService().getSelectedDate() : DateService().getDate(_dueDate!);
    _dueDate = isBacklog ? null : DateService().getString(initialDueDate!);
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
        completed: _completed,
        dueDate: _dueDate,
        startTime: _startTime,
        endTime: _endTime,
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
                  value: color.key,
                  child: Text(color.key.name, style: TextStyle(color: color.value))))
              .toList();
          // final selectedPriorityOption = Provider.of<String>(context);
          var tags = snapshot.hasError || !snapshot.hasData ? [] as List<Tag> : snapshot.data!;
          _tags ??= _initTags;
          // print(_tags!.map((t) => "${t.id}: ${t.label}").toList());
          return Form(
            key: _formKey, // Assign the form key
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
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

                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text("Effort Level:"),
                ),
                DropdownButton(
                  items: colorOptions,
                  hint: const Text('Set Effort'),
                  onChanged: (value) => setState(() {
                    _priority = value!;
                  }),
                  value: _priority,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final date = await _selectDate(context, initialDueDate!);
                        if (date == null) {
                          return;
                        }
                        setState(() => _dueDate = DateService().getString(date));
                      },
                      child: Text(_dueDate == null ? 'Set a due date' : _dueDate!),
                    ),
                    if (_dueDate != null)
                      IconButton(
                        onPressed: () => setState(() {
                          _dueDate = null;
                        }),
                        icon: const Icon(FontAwesomeIcons.xmark),
                      ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                        child: Text(_startTime == null
                            ? 'Set a start time'
                            : DateService().displayTime(_startTime!))),
                    if (_startTime != null)
                      IconButton(
                        onPressed: () => setState(() {
                          _startTime = null;
                          _endTime = null;
                        }),
                        icon: const Icon(FontAwesomeIcons.xmark),
                      ),
                  ],
                ),
                if (_startTime != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                          onPressed: () async {
                            final initial = _endTime == null
                                ? TimeOfDay.now()
                                : DateService().getTime(_endTime!);
                            final time = await _selectTime(context, initial);
                            if (time == null) {
                              return;
                            }
                            // IF END TIME IS EARLIER THAN START TIME, ERROR?
                            setState(() {
                              DateTime tempDateTime = DateTime(2024, 1, 1, time.hour, time.minute);
                              _endTime = DateService().getTimeStr(tempDateTime);
                            });
                          },
                          child: Text(_endTime == null
                              ? 'Set an end time'
                              : DateService().displayTime(_endTime!))),
                      if (_endTime != null)
                        IconButton(
                          onPressed: () => setState(() {
                            _endTime = null;
                          }),
                          icon: const Icon(FontAwesomeIcons.xmark),
                        ),
                    ],
                  ),

                if (_dueDate == null && !isBacklog)
                  const Text('Item will be added to the backlog without a due date'),
                if (_dueDate != null && isBacklog)
                  const Text('Item will be scheduled on the selected date'),
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
                  initialValue: _tags!.map((t) => t.id).toList(), // NEED TO BE ID's
                  onConfirm: (result) => setState(() =>
                      _tags = result.map((id) => tags.firstWhere((tag) => id == tag.id)).toList()),
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
