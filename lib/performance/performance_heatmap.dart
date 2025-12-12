import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/error.dart';

class PerformanceHeatmap extends StatefulWidget {
  final String userId;
  const PerformanceHeatmap({super.key, required this.userId});

  @override
  State<PerformanceHeatmap> createState() => _PerformanceHeatmapState();
}

class _PerformanceHeatmapState extends State<PerformanceHeatmap> {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final lastDayOfMonth = DateTime(now.year, now.month + 1, 0); // Last day of current month

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: PerformanceService().streamPerformanceForMonth(
        widget.userId,
        firstDayOfMonth,
        lastDayOfMonth,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // return const LoadingScreen();
          debugPrint('Loading performance data...');
        } else if (snapshot.hasError) {
          debugPrint(snapshot.error.toString());
          return const ErrorMessage();
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No performance data for this month.'));
        }
        final dailyData = snapshot.data ?? [];
        final Map<int, int> dailyScores = {};
        for (var data in dailyData) {
          final timestamp = data['date'] as Timestamp;
          final date = timestamp.toDate();
          final score = data['completed']['ALL'] as int? ?? 0;
          dailyScores[date.day] = score;
        }

        final daysInMonth = lastDayOfMonth.day;
        final firstDayWeekday = firstDayOfMonth.weekday; // 1 for Monday, 7 for Sunday

        // Adjust firstDayWeekday to be 0 for Monday, 6 for Sunday
        final adjustedFirstDayWeekday = (firstDayWeekday - 1 + 7) % 7;

        final totalCells = daysInMonth + adjustedFirstDayWeekday;
        final numberOfWeeks = (totalCells / 7).ceil();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              // Day of week headers
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (index) {
                  return Expanded(
                    child: Text(
                      DateService().getDayOfWeekByIndex(index),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  );
                }),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, // 7 days a week
                  childAspectRatio: 1.0,
                  crossAxisSpacing: 4.0,
                  mainAxisSpacing: 4.0,
                  mainAxisExtent: 14.0, // Adjust height to fit text
                ),
                itemCount: numberOfWeeks * 7, // Total cells in the grid
                itemBuilder: (context, index) {
                  final dayOfWeekIndex = index % 7; // 0 for Monday, 6 for Sunday
                  final weekIndex = index ~/ 7;

                  final dayOfMonth = (weekIndex * 7) + dayOfWeekIndex - adjustedFirstDayWeekday + 1;

                  if (dayOfMonth < 1 || dayOfMonth > daysInMonth) {
                    // Empty cells before the first day and after the last day of the month
                    return Container();
                  }

                  final score = dailyScores[dayOfMonth] ?? 0;
                  final color = _getColorForScore(score);

                  return Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4.0),
                      border: score > 10 ? Border.all(color: Colors.yellow, width: 2.0) : null,
                    ),
                    child: Center(
                      child: Text(
                        '$dayOfMonth',
                        style: TextStyle(
                          color: score > 0 ? Colors.white : Colors.black,
                          fontSize: 8.0,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getColorForScore(int score) {
    if (score == 0) {
      return Colors.grey[200]!;
    } else if (score < 2) {
      return Colors.green[100]!;
    } else if (score < 5) {
      return Colors.green[300]!;
    } else if (score < 8) {
      return Colors.green[500]!;
    } else {
      return Colors.green[700]!;
    }
  }
}
