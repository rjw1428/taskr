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

          final maxYAxis = chartData
                  .map((day) => day['ALL'] as int)
                  .reduce((value, element) => value > element ? value : element) *
              1.2;
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                                      getTooltipColor: (touchedSpot) =>
                                          Colors.blueGrey.withOpacity(0.8),
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
                                  lineBarsData: lineChartBarData1(chartData, isShowingAll),
                                  // lineChartBarData1_2,
                                  // lineChartBarData1_3,

                                  // minX: 0,
                                  // maxX: chartData.length + 1,
                                  // minX: chartData.length.toDouble(),
                                  // maxX: -1,
                                  maxY: maxYAxis,
                                  minY: 0,
                                ),
                                // swapAnimationDuration: Duration(milliseconds: 150), // Optional
                                // swapAnimationCurve: Curves.linear, // Optional
                              ))),
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
                  )
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

  return Text(value.toString(), style: style, textAlign: TextAlign.center);
}

List<LineChartBarData> lineChartBarData1(List<Map<String, dynamic>> chartData, bool showAll) {
  List<FlSpot> values = [];

  if (showAll) {
    for (int i = 0; i < chartData.length; i++) {
      // print('${chartData.length - 1 - i}, ${chartData[i]['ALL']}');
      final element = chartData[i]['ALL'] as int;
      values.add(FlSpot(i.toDouble(), element.toDouble()));
    }

    return [
      LineChartBarData(
          isCurved: true,
          preventCurveOverShooting: false,
          gradient: LinearGradient(
            colors: [
              Colors.green.withOpacity(0),
              Colors.green,
            ],
            stops: [0.0, .5],
          ),
          barWidth: 4,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(show: true),
          spots: values)
    ];
  } else {
    List<LineChartBarData> lines2 = [];
    Map<String, List<FlSpot>> lines = {};
    for (int i = 0; i < chartData.length; i++) {
      chartData[i].keys.where((key) => key != 'ALL').forEach((key) {
        int value = chartData[i][key];
        final point = FlSpot(i.toDouble(), value.toDouble());
        if (lines.containsKey(key)) {
          lines[key]!.add(point);
        } else {
          lines[key] = [point];
        }
      });
    }
    print(lines.toString());
    return lines2;
  }
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
