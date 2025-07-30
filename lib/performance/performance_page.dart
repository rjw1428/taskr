import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/services.dart';
import '../shared/shared.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:taskr/performance/performance_heatmap.dart';

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

class CurrentScore extends StatefulWidget {
  final String userId;
  const CurrentScore({super.key, required this.userId});

  @override
  State<StatefulWidget> createState() => CurrentScoreState();
}

class CurrentScoreState extends State<CurrentScore> {
  bool isShowingAll = true;

  @override
  Widget build(BuildContext context) {
    DateTime selectedMinDate = DateService().daysAgo(DateTime.now(), 7);
    return StreamBuilder(
        stream: CombineLatestStream.combine2(
            PerformanceService().streamPerformance(widget.userId, selectedMinDate),
            TagService().streamTags(widget.userId),
            (currentPerformance, tags) => [currentPerformance, tags]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingScreen(message: 'Loading Tasks...');
          }

          if (snapshot.hasError) {
            print(snapshot.error);
            return const Text("ERROR");
          }
          final performace = snapshot.data![0]
              as List<Map<String, dynamic>>; //as Map<String, List<Map<String, int>>>;
          final chartData =
              performace.map((days) => days['completed'] as Map<String, dynamic>).toList();

          final maxYAxis = (chartData
                      .map((day) => day['ALL'] as int)
                      .reduce((value, element) => value > element ? value : element) *
                  (isShowingAll ? 1.2 : 0.6))
              .toInt();

          print(maxYAxis);
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
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'Daily Progress',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  PerformanceHeatmap(userId: widget.userId),
                  const SizedBox(height: 16),
                  Stack(
                    children: [
                      Center(
                          child: SizedBox(
                              width: MediaQuery.of(context).size.width * 0.8,
                              height: 500,
                              child: LineChart(
                                LineChartData(
                                  lineTouchData: LineTouchData(
                                    handleBuiltInTouches: true,
                                    touchTooltipData: LineTouchTooltipData(
                                      fitInsideHorizontally: true,
                                      fitInsideVertically: true,
                                      getTooltipColor: (touchedSpot) =>
                                          Colors.blueGrey.withOpacity(0.8),
                                      getTooltipItems: (data) => data.map((spot) {
                                        // print(spot.toString());
                                        return LineTooltipItem(
                                            spot.y.toString(), const TextStyle(color: Colors.red));
                                      }).toList(),
                                    ),
                                  ),
                                  gridData: const FlGridData(show: false),
                                  titlesData: FlTitlesData(
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 32,
                                          interval: 1,
                                          getTitlesWidget: (double value, TitleMeta meta) =>
                                              bottomTitleWidgets(value, meta, chartData.length)),
                                    ),
                                    rightTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    topTitles: const AxisTitles(
                                      sideTitles: SideTitles(showTitles: false),
                                    ),
                                    leftTitles: const AxisTitles(
                                      sideTitles: SideTitles(
                                          getTitlesWidget: leftTitleWidgets,
                                          showTitles: true,
                                          interval: 2
                                          // reservedSize: 40,
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
                                  lineBarsData: lineChartBarData1(chartData, isShowingAll),
                                  // lineChartBarData1_2,
                                  // lineChartBarData1_3,

                                  // minX: 0,
                                  // maxX: chartData.length + 1,
                                  // minX: chartData.length.toDouble(),
                                  // maxX: -1,
                                  maxY: maxYAxis.toDouble(),
                                  minY: 0,
                                ),
                                // swapAnimationDuration: Duration(milliseconds: 150), // Optional
                                // swapAnimationCurve: Curves.linear, // Optional
                              ))),
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.refresh,
                                  color: Colors.white.withOpacity(isShowingAll ? 1.0 : 0.5),
                                ),
                                onPressed: () {
                                  setState(() {
                                    isShowingAll = !isShowingAll;
                                  });
                                },
                              )
                            ],
                          )),
                    ],
                  ),
                ],
              ),
              bottomNavigationBar: const BottomNavBar(
                selectedIndex: 1,
              ));
        });
  }
}

Widget bottomTitleWidgets(double value, TitleMeta meta, int dataLength) {
  const style = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
  );

  final day = DateService().dayAxisLabel(dataLength - 1 - value.toInt());
  return SideTitleWidget(axisSide: meta.axisSide, space: 10, child: Text(day, style: style));
}

Widget leftTitleWidgets(double value, TitleMeta meta) {
  const style = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 14,
  );

  return Text(value.toInt().toString(), style: style, textAlign: TextAlign.center);
}

List<LineChartBarData> lineChartBarData1(List<Map<String, dynamic>> chartData, bool showAll) {
  List<LineChartBarData> lines2 = [];

  Set uniqueKeys = {};
  for (int i = 0; i < chartData.length; i++) {
    uniqueKeys.addAll(chartData[i].keys);
  }

  Map<String, List<FlSpot>> lines = {};
  for (int i = 0; i < chartData.length; i++) {
    for (var key in uniqueKeys) {
      int value = chartData[i][key] ?? 0;
      final point = FlSpot(i.toDouble(), value.toDouble());
      if (lines.containsKey(key)) {
        lines[key]!.add(point);
      } else if (value != 0) {
        lines[key] = [point];
      }
    }
  }

  for (int j = 0; j < lines.keys.length; j++) {
    final key = lines.keys.toList()[j];
    final show = showAll ? key == 'ALL' : key != 'ALL';
    final values = lines.values.toList()[j];
    Color c = showAll ? chartColors[0] : chartColors[j];
    lines2.add(LineChartBarData(
        isCurved: true,
        show: show,
        preventCurveOverShooting: true,
        color: c,
        barWidth: 4,
        isStrokeCapRound: true,
        dotData: FlDotData(show: show),
        belowBarData: BarAreaData(show: showAll),
        spots: values));
  }
  return lines2;
}
