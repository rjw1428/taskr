import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_detail_page.dart';
import 'package:taskr/goals/habit_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class GoalListPage extends StatelessWidget {
  const GoalListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final goalService = GoalService();
    final habitService = HabitService();
    return StreamBuilder<List<Habit>>(
      stream: habitService.streamHabits(),
      builder: (context, habitSnap) {
        final habits = habitSnap.data ?? const <Habit>[];
        // Keep upcoming habit instances materialized (rolling top-up).
        for (final h in habits) {
          if (h.status == 'active') habitService.ensureInstances(h);
        }
        return StreamBuilder<List<Goal>>(
          stream: goalService.streamGoals(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting && !habitSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final goals = snapshot.data ?? [];
            final activeGoals = goals.where((g) => g.status == GoalStatus.active).toList();
            final pausedGoals = goals.where((g) => g.status == GoalStatus.paused).toList();
            final completedGoals = goals.where((g) => g.status == GoalStatus.completed).toList();

            final theme = Theme.of(context);
            final t = theme.appTokens;

            if (habits.isEmpty &&
                activeGoals.isEmpty &&
                pausedGoals.isEmpty &&
                completedGoals.isEmpty) {
              return const EmptyState(
                icon: FontAwesomeIcons.bullseye,
                title: 'No goals or habits yet',
                message: 'Tap + to set a goal or start a habit.',
              );
            }

            return ListView(
              padding: const EdgeInsets.all(Insets.sm),
              children: [
                if (habits.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.xs),
                    child: Text('Habits',
                        style: theme.textTheme.titleMedium?.copyWith(color: t.goal)),
                  ),
                  ...habits.asMap().entries.map((e) => AppReveal(
                        delay: staggerDelay(e.key),
                        child: _HabitCard(habit: e.value),
                      )),
                  const SizedBox(height: Insets.lg),
                ],
                if (activeGoals.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.xs),
                child: Text('Active Goals',
                    style: theme.textTheme.titleMedium?.copyWith(color: t.goal)),
              ),
              ...activeGoals.asMap().entries.map((e) => AppReveal(
                    delay: staggerDelay(e.key),
                    child: _GoalCard(goal: e.value),
                  )),
            ],
            if (pausedGoals.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.xs),
                child: Text('Paused',
                    style: theme.textTheme.titleMedium?.copyWith(color: t.textMuted)),
              ),
              ...pausedGoals.asMap().entries.map((e) => AppReveal(
                    delay: staggerDelay(e.key),
                    child: _GoalCard(goal: e.value),
                  )),
            ],
            if (completedGoals.isNotEmpty) ...[
              const SizedBox(height: Insets.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: Insets.xs),
                child: Text('Completed',
                    style: theme.textTheme.titleMedium?.copyWith(color: t.textFaint)),
              ),
              ...completedGoals.asMap().entries.map((e) => AppReveal(
                    delay: staggerDelay(e.key),
                    child: _GoalCard(goal: e.value),
                  )),
            ],
              ],
            );
          },
        );
      },
    );
  }
}

class _HabitCard extends StatelessWidget {
  final Habit habit;
  const _HabitCard({required this.habit});

  String _cadenceLabel() {
    switch (habit.recurrenceType) {
      case 'Weekly':
        final days = (habit.daysOfWeek ?? {}).entries.where((e) => e.value).map((e) => e.key).toList();
        return days.isEmpty ? 'Weekly' : days.join(' ');
      case 'Monthly':
        return 'Monthly · day ${habit.dayOfMonth ?? 1}';
      case 'Yearly':
        return 'Yearly';
      default:
        return 'Daily';
    }
  }

  void _openEdit(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => HabitForm(habit: habit)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final paused = habit.status == 'paused';
    final streak = habit.currentStreak;
    return Card(
      color: theme.colorScheme.surface,
      margin: const EdgeInsets.symmetric(horizontal: Insets.xs, vertical: Insets.xs),
      child: ListTile(
        leading: Icon(FontAwesomeIcons.fire, color: (!paused && streak > 0) ? t.goal : t.textFaint),
        title: Text(habit.title, style: theme.textTheme.titleSmall),
        subtitle: Text('${_cadenceLabel()}${paused ? " · paused" : ""}',
            style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!paused)
              Text('$streak',
                  style: theme.textTheme.titleMedium?.copyWith(color: t.goal, fontWeight: FontWeight.w800)),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  _openEdit(context);
                } else if (v == 'pause') {
                  await HabitService().pauseHabit(habit);
                } else if (v == 'resume') {
                  await HabitService().resumeHabit(habit);
                } else if (v == 'delete') {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text('Delete "${habit.title}"?'),
                      content: const Text('Future occurrences are removed; completed history stays.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text('Delete', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await HabitService().deleteHabit(habit);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (paused)
                  const PopupMenuItem(value: 'resume', child: Text('Resume'))
                else
                  const PopupMenuItem(value: 'pause', child: Text('Pause')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
        onTap: () => _openEdit(context),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  const _GoalCard({required this.goal});

  String _timeRemaining() {
    final end = DateTime.parse(goal.endDate);
    final now = DateTime.now();
    final diff = end.difference(now);
    if (diff.isNegative) return 'Expired';
    if (diff.inDays > 30) return '${(diff.inDays / 30).round()} months left';
    if (diff.inDays > 7) return '${(diff.inDays / 7).round()} weeks left';
    if (diff.inDays > 0) return '${diff.inDays} days left';
    return 'Last day';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final isCompleted = goal.status == GoalStatus.completed;
    final isPaused = goal.status == GoalStatus.paused;
    return Card(
      color: theme.colorScheme.surface,
      margin: const EdgeInsets.symmetric(horizontal: Insets.xs, vertical: Insets.xs),
      child: ListTile(
        leading: Icon(
          isCompleted
              ? FontAwesomeIcons.circleCheck
              : isPaused
                  ? FontAwesomeIcons.pause
                  : FontAwesomeIcons.bullseye,
          color: isCompleted
              ? t.of(Effort.low).accent
              : isPaused
                  ? t.of(Effort.info).accent
                  : t.goal,
        ),
        title: Text(
          goal.title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          isPaused
              ? '${goal.frequencyLabel} · Paused'
              : '${goal.frequencyLabel} · ${_timeRemaining()}',
          style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted),
        ),
        trailing: Icon(FontAwesomeIcons.chevronRight, size: 14, color: t.textFaint),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => GoalDetailPage(goalId: goal.id!)),
          );
        },
      ),
    );
  }
}
