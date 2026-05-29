import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/error.dart';

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

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PerformanceService().streamPerformanceForMonth(
        widget.userId,
        windowStart,
        windowEnd,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(snapshot.error.toString());
          return const ErrorMessage();
        }

        final dailyScores = <DateTime, int>{};
        final docs = snapshot.data ?? const <Map<String, dynamic>>[];
        for (final data in docs) {
          final ts = data['date'] as Timestamp?;
          if (ts == null) continue;
          final completed = data['completed'] as Map<String, dynamic>?;
          final score = (completed?['ALL'] as int?) ?? 0;
          dailyScores[_dateKey(ts.toDate())] = score;
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
            ],
          ),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _colorForScore(score),
        borderRadius: BorderRadius.circular(3.0),
        border: score > 10 ? Border.all(color: Colors.yellow, width: 1.5) : null,
      ),
    );
  }

  static Color _colorForScore(int score) {
    if (score == 0) return Colors.grey[200]!;
    if (score < 2) return Colors.green[100]!;
    if (score < 5) return Colors.green[300]!;
    if (score < 8) return Colors.green[500]!;
    return Colors.green[700]!;
  }
}

class _WeekdayLabels extends StatelessWidget {
  static const _labels = ['M', '', 'W', '', 'F', '', ''];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(7, (i) {
        return Padding(
          padding: EdgeInsets.only(bottom: i < 6 ? _cellSpacing : 0),
          child: SizedBox(
            width: 10,
            height: _cellSize,
            child: Text(
              _labels[i],
              style: const TextStyle(fontSize: 9, color: Colors.grey),
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
                    style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500),
                  ),
                ))
            .toList(),
      ),
    );
  }
}
