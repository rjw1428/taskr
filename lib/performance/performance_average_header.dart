import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/services.dart';

const _windows = [7, 30, 90, 365];
const _labels = ['Last 7 days', 'Last month', 'Last 3 months', 'Last year'];

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
    final today = _dateKey(DateTime.now());
    final streamStart = today.subtract(const Duration(days: 364));

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PerformanceService().streamPerformanceForMonth(
        widget.userId,
        streamStart,
        today,
      ),
      builder: (context, snapshot) {
        final scoresByDay = <DateTime, int>{};
        final docs = snapshot.data ?? const <Map<String, dynamic>>[];
        for (final data in docs) {
          final ts = data['date'] as Timestamp?;
          if (ts == null) continue;
          final completed = data['completed'] as Map<String, dynamic>?;
          final score = (completed?['ALL'] as int?) ?? 0;
          scoresByDay[_dateKey(ts.toDate())] = score;
        }

        final windowDays = _windows[_windowIndex];
        final label = _labels[_windowIndex];
        final average = _averageFor(windowDays, scoresByDay, today);

        return InkWell(
          onTap: () {
            setState(() {
              _windowIndex = (_windowIndex + 1) % _windows.length;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      average.toStringAsFixed(2),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'avg points · $label',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.swap_horiz, size: 14, color: Colors.grey),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
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
