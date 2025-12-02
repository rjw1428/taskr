import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';

class AddTaskScreen extends StatefulWidget {
  final Task? task;
  final bool isBacklog;
  const AddTaskScreen({super.key, this.task, required this.isBacklog});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  // String _modified = '';
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _dueDate;
  String? _startTime;
  String? _endTime;
  Effort _priority = Effort.low;
  Effort initialPriority = Effort.low;
  bool _completed = false;
  // List<String> _subTasks = const [];
  DateTime? initialDueDate;
  bool apiPending = false;
  List<DropdownMenuItem> colorOptions = priorityColors.entries
      .map((color) => DropdownMenuItem(
          value: color.key,
          child: Text(color.key.name, style: TextStyle(color: color.key == Effort.info ? Colors.white : color.value))))
      .toList();
  late List<Tag>? _tags = [];

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

    if (widget.task == null) {
      // ADD NEW TASK
      await TaskService().addTask(newTask);
    } else {
      if (widget.task!.dueDate != newTask.dueDate) {
        // MOVE TO NEW DAY
        await TaskService().deleteTask(widget.task!);
        await TaskService().addTask(newTask);
      } else {
        // UPDATE WITHIN THE SAME DAY
        await TaskService().updateTask(widget.task!.id!, newTask, widget.task!);
      }
    }

    setState(() {
      apiPending = false;
    });

    Navigator.of(context).pop();
  }

  @override
  void initState() {
    super.initState();

    if (widget.task != null) {
      _title.text = widget.task!.title;
      _description.text = widget.task!.description ?? '';
      _dueDate = widget.task!.dueDate;
      _startTime = widget.task!.startTime;
      _endTime = widget.task!.endTime;
      _priority = widget.task!.priority;
      _completed = widget.task!.completed;
      initialPriority = widget.task!.priority;
    }

    DateTime initialDueDate =
        _dueDate == null ? DateService().getSelectedDate() : DateService().getDate(widget.task!.dueDate!);
    _dueDate = widget.isBacklog ? null : DateService().getString(initialDueDate);

    // TagService().streamTagsArray(AuthService().user!.uid).first.then((tagList) {
    //   print(tagList);
    //   _tags = tagList;
    // });
  }

  @override
  Widget build(BuildContext context) {
    final keyboardSpace = MediaQuery.of(context).viewInsets.bottom;
    final title = widget.task == null ? "Add Task" : "Edit Task";
    final actionButtonText = widget.task == null ? "Save" : "Update";
    return SingleChildScrollView(
      child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, keyboardSpace + 16),
          child: Column(
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Form(
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
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        TextFormField(
                          decoration: const InputDecoration(labelText: 'Description'),
                          controller: _description,
                          style: Theme.of(context).textTheme.titleSmall,
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
                                      ? DateService().getRoundedTime(TimeOfDay.now())
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
                                child: Text(
                                    _startTime == null ? 'Set a start time' : DateService().displayTime(_startTime!))),
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
                                        ? DateService().getRoundedTime(DateService().getTime(_startTime!))
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
                                  child: Text(
                                      _endTime == null ? 'Set an end time' : DateService().displayTime(_endTime!))),
                              if (_endTime != null)
                                IconButton(
                                  onPressed: () => setState(() {
                                    _endTime = null;
                                  }),
                                  icon: const Icon(FontAwesomeIcons.xmark),
                                ),
                            ],
                          ),

                        if (_dueDate == null && !widget.isBacklog)
                          const Text('Item will be added to the backlog without a due date'),
                        if (_dueDate != null && widget.isBacklog)
                          const Text('Item will be scheduled on the selected date'),
                        if (_tags != null)
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
                            items: _tags!.map((tag) => MultiSelectItem(tag.id, tag.label)).toList(),
                            listType: MultiSelectListType.CHIP,
                            initialValue: _tags!.map((t) => t.id).toList(), // NEED TO BE ID's
                            onConfirm: (result) => setState(
                                () => _tags = result.map((id) => _tags!.firstWhere((tag) => id == tag.id)).toList()),
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
                          )
                      ])),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => _submit(),
                    child: Text(actionButtonText),
                  ),
                  ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      child: const Text('Close'))
                ],
              )
            ],
          )),
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

  Future<TimeOfDay?> _selectTime(BuildContext context, TimeOfDay initial) async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    return selectedTime;
  }
}
