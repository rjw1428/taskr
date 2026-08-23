import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';
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

  // Shown when the series template no longer exists (e.g. a series that was only
  // partially deleted by an older version of the app, leaving orphaned occurrences).
  // The series definition is gone, so we can't act on the whole series, but the user
  // can still clear each leftover occurrence from here.
  Widget _buildOrphanedSeries(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.link_off, size: 48),
          const SizedBox(height: 16),
          const Text(
            'This recurring series no longer has a template. It was likely deleted '
            'earlier, leaving a few leftover occurrences behind.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'You can remove this occurrence here, then repeat for any others that '
            'are still showing up.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Insets.xl),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () async {
              await _taskService.deleteTask(widget.task);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Occurrence deleted')),
                );
                Navigator.of(context).pop();
              }
            },
            child: const Text('Delete This Occurrence'),
          ),
        ],
      ),
    );
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
            return _buildOrphanedSeries(context);
          } else if (snapshot.hasData) {
            _recurringTask ??= snapshot.data;
            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    RecurringTaskForm(
                      key: _recurringTaskFormKey,
                      showReminder: true,
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
                            backgroundColor: Theme.of(context).colorScheme.error,
                            foregroundColor: Theme.of(context).colorScheme.onError,
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
