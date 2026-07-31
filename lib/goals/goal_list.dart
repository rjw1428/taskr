import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_detail_page.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class GoalListPage extends StatelessWidget {
  const GoalListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final goalService = GoalService();
    return StreamBuilder<List<Goal>>(
      stream: goalService.streamGoals(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final goals = snapshot.data ?? [];
        final activeGoals = goals.where((g) => g.status == GoalStatus.active).toList();
        final pausedGoals = goals.where((g) => g.status == GoalStatus.paused).toList();
        final completedGoals = goals.where((g) => g.status == GoalStatus.completed).toList();

        final theme = Theme.of(context);
        final t = theme.appTokens;

        if (activeGoals.isEmpty && pausedGoals.isEmpty && completedGoals.isEmpty) {
          return const EmptyState(
            icon: FontAwesomeIcons.bullseye,
            title: 'No goals yet',
            message: 'Tap + to set your first goal and start building towards something great.',
          );
        }

        return ListView(
          padding: const EdgeInsets.all(Insets.sm),
          children: [
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
