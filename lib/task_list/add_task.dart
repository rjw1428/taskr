import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:rrule/rrule.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/shared/shared.dart';
import 'package:multi_select_flutter/multi_select_flutter.dart';
import 'package:taskr/task_list/recurring_task_form.dart';

class AddTaskScreen extends StatefulWidget {
  final Task? task;
  final bool isBacklog;
  const AddTaskScreen({super.key, this.task, required this.isBacklog});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _recurringTaskFormKey = GlobalKey<RecurringTaskFormState>();
  // String _modified = '';
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  String? _dueDate;
  String? _startTime;
  String? _endTime;
  Effort _priority = Effort.low;
  Effort initialPriority = Effort.low;
  bool _completed = false;
  bool _isRecurring = false;
  bool _isMultiDay = false;
  bool _countdown = false;
  bool _reminderEnabled = false;
  String? _multiDayEndDate;
  String? _multiDayStartDate;
  String? _reminderTime;
  RecurringTask? _recurringTaskTemplate;
  // List<String> _subTasks = const [];
  DateTime? initialDueDate;
  bool apiPending = false;
  late List<Tag> _allTags = [];
  late List<Tag> _selectedTags = [];
  final TaskService _taskService = TaskService();

  getRecurrenceFrequency(String templateRecurrance) {
    if (templateRecurrance == 'Daily') return Frequency.daily;
    if (templateRecurrance == 'Weekly') return Frequency.weekly;
    if (templateRecurrance == 'Monthly') return Frequency.monthly;
    if (templateRecurrance == 'Yearly') return Frequency.yearly;
  }

  List<ByWeekDayEntry> getWeeklyRecurrenceList(Map<String, bool> daysOfWeek) {
    return daysOfWeek.entries.fold([], (acc, entry) {
      if (!entry.value) return acc;

      if (entry.key == 'Su') acc.add(ByWeekDayEntry(DateTime.sunday));
      if (entry.key == 'Mo') acc.add(ByWeekDayEntry(DateTime.monday));
      if (entry.key == 'Tu') acc.add(ByWeekDayEntry(DateTime.tuesday));
      if (entry.key == 'We') acc.add(ByWeekDayEntry(DateTime.wednesday));
      if (entry.key == 'Th') acc.add(ByWeekDayEntry(DateTime.thursday));
      if (entry.key == 'Fr') acc.add(ByWeekDayEntry(DateTime.friday));
      if (entry.key == 'Sa') acc.add(ByWeekDayEntry(DateTime.saturday));
      return acc;
    });
  }

  String _formatReminder(String isoString) {
    final dt = DateTime.parse(isoString).toLocal();
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$month/$day $hour:$minute $period';
  }

  Future<void> _loadMultiDayEndDate() async {
    final group = await _taskService.getMultiDayGroup(
      widget.task!.multiDayGroupId!,
      knownDate: widget.task!.dueDate!,
    );
    if (group.isNotEmpty && mounted) {
      setState(() {
        _multiDayStartDate = group.first.dueDate;
        _multiDayEndDate = group.last.dueDate;
      });
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isRecurring) {
      final recurringValidationError = _recurringTaskFormKey.currentState?.validate();
      if (recurringValidationError != null) {
        return;
      }
    }

    setState(() {
      apiPending = true;
    });

    try {
      await _saveTask();
    } catch (e) {
      if (mounted) {
        setState(() => apiPending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save task: $e')),
        );
      }
    }
  }

