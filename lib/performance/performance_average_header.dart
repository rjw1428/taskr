import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/performance/performance_history.dart';
import 'package:taskr/performance/performance_range.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/services/date.service.dart';

class PerformanceAverageHeader extends StatelessWidget {
  final String userId;

  /// Index into [PerformanceRange.all]. Owned by the page, not this widget, so
  /// the charts below follow the same toggle.
  final int rangeIndex;
  final ValueChanged<int> onRangeChanged;
  const PerformanceAverageHeader({
    super.key,
    required this.userId,
    required this.rangeIndex,
    required this.onRangeChanged,
  });

  static DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final today = _dateKey(DateTime.now());
    final streamStart = DateService.shiftDays(today, -364);

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
        final windowDays = PerformanceRange.all[rangeIndex].days;
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
                segments: [
                  for (var i = 0; i < PerformanceRange.all.length; i++)
                    ButtonSegment(value: i, label: Text(PerformanceRange.all[i].label)),
                ],
                selected: {rangeIndex},
                showSelectedIcon: false,
                onSelectionChanged: (s) => onRangeChanged(s.first),
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
      final daysSinceOldest = DateService.daysBetween(oldest, today) + 1;
      effectiveDays = daysSinceOldest < 365 ? daysSinceOldest : 365;
    } else {
      effectiveDays = windowDays;
    }

    if (effectiveDays <= 0) return 0.0;

    final windowStart = DateService.shiftDays(today, -(effectiveDays - 1));
    int total = 0;
    scoresByDay.forEach((date, score) {
      if (!date.isBefore(windowStart) && !date.isAfter(today)) {
        total += score;
      }
    });

    return total / effectiveDays;
  }
}
