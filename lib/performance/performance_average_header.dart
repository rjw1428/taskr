import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/performance/performance_history.dart';
import 'package:taskr/shared/shared.dart';

const _windows = [7, 30, 90, 365];

class PerformanceAverageHeader extends StatefulWidget {
  final String userId;
  const PerformanceAverageHeader({super.key, required this.userId});

  @override
  State<PerformanceAverageHeader> createState() => _PerformanceAverageHeaderState();
}

class _PerformanceAverageHeaderState extends State<PerformanceAverageHeader> {
  int _windowIndex = 0;

  static DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final today = _dateKey(DateTime.now());
    final streamStart = today.subtract(const Duration(days: 364));

    // Sliced from the page-wide history (which starts at the same day) rather
    // than streamed here: this widget's own year-long listener was rebuilt and
    // re-read every time the page did.
    final history = context.watch<PerformanceHistory?>();
    final scoresByDay = <DateTime, int>{};
    history?.scoresByDay(until: today).forEach((date, score) {
      if (!date.isBefore(streamStart)) scoresByDay[date] = score;
    });

    return Builder(
      builder: (context) {
        final windowDays = _windows[_windowIndex];
        final average = _averageFor(windowDays, scoresByDay, today);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('THIS PERIOD',
                style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint, letterSpacing: 1.4)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  average.toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('avg points / day',
                      style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted)),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('7d')),
                  ButtonSegment(value: 1, label: Text('30d')),
                  ButtonSegment(value: 2, label: Text('90d')),
                  ButtonSegment(value: 3, label: Text('1y')),
                ],
                selected: {_windowIndex},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _windowIndex = s.first),
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _averageFor(int windowDays, Map<DateTime, int> scoresByDay, DateTime today) {
    int effectiveDays;
    if (windowDays == 365) {
      if (scoresByDay.isEmpty) return 0.0;
      final oldest = scoresByDay.keys.reduce((a, b) => a.isBefore(b) ? a : b);
      final daysSinceOldest = today.difference(oldest).inDays + 1;
      effectiveDays = daysSinceOldest < 365 ? daysSinceOldest : 365;
    } else {
      effectiveDays = windowDays;
    }

    if (effectiveDays <= 0) return 0.0;

    final windowStart = today.subtract(Duration(days: effectiveDays - 1));
    int total = 0;
    scoresByDay.forEach((date, score) {
      if (!date.isBefore(windowStart) && !date.isAfter(today)) {
        total += score;
      }
    });

    return total / effectiveDays;
  }
}
