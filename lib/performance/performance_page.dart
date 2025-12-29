import 'package:flutter/material.dart';
import 'package:taskr/services/services.dart';
import '../shared/shared.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:taskr/performance/performance_heatmap.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/accomplishment.provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/accomplishments/accomplishment_detail_page.dart';

class PerformancePage extends StatelessWidget {
  const PerformancePage({super.key});
  @override
  Widget build(BuildContext context) {
    final user = AuthService().user!;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AccomplishmentProvider()),
        StreamProvider<List<Map<String, dynamic>>?>.value(
          value: PerformanceService().streamPerformance(user.uid, DateService().daysAgo(DateTime.now(), 7)),
          initialData: null,
          catchError: (context, error) {
            debugPrint('Error in PerformanceService stream: $error');
            return [];
          },
        ),
      ],
      child: CurrentScore(userId: user.uid),
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
    final performance = Provider.of<List<Map<String, dynamic>>?>(context);

    if (performance == null) {
      return const LoadingScreen(message: 'Loading Performance Data...');
    }

    if (performance.isEmpty) {
      return const Center(
        child: Text('Complete some tasks to get your performance info'),
      );
    }

    final chartData = performance.map((days) => days['completed'] as Map<String, dynamic>).toList();

    final maxYAxis =
        (chartData.map((day) => day['ALL'] as int).reduce((value, element) => value > element ? value : element) *
                (isShowingAll ? 1.2 : 0.6))
            .toInt();

    debugPrint(maxYAxis.toString());
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PerformanceHeatmap(userId: widget.userId),
          const SizedBox(height: 16),
          const Text(
            'Latest Accomplishments',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
          const _AccomplishmentsSummary(),
          const SizedBox(height: 16),
          Stack(
            children: [
              Center(
                  child: SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: 300,
                      child: LineChart(
                        LineChartData(
                          lineTouchData: LineTouchData(
                            handleBuiltInTouches: true,
                            touchTooltipData: LineTouchTooltipData(
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipColor: (touchedSpot) => Colors.blueGrey.withValues(alpha: 0.8),
                              getTooltipItems: (data) => data.map((spot) {
                                return LineTooltipItem(spot.y.toString(), const TextStyle(color: Colors.white));
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
                              sideTitles: SideTitles(getTitlesWidget: leftTitleWidgets, showTitles: true, interval: 2),
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
                          maxY: maxYAxis.toDouble(),
                          minY: 0,
                        ),
                      ))),
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: Colors.white.withValues(alpha: isShowingAll ? 1.0 : 0.5),
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
    );
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

class _AccomplishmentsSummary extends StatelessWidget {
  const _AccomplishmentsSummary();

  @override
  Widget build(BuildContext context) {
    var accomplishmentProvider = Provider.of<AccomplishmentProvider>(context);

    return StreamBuilder<List<Accomplishment>>(
      stream: accomplishmentProvider.getAccomplishments(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        } else if (snapshot.hasError) {
          return Center(child: ErrorMessage(message: snapshot.error.toString()));
        } else if (snapshot.hasData) {
          var accomplishments = snapshot.data!;
          // Take only the latest 5 accomplishments
          var latestAccomplishments = accomplishments.take(5).toList();

          if (latestAccomplishments.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('No accomplishments yet!', style: TextStyle(fontSize: 18)),
              ),
            );
          }

          return SizedBox(
            height: 200, // Fixed height to show 5 items with scrolling
            child: ListView.builder(
              itemCount: latestAccomplishments.length,
              itemBuilder: (context, index) {
                var accomplishment = latestAccomplishments[index];
                // Format the date to MM/dd
                final DateTime date = DateTime.parse(accomplishment.date);
                final String formattedDate =
                    '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                  child: InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AccomplishmentDetailPage(accomplishment: accomplishment),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        // Use Row to place title on left and date on right
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            // Allow title to take remaining space
                            child: Text(
                              accomplishment.title,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          Text(
                            formattedDate, // Display formatted date
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        } else {
          return const Center(child: Text('No accomplishments found.'));
        }
      },
    );
  }
}
