import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/services.dart';
import '../shared/shared.dart';
import 'package:fl_chart/fl_chart.dart';

class PerformancePage extends StatelessWidget {
  const PerformancePage({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: AuthService().userStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        } else if (snapshot.hasError) {
          return const Center(
            child: ErrorMessage(),
          );
        } else if (snapshot.hasData) {
          // Will be null if user is not logged in
          return CurrentScore(userId: snapshot.data!.uid);
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

class CurrentScore extends StatelessWidget {
  final String userId;
  const CurrentScore({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
        stream: CombineLatestStream.combine2(
            PerformanceService().streamPerformance(userId),
            TagService().streamTags(userId),
            (currentPerformance, tags) => [currentPerformance, tags]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen(message: 'Loading Tasks...');
          }

          if (snapshot.hasError) {
            print(snapshot.error);
            return const Text("ERROR");
          }
          final performace = snapshot.data![0]; //as Map<String, List<Map<String, int>>>;
          final score = performace['currentScore']!;
          final week = performace['currentWeek']!;
          final day = performace['currentDay']!;
          final tags = snapshot.data![1];
          return Scaffold(
              appBar: AppBar(
                title: const Text('Performance'),
                actions: [
                  IconButton(
                      onPressed: () => AuthService().signOut(),
                      icon: const Icon(FontAwesomeIcons.userAstronaut))
                ],
              ),
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Performance things go here: ${score.toString()}'),
                  Expanded(
                      child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (touchedSpot) => Colors.blueGrey.withOpacity(0.8),
                        ),
                      ),
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 32,
                            interval: 1,
                            getTitlesWidget: bottomTitleWidgets,
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            getTitlesWidget: leftTitleWidgets,
                            showTitles: true,
                            interval: 1,
                            reservedSize: 40,
                          ),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: const Border(
                          bottom: BorderSide(color: Colors.red, width: 4),
                          left: BorderSide(color: Colors.transparent),
                          right: BorderSide(color: Colors.transparent),
                          top: BorderSide(color: Colors.transparent),
                        ),
                      ),
                      lineBarsData: [
                        lineChartBarData1(week),
                        // lineChartBarData1_2,
                        // lineChartBarData1_3,
                      ],
                      minX: 0,
                      maxX: 6,
                      maxY: 20,
                      minY: 0,
                    ),
                    // swapAnimationDuration: Duration(milliseconds: 150), // Optional
                    // swapAnimationCurve: Curves.linear, // Optional
                  )),
                ],
              ),
              bottomNavigationBar: const BottomNavBar(
                selectedIndex: 1,
              ));
        });
  }
}

Widget bottomTitleWidgets(double value, TitleMeta meta) {
  const style = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
  );

  // DateService().getMonth(value.toInt());
  final day = DateService().dayAxisLabel(value.toInt());
  return SideTitleWidget(axisSide: meta.axisSide, space: 10, child: Text(day, style: style));
}

Widget leftTitleWidgets(double value, TitleMeta meta) {
  const style = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 14,
  );

  return Text(value.toString(), style: style, textAlign: TextAlign.center);
}

LineChartBarData lineChartBarData1(List<dynamic> week) {
  List<FlSpot> values = [];
  for (int i = 0; i < week.length; i++) {
    print('$i, ${week[i]['ALL']}');
    final element = week[i]['ALL'] as int;
    values.add(FlSpot(i.toDouble(), element.toDouble()));
  }
  return LineChartBarData(
      isCurved: true,
      preventCurveOverShooting: true,
      color: Colors.green,
      barWidth: 4,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
      spots: values);
}

// LineChartBarData get lineChartBarData1_2 => LineChartBarData(
//       isCurved: true,
//       color: Colors.pink,
//       barWidth: 8,
//       isStrokeCapRound: true,
//       dotData: const FlDotData(show: false),
//       belowBarData: BarAreaData(show: false, color: Colors.pink),
//       spots: const [
//         FlSpot(1, 1),
//         FlSpot(3, 2.8),
//         FlSpot(7, 1.2),
//         FlSpot(10, 2.8),
//         FlSpot(12, 2.6),
//         FlSpot(13, 3.9),
//       ],
//     );

// LineChartBarData get lineChartBarData1_3 => LineChartBarData(
//       isCurved: true,
//       color: Colors.cyan,
//       barWidth: 8,
//       isStrokeCapRound: true,
//       dotData: const FlDotData(show: false),
//       belowBarData: BarAreaData(show: false),
//       spots: const [
//         FlSpot(1, 2.8),
//         FlSpot(3, 1.9),
//         FlSpot(6, 3),
//         FlSpot(10, 1.3),
//         FlSpot(13, 2.5),
//       ],
//     );