  Future<void> _saveTask() async {
    // Save Recurring Task
    if (_isRecurring && _dueDate != null && _recurringTaskTemplate != null) {
      _recurringTaskTemplate!.startDate = DateService().getDate(_dueDate!);

      // if not weekly, remove daysOfWeek
      if (_recurringTaskTemplate!.recurrenceType != "Weekly") {
        _recurringTaskTemplate!.daysOfWeek = null;
      }

      if (_recurringTaskTemplate!.recurrenceType == 'Yearly' || _recurringTaskTemplate!.recurrenceType == 'Daily') {
        _recurringTaskTemplate!.frequency = null;
      }

      if (_recurringTaskTemplate!.recurrenceType != 'Monthly') {
        _recurringTaskTemplate!.dayOfMonth = null;
      }

      final recurringTaskTemplateId = await TaskService().saveRecurringTask(_recurringTaskTemplate!);

      final type = getRecurrenceFrequency(_recurringTaskTemplate!.recurrenceType);
      final untilDate = _recurringTaskTemplate!.endDate?.toUtc();
      RecurrenceRule rule;
      switch (_recurringTaskTemplate!.recurrenceType) {
        case 'Weekly':
          rule = RecurrenceRule(
            frequency: type,
            interval: _recurringTaskTemplate!.frequency ?? 1,
            until: untilDate,
            byWeekDays: getWeeklyRecurrenceList(_recurringTaskTemplate!.daysOfWeek!),
          );
          break;
        case 'Monthly':
          rule = RecurrenceRule(
            frequency: type,
            interval: _recurringTaskTemplate!.frequency ?? 1,
            until: untilDate,
            byMonthDays: [_recurringTaskTemplate!.dayOfMonth!],
          );
          break;
        default:
          rule = RecurrenceRule(
            frequency: type,
            interval: _recurringTaskTemplate!.frequency ?? 1,
            until: untilDate,
          );
      }

      final instancesStart = _recurringTaskTemplate!.startDate?.toUtc() ?? DateTime.now().toUtc();
      final instances = rule.getInstances(start: instancesStart).take(30);

      final firstInstance = instances.first;

      final firstTask = Task(
        title: _title.value.text.trim(),
        description: _description.value.text.trim(),
        priority: _priority,
        completed: false,
        dueDate: DateService().getString(firstInstance),
        startTime: _startTime,
        endTime: _endTime,
        recurringTemplateId: recurringTaskTemplateId,
        added: DateTime.now().millisecondsSinceEpoch,
        tags: _selectedTags,
        pushCount: 0,
        countdown: _countdown,
      );
      await _taskService.addTask(firstTask);

      setState(() {
        apiPending = false;
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('First task in series added. The rest are being added in the background.'),
          ),
        );
      }

      // Add remaining tasks in the background
      _addRemainingTasks(instances.skip(1), recurringTaskTemplateId);
    } else if (_isMultiDay && _dueDate != null && _multiDayEndDate != null && widget.task == null) {
      final startDate = DateService().getDate(_dueDate!);
      final endDate = DateService().getDate(_multiDayEndDate!);
      final dayCount = endDate.difference(startDate).inDays + 1;

      if (dayCount < 2) {
        setState(() => apiPending = false);
        return;
      }

      final groupId = DateTime.now().millisecondsSinceEpoch.toString();

      for (int i = 0; i < dayCount; i++) {
        final date = startDate.add(Duration(days: i));
        String position;
        if (i == 0) {
          position = 'start';
        } else if (i == dayCount - 1) {
          position = 'end';
        } else {
          position = 'middle';
        }

        final task = Task(
          title: _title.value.text.trim(),
          description: _description.value.text.trim(),
          priority: _priority,
          completed: false,
          dueDate: DateService().getString(date),
          added: DateTime.now().millisecondsSinceEpoch,
          tags: _selectedTags,
          pushCount: 0,
          countdown: _countdown,
          multiDayGroupId: groupId,
          multiDayPosition: position,
        );
        await _taskService.addTask(task);
      }

      setState(() => apiPending = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Multi-day task added ($dayCount days)')),
        );
        Navigator.of(context).pop();
      }
    } else if (widget.task != null && widget.task!.isMultiDay && _multiDayEndDate != null) {
      final groupId = widget.task!.multiDayGroupId!;
      await _taskService.updateMultiDayEndDate(groupId, _multiDayEndDate!, widget.task!.copyWith(
        title: _title.value.text.trim(),
        description: _description.value.text.trim(),
        priority: _priority,
        tags: _selectedTags,
      ));

      // Also update all existing days with the edited title/description/priority/tags
      final group = await _taskService.getMultiDayGroup(groupId, knownDate: widget.task!.dueDate!);
      for (final task in group) {
        await _taskService.updateTaskByKey({
          'title': _title.value.text.trim(),
          'description': _description.value.text.trim(),
          'priority': _priority.name,
          'tags': _selectedTags.map((t) => t.id).toList(),
        }, task);
      }

      setState(() => apiPending = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Multi-day task updated')),
        );
        Navigator.of(context).pop();
      }
    } else {
      Task newTask = Task(
          id: widget.task?.id,
          title: _title.value.text.trim(),
          description: _description.value.text.trim(),
          priority: _priority,
          completed: _completed,
          dueDate: _dueDate,
          startTime: _startTime,
          endTime: _endTime,
          recurringTemplateId: null,
          added: DateTime.now().millisecondsSinceEpoch,
          tags: _selectedTags,
          pushCount: widget.task?.pushCount ?? 0,
          goalId: widget.task?.goalId,
          feedback: widget.task?.feedback,
          multiDayGroupId: widget.task?.multiDayGroupId,
          multiDayPosition: widget.task?.multiDayPosition,
          reminderTime: _reminderTime,
          reminderTaskName: widget.task?.reminderTaskName,
          parentId: widget.task?.parentId,
          parentTitle: widget.task?.parentTitle,
          countdown: _countdown);

      if (widget.task == null) {
        final taskId = await _taskService.addTask(newTask);
        if (_reminderTime != null) {
          newTask = newTask.copyWith(id: taskId);
          await ReminderService().scheduleReminder(newTask);
        }
      } else {
        if (widget.task!.dueDate != newTask.dueDate) {
          if (widget.task!.reminderTaskName != null) {
            await ReminderService().cancelReminder(widget.task!);
          }
          await _taskService.deleteTask(widget.task!);
          await _taskService.addTask(newTask);
          if (_reminderTime != null) {
            await ReminderService().scheduleReminder(newTask);
          }
        } else {
          await _taskService.updateTask(widget.task!.id!, newTask, widget.task!);
          final oldReminder = widget.task!.reminderTime;
          if (oldReminder != _reminderTime) {
            if (_reminderTime == null) {
              await ReminderService().cancelReminder(widget.task!);
            } else if (oldReminder == null) {
              await ReminderService().scheduleReminder(newTask);
            } else {
              await ReminderService().updateReminder(widget.task!, _reminderTime!);
            }
          }
        }
      }
      setState(() {
        apiPending = false;
      });

      if (mounted) {
        final message = widget.task == null ? 'Task added' : 'Task updated';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _addRemainingTasks(Iterable<DateTime> instances, String? recurringTaskTemplateId) async {
    for (var instance in instances) {
      final task = Task(
        title: _title.value.text.trim(),
        description: _description.value.text.trim(),
        priority: _priority,
        completed: false,
        dueDate: DateService().getString(instance),
        startTime: _startTime,
        endTime: _endTime,
        recurringTemplateId: recurringTaskTemplateId,
        added: DateTime.now().millisecondsSinceEpoch,
        tags: _selectedTags,
        pushCount: 0,
      );
      await _taskService.addTask(task);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recurring task series fully added.'),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();

    _allTags = Provider.of<TagProvider>(context, listen: false).tags;

    if (widget.task != null) {
      _title.text = widget.task!.title;
      _description.text = widget.task!.description ?? '';
      _dueDate = widget.task!.dueDate;
      _startTime = widget.task!.startTime;
      _endTime = widget.task!.endTime;
      _priority = widget.task!.priority;
      _completed = widget.task!.completed;
      initialPriority = widget.task!.priority;
      _selectedTags = widget.task!.tags;
      _reminderTime = widget.task!.reminderTime;
      _reminderEnabled = _reminderTime != null;
      _countdown = widget.task!.countdown;
      if (widget.task!.isMultiDay) {
        _isMultiDay = true;
        _loadMultiDayEndDate();
      }
    }

    if (_dueDate != null) {
      initialDueDate = DateService().getDate(widget.task!.dueDate!);
    } else if (widget.task == null) {
      // New task: on the backlog default to no due date; on the to-do list
      // default to the day currently in view. The date picker still opens at a
      // sensible day either way.
      initialDueDate = DateService().getSelectedDate();
      if (!widget.isBacklog) {
        _dueDate = DateService().getString(initialDueDate!);
      }
    } else {
      initialDueDate = DateTime.now();
    }
  }

  Future<DateTime?> _selectDate(BuildContext context, DateTime initial) async {
    final now = DateTime.now();
    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      initialDatePickerMode: DatePickerMode.day,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    return selectedDate;
  }

  Future<TimeOfDay?> _selectTime(BuildContext context, TimeOfDay initial) async {
    final TimeOfDay? selectedTime = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    return selectedTime;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final keyboardSpace = MediaQuery.of(context).viewInsets.bottom;
    final title = widget.task == null ? "Add Task" : "Edit Task";
    final actionButtonText = widget.task == null ? "Save" : "Update";
    return SingleChildScrollView(
      child: Padding(
          padding: EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, keyboardSpace + Insets.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: Insets.md),
                  decoration: BoxDecoration(
                    color: t.textFaint.withAlpha(90),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: Insets.lg),
              Form(
                  key: _formKey, // Assign the form key
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: Insets.md),
                        TextFormField(
                          decoration: const InputDecoration(labelText: 'Description'),
                          controller: _description,
                          maxLines: null,
                          minLines: 3,
                          keyboardType: TextInputType.multiline,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: Insets.lg),
                        _sectionLabel('Schedule'),
                        _pickerField(
                          icon: FontAwesomeIcons.calendarDay,
                          label: 'Due date',
                          value: _dueDate,
                          placeholder: 'Set a due date',
                          onTap: () async {
                            final date = await _selectDate(context, initialDueDate!);
                            if (date == null) return;
                            setState(() => _dueDate = DateService().getString(date));
                          },
                          onClear: () => setState(() => _dueDate = null),
                        ),
                        if (_dueDate != null)
                          _pickerField(
                            icon: FontAwesomeIcons.clock,
                            label: 'Start time',
                            value: _startTime == null ? null : DateService().displayTime(_startTime!),
                            placeholder: 'Set a start time',
                            onTap: () async {
                              final initial = _startTime == null
                                  ? DateService().getRoundedTime(TimeOfDay.now())
                                  : DateService().getTime(_startTime!);
                              final time = await _selectTime(context, initial);
                              if (time == null) return;
                              setState(() {
                                DateTime tempDateTime = DateTime(2024, 1, 1, time.hour, time.minute);
                                _startTime = DateService().getTimeStr(tempDateTime);
                              });
                            },
                            onClear: () => setState(() {
                              _startTime = null;
                              _endTime = null;
                            }),
                          ),
                        if (_startTime != null)
                          _pickerField(
                            icon: FontAwesomeIcons.clock,
                            label: 'End time',
                            value: _endTime == null ? null : DateService().displayTime(_endTime!),
                            placeholder: 'Set an end time',
                            onTap: () async {
                              final initial = _endTime == null
                                  ? DateService().getRoundedTime(DateService().getTime(_startTime!))
                                  : DateService().getTime(_endTime!);
                              final time = await _selectTime(context, initial);
                              if (time == null) return;
                              // IF END TIME IS EARLIER THAN START TIME, ERROR?
                              setState(() {
                                DateTime tempDateTime = DateTime(2024, 1, 1, time.hour, time.minute);
                                _endTime = DateService().getTimeStr(tempDateTime);
                              });
                            },
                            onClear: () => setState(() => _endTime = null),
                          ),
                        const SizedBox(height: Insets.md),
                        _sectionLabel('Effort level'),
                        _effortSelector(),
                        const SizedBox(height: Insets.sm),
                        if (_dueDate == null && !widget.isBacklog)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                            child: Text('No due date — this goes to your backlog.',
                                style: theme.textTheme.bodySmall),
                          ),
                        if (_dueDate != null && widget.isBacklog)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                            child: Text('This will be scheduled on the selected date.',
                                style: theme.textTheme.bodySmall),
                          ),
                        Theme(
                          data: theme.copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: Insets.sm),
                            title: Text('Advanced', style: theme.textTheme.titleSmall),
                            initiallyExpanded: _isRecurring || _isMultiDay || _reminderTime != null || _countdown,
                            children: [
                              if (_dueDate != null && (widget.task == null || widget.task!.isMultiDay) && !_isRecurring)
                                _toggleRow(
                                  'Multi-day',
                                  _isMultiDay,
                                  widget.task?.isMultiDay == true
                                      ? null
                                      : (value) => setState(() {
                                            _isMultiDay = value;
                                            if (!_isMultiDay) _multiDayEndDate = null;
                                          }),
                                ),
                              if (_isMultiDay)
                                _pickerField(
                                  icon: FontAwesomeIcons.calendarWeek,
                                  label: 'End date',
                                  value: _multiDayEndDate,
                                  placeholder: 'Set end date',
                                  onTap: () async {
                                    final startStr = _multiDayStartDate ?? _dueDate!;
                                    final startDate = DateService().getDate(startStr);
                                    final initial = _multiDayEndDate != null
                                        ? DateService().getDate(_multiDayEndDate!)
                                        : startDate.add(const Duration(days: 1));
                                    final date = await _selectDate(context, initial);
                                    if (date == null || !date.isAfter(startDate)) return;
                                    setState(() => _multiDayEndDate = DateService().getString(date));
                                  },
                                  onClear: widget.task?.isMultiDay == true
                                      ? null
                                      : () => setState(() => _multiDayEndDate = null),
                                ),
                              if (_dueDate != null && widget.task?.recurringTemplateId == null && !_isMultiDay)
                                _toggleRow('Recurring', _isRecurring,
                                    (value) => setState(() => _isRecurring = value)),
                              if (_isRecurring)
                                RecurringTaskForm(
                                  key: _recurringTaskFormKey,
                                  startDate: _dueDate,
                                  onRecurringTaskChanged: (recurringTask) {
                                    setState(() {
                                      _recurringTaskTemplate = recurringTask;
                                    });
                                  },
                                ),
                              _toggleRow(
                                'Reminder',
                                _reminderEnabled,
                                (value) => setState(() {
                                  _reminderEnabled = value;
                                  if (!value) _reminderTime = null;
                                }),
                              ),
                              if (_reminderEnabled)
                                _pickerField(
                                  icon: FontAwesomeIcons.bell,
                                  label: 'Remind me at',
                                  value: _reminderTime != null ? _formatReminder(_reminderTime!) : null,
                                  placeholder: 'Set date & time',
                                  onTap: () async {
                                    final defaultDate =
                                        _dueDate != null ? DateService().getDate(_dueDate!) : DateTime.now();
                                    final date = await _selectDate(
                                        context,
                                        _reminderTime != null
                                            ? DateTime.parse(_reminderTime!).toLocal()
                                            : defaultDate);
                                    if (date == null) return;
                                    if (!context.mounted) return;
                                    final time = await _selectTime(
                                      context,
                                      _reminderTime != null
                                          ? TimeOfDay.fromDateTime(DateTime.parse(_reminderTime!).toLocal())
                                          : DateService().getRoundedTime(TimeOfDay.now()),
                                    );
                                    if (time == null) return;
                                    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                                    // Store as a UTC instant (with 'Z') so the backend resolves
                                    // the same absolute moment regardless of server timezone.
                                    setState(() => _reminderTime = dt.toUtc().toIso8601String());
                                  },
                                  onClear: () => setState(() => _reminderTime = null),
                                ),
                              if (_dueDate != null)
                                _toggleRow('Countdown', _countdown,
                                    (value) => setState(() => _countdown = value)),
                            ],
                          ),
                        ),
                        if (_allTags.isNotEmpty) ...[
                          const SizedBox(height: Insets.md),
                          _sectionLabel('Tags'),
                          MultiSelectDialogField(
                            isDismissible: true,
                            itemsTextStyle: TextStyle(color: theme.colorScheme.onSurface),
                            selectedColor: theme.colorScheme.primary,
                            selectedItemsTextStyle: TextStyle(color: theme.colorScheme.onPrimary),
                            backgroundColor: theme.colorScheme.surface,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Corners.md),
                              border: Border.all(color: t.hairline),
                            ),
                            items: _allTags.map((tag) => MultiSelectItem(tag.id, tag.label)).toList(),
                            listType: MultiSelectListType.CHIP,
                            initialValue: _selectedTags.map((t) => t.id).toList(), // NEED TO BE ID's
                            onConfirm: (result) => setState(() => _selectedTags =
                                result.map((id) => _allTags.firstWhere((tag) => id == tag.id)).toList()),
                            buttonIcon: Icon(FontAwesomeIcons.tag, size: 16, color: theme.colorScheme.primary),
                            buttonText: Text('Add tags', style: theme.textTheme.bodyLarge),
                          ),
                        ],
                      ])),
              const SizedBox(height: Insets.xl),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: apiPending ? null : () => _submit(),
                      child: apiPending
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(actionButtonText),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  SecondaryButton('Cancel', onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ],
          )),
    );
  }

  Widget _sectionLabel(String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.xs, bottom: Insets.sm),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.appTokens.textMuted,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _pickerField({
    required IconData icon,
    required String label,
    String? value,
    required String placeholder,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final hasValue = value != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Corners.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(Corners.md),
              border: Border.all(color: hasValue ? theme.colorScheme.primary.withAlpha(130) : t.hairline),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: hasValue ? theme.colorScheme.primary : t.textFaint),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint, letterSpacing: 1)),
                      const SizedBox(height: 1),
                      Text(hasValue ? value : placeholder,
                          style: theme.textTheme.bodyLarge?.copyWith(
                              color: hasValue ? theme.colorScheme.onSurface : t.textMuted)),
                    ],
                  ),
                ),
                if (onClear != null && hasValue)
                  InkWell(
                    onTap: onClear,
                    borderRadius: BorderRadius.circular(999),
                    child: Padding(
                      padding: const EdgeInsets.all(Insets.xs),
                      child: Icon(FontAwesomeIcons.xmark, size: 14, color: t.textFaint),
                    ),
                  )
                else
                  Icon(FontAwesomeIcons.chevronRight, size: 12, color: t.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _effortSelector() {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    String lbl(Effort e) => e.name[0].toUpperCase() + e.name.substring(1);
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      children: Effort.values.map((e) {
        final p = t.of(e);
        final selected = _priority == e;
        return ChoiceChip(
          label: Text(lbl(e)),
          selected: selected,
          showCheckmark: false,
          onSelected: (_) => setState(() => _priority = e),
          backgroundColor: theme.colorScheme.surface,
          selectedColor: p.fill,
          avatar: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
          ),
          side: BorderSide(color: selected ? p.accent : t.hairline, width: selected ? 1.5 : 1),
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: selected ? p.ink : t.textMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        );
      }).toList(),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool>? onChanged) {
    final theme = Theme.of(context);
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(label, style: theme.textTheme.bodyLarge),
      value: value,
      onChanged: onChanged,
    );
  }
}
