import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:taskr/performance/performance_history.dart';
import 'package:taskr/shared/shared.dart';

const int _weekCount = 13;
const double _cellSize = 14.0;
const double _cellSpacing = 4.0;

class PerformanceHeatmap extends StatefulWidget {
  final String userId;
  const PerformanceHeatmap({super.key, required this.userId});

  @override
  State<PerformanceHeatmap> createState() => _PerformanceHeatmapState();
}

class _PerformanceHeatmapState extends State<PerformanceHeatmap> {
  static DateTime _mondayOf(DateTime d) {
    final dateOnly = DateTime(d.year, d.month, d.day);
    return dateOnly.subtract(Duration(days: dateOnly.weekday - 1));
  }

  static DateTime _dateKey(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final windowStart = _mondayOf(today).subtract(const Duration(days: (_weekCount - 1) * 7));
    final windowEnd = windowStart.add(const Duration(days: _weekCount * 7 - 1));

    // Sliced from the page-wide history rather than streamed here: this
    // widget's own listener was rebuilt (and its 13 weeks re-read) every time
    // the page did.
    final history = context.watch<PerformanceHistory?>();
    final dailyScores = <DateTime, int>{};
    history?.scoresByDay(until: windowEnd).forEach((date, score) {
      if (!date.isBefore(windowStart)) dailyScores[date] = score;
    });

    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final t = theme.appTokens;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Consistency', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text('Daily points earned · last 13 weeks',
                style: theme.textTheme.bodySmall?.copyWith(color: t.textFaint)),
            const SizedBox(height: Insets.md),
            _MonthLabels(windowStart: windowStart, weekCount: _weekCount),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WeekdayLabels(),
                const SizedBox(width: 4),
                Expanded(
                  child: _Grid(
                    windowStart: windowStart,
                    today: _dateKey(today),
                    dailyScores: dailyScores,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            const _HeatLegend(),
          ],
        );
      },
    );
  }
}

class _Grid extends StatelessWidget {
  final DateTime windowStart;
  final DateTime today;
  final Map<DateTime, int> dailyScores;

  const _Grid({
    required this.windowStart,
    required this.today,
    required this.dailyScores,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cellSize = ((constraints.maxWidth - _cellSpacing * (_weekCount - 1)) / _weekCount)
            .clamp(8.0, _cellSize);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(_weekCount, (weekIndex) {
            final weekMonday = windowStart.add(Duration(days: weekIndex * 7));
            return Column(
              children: List.generate(7, (dayIndex) {
                final cellDate = weekMonday.add(Duration(days: dayIndex));
                final isFuture = cellDate.isAfter(today);
                return Padding(
                  padding: EdgeInsets.only(bottom: dayIndex < 6 ? _cellSpacing : 0),
                  child: isFuture
                      ? SizedBox(width: cellSize, height: cellSize)
                      : _Cell(
                          size: cellSize,
                          score: dailyScores[cellDate] ?? 0,
                        ),
                );
              }),
            );
          }),
        );
      },
    );
  }
}

class _Cell extends StatelessWidget {
  final double size;
  final int score;

  const _Cell({required this.size, required this.score});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorForScore(theme, score),
        borderRadius: BorderRadius.circular(3.0),
        border: score > 10 ? Border.all(color: t.goal, width: 1.5) : null,
      ),
    );
  }

  static Color _colorForScore(ThemeData theme, int score) {
    final t = theme.appTokens;
    if (score == 0) return t.surfaceRaised;
    final level = score < 2
        ? 0.25
        : score < 5
            ? 0.5
            : score < 8
                ? 0.75
                : 1.0;
    return Color.lerp(theme.colorScheme.surface, theme.colorScheme.primary, level)!;
  }
}

class _HeatLegend extends StatelessWidget {
  const _HeatLegend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = theme.appTokens;
    const levels = [0.0, 0.25, 0.5, 0.75, 1.0];
    Color colorFor(double l) =>
        l == 0 ? t.surfaceRaised : Color.lerp(theme.colorScheme.surface, theme.colorScheme.primary, l)!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint)),
        const SizedBox(width: 6),
        ...levels.map((l) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(color: colorFor(l), borderRadius: BorderRadius.circular(3)),
              ),
            )),
        const SizedBox(width: 6),
        Text('More', style: theme.textTheme.labelSmall?.copyWith(color: t.textFaint)),
      ],
    );
  }
}

class _WeekdayLabels extends StatelessWidget {
  static const _labels = ['M', '', 'W', '', 'F', '', ''];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).appTokens;
    return Column(
      children: List.generate(7, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < 6 ? _cellSpacing : 0),
          child: SizedBox(
            width: 10,
            height: _cellSize,
            child: Text(
              _labels[i],
              style: TextStyle(fontSize: 9, color: t.textFaint),
              textAlign: TextAlign.center,
            ),
          ),
        );
      }),
    );
  }
}

class _MonthLabels extends StatelessWidget {
  final DateTime windowStart;
  final int weekCount;

  const _MonthLabels({required this.windowStart, required this.weekCount});

  static const _monthAbbr = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).appTokens;
    final labels = <String>[];
    int? prevMonth;
    for (int i = 0; i < weekCount; i++) {
      final weekMonday = windowStart.add(Duration(days: i * 7));
      if (prevMonth == null || weekMonday.month != prevMonth) {
        labels.add(_monthAbbr[weekMonday.month]);
        prevMonth = weekMonday.month;
      } else {
        labels.add('');
      }
    }

    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Row(
        children: labels
            .map((label) => Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 10, color: t.textFaint, fontWeight: FontWeight.w500),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
