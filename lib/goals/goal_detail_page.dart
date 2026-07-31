import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class GoalDetailPage extends StatefulWidget {
  final String goalId;
  const GoalDetailPage({super.key, required this.goalId});

  @override
  State<GoalDetailPage> createState() => _GoalDetailPageState();
}

class _GoalDetailPageState extends State<GoalDetailPage> {
  final _goalService = GoalService();
  Goal? _goal;
  Map<String, int> _stats = {};
  bool _loading = true;
  bool _regenerating = false;

  @override
  void initState() {
    super.initState();
    _loadGoal();
  }

  Future<void> _loadGoal() async {
    final goal = await _goalService.getGoal(widget.goalId);
    if (goal == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    if (goal.status == GoalStatus.active && DateTime.parse(goal.endDate).isBefore(DateTime.now())) {
      goal.status = GoalStatus.completed;
      await _goalService.updateGoal(goal);
    }

    final stats = await _goalService.getGoalStats(widget.goalId);
    if (mounted) {
      setState(() {
        _goal = goal;
        _stats = stats;
        _loading = false;
      });
    }
  }

  Future<void> _regenerate() async {
    if (_goal == null) return;
    setState(() => _regenerating = true);
    try {
      await _goalService.generateTasksForGoal(_goal!, isRegeneration: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tasks regenerated!')),
        );
        _loadGoal();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Regeneration failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  Future<void> _togglePause() async {
    if (_goal == null) return;
    final goal = _goal!;
    final pausing = goal.status == GoalStatus.active;
    if (pausing) {
      await _goalService.pauseGoal(goal);
    } else {
      await _goalService.resumeGoal(goal);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(pausing
            ? 'Goal paused — no new tasks will be generated'
            : 'Goal resumed')),
      );
      _loadGoal();
    }
  }

  Future<void> _deleteGoal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Goal'),
        content: const Text('This will delete the goal and all its future uncompleted tasks. Completed tasks will be preserved.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || _goal == null) return;

    await _goalService.deleteGoal(_goal!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Goal deleted')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Goal')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final theme = Theme.of(context);
    final t = theme.appTokens;
    final goal = _goal!;
    final isCompleted = goal.status == GoalStatus.completed;
    final isDeleted = goal.status == GoalStatus.deleted;
    final isPaused = goal.status == GoalStatus.paused;
    final totalTasks = _stats['totalTasks'] ?? 0;
    final completedTasks = _stats['completedTasks'] ?? 0;
    final weeksActive = _stats['weeksActive'] ?? 0;
    final completionRate = totalTasks > 0 ? (completedTasks / totalTasks * 100).round() : 0;

    final end = DateTime.parse(goal.endDate);
    final start = DateTime.parse(goal.startDate);
    final now = DateTime.now();
    final totalDays = end.difference(start).inDays;
    final elapsedDays = now.difference(start).inDays;
    final progress = totalDays > 0 ? (elapsedDays / totalDays).clamp(0.0, 1.0) : 1.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(goal.title),
        actions: [
          if (!isDeleted) ...[
            if (!isCompleted)
              IconButton(
                icon: Icon(isPaused ? FontAwesomeIcons.play : FontAwesomeIcons.pause),
                tooltip: isPaused ? 'Resume goal' : 'Pause goal',
                onPressed: _togglePause,
              ),
            IconButton(
              icon: const Icon(FontAwesomeIcons.penToSquare),
              onPressed: () async {
                await showModalBottomSheet(
                  isScrollControlled: true,
                  useSafeArea: true,
                  context: context,
                  builder: (_) => GoalForm(goal: goal),
                );
                _loadGoal();
              },
            ),
            IconButton(
              icon: Icon(FontAwesomeIcons.trashCan, color: theme.colorScheme.error),
              onPressed: _deleteGoal,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCompleted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Insets.md),
                margin: const EdgeInsets.only(bottom: Insets.lg),
                decoration: BoxDecoration(
                  color: t.of(Effort.low).fill,
                  borderRadius: BorderRadius.circular(Corners.sm),
                  border: Border.all(color: t.of(Effort.low).border),
                ),
                child: Column(
                  children: [
                    Icon(FontAwesomeIcons.trophy, color: t.of(Effort.low).accent, size: 32),
                    const SizedBox(height: Insets.sm),
                    Text('Goal Complete!', style: theme.textTheme.titleMedium?.copyWith(color: t.of(Effort.low).ink)),
                    const SizedBox(height: Insets.xs),
                    Text('$completedTasks of $totalTasks tasks completed over $weeksActive weeks ($completionRate%)',
                        style: theme.textTheme.bodySmall?.copyWith(color: t.of(Effort.low).ink)),
                  ],
                ),
              ),

            if (isPaused)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Insets.md),
                margin: const EdgeInsets.only(bottom: Insets.lg),
                decoration: BoxDecoration(
                  color: t.of(Effort.info).fill,
                  borderRadius: BorderRadius.circular(Corners.sm),
                  border: Border.all(color: t.of(Effort.info).border),
                ),
                child: Row(
                  children: [
                    Icon(FontAwesomeIcons.pause, color: t.of(Effort.info).accent, size: 20),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Text(
                        'Goal paused — no new tasks will be generated until you resume.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: t.of(Effort.info).ink),
                      ),
                    ),
                  ],
                ),
              ),

            if (goal.description != null && goal.description!.isNotEmpty) ...[
              Text(goal.description!, style: theme.textTheme.bodyLarge?.copyWith(color: t.textMuted)),
              const SizedBox(height: Insets.lg),
            ],

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Timeframe', goal.timeframeLabel),
                  _infoRow('Frequency', goal.frequencyLabel),
                  _infoRow('Started', goal.startDate),
                  _infoRow('Ends', goal.endDate),
                  const SizedBox(height: Insets.sm),
                  if (!isCompleted && !isDeleted) ...[
                    Text('Time Progress', style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted)),
                    const SizedBox(height: Insets.xs),
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: t.hairline,
                      valueColor: AlwaysStoppedAnimation<Color>(t.goal),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Insets.lg),

            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Progress', style: theme.textTheme.titleSmall),
                  const SizedBox(height: Insets.md),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _statWidget('Weeks', '$weeksActive'),
                      _statWidget('Tasks Done', '$completedTasks/$totalTasks'),
                      _statWidget('Rate', '$completionRate%'),
                    ],
                  ),
                ],
              ),
            ),

            if (!isCompleted && !isDeleted && !isPaused) ...[
              const SizedBox(height: Insets.xl),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _regenerating ? null : _regenerate,
                  icon: _regenerating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(FontAwesomeIcons.arrowsRotate),
                  label: const Text('Regenerate This Week\'s Tasks'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: t.textMuted)),
          Text(value, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }

  Widget _statWidget(String label, String value) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: t.goal)),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: t.textMuted)),
      ],
    );
  }
}
