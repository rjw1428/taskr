import 'package:flutter/material.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class GoalForm extends StatefulWidget {
  final Goal? goal;
  const GoalForm({super.key, this.goal});

  @override
  State<GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends State<GoalForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _frequencyCount = TextEditingController(text: '3');
  GoalTimeframe _timeframe = GoalTimeframe.oneMonth;
  GoalFrequency _frequency = GoalFrequency.daily;
  bool _apiPending = false;

  @override
  void initState() {
    super.initState();
    if (widget.goal != null) {
      _title.text = widget.goal!.title;
      _description.text = widget.goal!.description ?? '';
      _timeframe = widget.goal!.timeframe;
      _frequency = widget.goal!.frequency;
      if (widget.goal!.frequencyCount != null) {
        _frequencyCount.text = widget.goal!.frequencyCount.toString();
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _frequencyCount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _apiPending = true);

    try {
      final goalService = GoalService();
      final now = DateTime.now();
      final startDate = DateService().getString(now);
      final int? freqCount =
          _frequency == GoalFrequency.nTimesWeek ? int.tryParse(_frequencyCount.text) : null;

      if (widget.goal == null) {
        final endDate = Goal.computeEndDate(startDate, _timeframe);
        final goal = Goal(
          title: _title.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          timeframe: _timeframe,
          frequency: _frequency,
          frequencyCount: freqCount,
          startDate: startDate,
          endDate: endDate,
          createdAt: now.millisecondsSinceEpoch,
          modifiedAt: now.millisecondsSinceEpoch,
        );
        final goalId = await goalService.addGoal(goal);
        goal.id = goalId;

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Goal created! Generating tasks...')),
          );
        }

        try {
          await goalService.generateTasksForGoal(goal);
        } catch (e, s) {
          reportError(e, s, "Couldn't generate tasks for the goal");
        }
      } else {
        final endDate = Goal.computeEndDate(widget.goal!.startDate, _timeframe);
        final updated = widget.goal!.copyWith(
          title: _title.text.trim(),
          description: _description.text.trim().isEmpty ? null : _description.text.trim(),
          timeframe: _timeframe,
          frequency: _frequency,
          frequencyCount: freqCount,
          endDate: endDate,
          modifiedAt: now.millisecondsSinceEpoch,
        );
        await goalService.updateGoal(updated);

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Goal updated')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving goal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _apiPending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardSpace = MediaQuery.of(context).viewInsets.bottom;
    final isEdit = widget.goal != null;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, keyboardSpace + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'Edit Goal' : 'New Goal',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What do you want to achieve?',
                      hintText: 'e.g. Learn the piano, Be a better friend',
                    ),
                    controller: _title,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your goal';
                      }
                      return null;
                    },
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      hintText: 'Any details to help focus your tasks',
                    ),
                    controller: _description,
                    maxLines: null,
                    minLines: 2,
                    keyboardType: TextInputType.multiline,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 20),
                  Text('Timeframe', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<GoalTimeframe>(
                    segments: const [
                      ButtonSegment(value: GoalTimeframe.oneWeek, label: Text('1W')),
                      ButtonSegment(value: GoalTimeframe.oneMonth, label: Text('1M')),
                      ButtonSegment(value: GoalTimeframe.threeMonths, label: Text('3M')),
                      ButtonSegment(value: GoalTimeframe.sixMonths, label: Text('6M')),
                      ButtonSegment(value: GoalTimeframe.oneYear, label: Text('1Y')),
                    ],
                    selected: {_timeframe},
                    onSelectionChanged: (set) => setState(() => _timeframe = set.first),
                  ),
                  const SizedBox(height: 20),
                  Text('Frequency', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<GoalFrequency>(
                    segments: const [
                      ButtonSegment(value: GoalFrequency.daily, label: Text('Daily')),
                      ButtonSegment(value: GoalFrequency.nTimesWeek, label: Text('N/Week')),
                      ButtonSegment(value: GoalFrequency.auto, label: Text('Auto')),
                    ],
                    selected: {_frequency},
                    onSelectionChanged: (set) => setState(() => _frequency = set.first),
                  ),
                  if (_frequency == GoalFrequency.nTimesWeek) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        controller: _frequencyCount,
                        decoration: const InputDecoration(labelText: 'Times per week'),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        validator: (value) {
                          if (_frequency != GoalFrequency.nTimesWeek) return null;
                          final n = int.tryParse(value ?? '');
                          if (n == null || n < 1 || n > 7) return '1-7';
                          return null;
                        },
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Insets.xl),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(
                  onPressed: _apiPending ? null : _submit,
                  child: _apiPending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isEdit ? 'Update' : 'Create Goal'),
                ),
                const SizedBox(width: Insets.md),
                SecondaryButton('Close', onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
