import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/recurring_task_form.dart';

class ViewSeries extends StatefulWidget {
  final Task task;
  const ViewSeries({super.key, required this.task});

  @override
  State<ViewSeries> createState() => _ViewSeriesState();
}

class _ViewSeriesState extends State<ViewSeries> {
  final _recurringTaskFormKey = GlobalKey<RecurringTaskFormState>();
  final _taskService = TaskService();
  late Future<RecurringTask> _recurringTaskFuture;
  RecurringTask? _recurringTask;

  @override
  void initState() {
    super.initState();
    _recurringTaskFuture = _taskService.getRecurringTemplate(widget.task.recurringTemplateId!);
  }

  Future<void> _update() async {
    final recurringValidationError = _recurringTaskFormKey.currentState?.validate();
    if (recurringValidationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(recurringValidationError),
        ),
      );
      return;
    }

    if (_recurringTask != null) {
      await _taskService.updateRecurringTemplate(widget.task, _recurringTask!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recurring task updated'),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Series'),
        content: const Text(
            'Are you sure you want to delete this recurring task series? This will also delete all future tasks in this series.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && _recurringTask != null) {
      await _taskService.deleteRecurringTemplate(widget.task, _recurringTask!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recurring task series deleted'),
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('View Recurring Task'),
      ),
      body: FutureBuilder<RecurringTask>(
        future: _recurringTaskFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (snapshot.hasData) {
            _recurringTask ??= snapshot.data;
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    RecurringTaskForm(
                      key: _recurringTaskFormKey,
                      startDate: DateService().getString(snapshot.data!.startDate!),
                      recurringTask: snapshot.data,
                      onRecurringTaskChanged: (recurringTask) {
                        setState(() {
                          _recurringTask = recurringTask;
                        });
                      },
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _update,
                          child: const Text('Update'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed: _delete,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('Delete Series'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          } else {
            return const Center(child: Text('No recurring task found.'));
          }
        },
      ),
    );
  }
}
