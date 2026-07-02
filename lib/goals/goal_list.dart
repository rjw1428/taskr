import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_detail_page.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';

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

        if (activeGoals.isEmpty && pausedGoals.isEmpty && completedGoals.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(FontAwesomeIcons.bullseye, size: 48, color: Colors.orange),
                  const SizedBox(height: 16),
                  Text(
                    'No goals yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to set your first goal and start building towards something great.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(8),
          children: [
            if (activeGoals.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Active Goals',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.orange)),
              ),
              ...activeGoals.map((goal) => _GoalCard(goal: goal)),
            ],
            if (pausedGoals.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Paused',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.blueGrey)),
              ),
              ...pausedGoals.map((goal) => _GoalCard(goal: goal)),
            ],
            if (completedGoals.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text('Completed',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
              ),
              ...completedGoals.map((goal) => _GoalCard(goal: goal)),
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
    final isCompleted = goal.status == GoalStatus.completed;
    final isPaused = goal.status == GoalStatus.paused;
    return Card(
      color: isCompleted ? Colors.grey.shade900 : Colors.black87,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ListTile(
        leading: Icon(
          isCompleted
              ? FontAwesomeIcons.circleCheck
              : isPaused
                  ? FontAwesomeIcons.pause
                  : FontAwesomeIcons.bullseye,
          color: isCompleted
              ? Colors.green
              : isPaused
                  ? Colors.blueGrey
                  : Colors.orange,
        ),
        title: Text(
          goal.title,
          style: TextStyle(
            color: Colors.white,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          isPaused
              ? '${goal.frequencyLabel} · Paused'
              : '${goal.frequencyLabel} · ${_timeRemaining()}',
          style: const TextStyle(color: Colors.grey),
        ),
        trailing: const Icon(FontAwesomeIcons.chevronRight, size: 14, color: Colors.grey),
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
