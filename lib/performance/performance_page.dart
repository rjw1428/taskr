import 'package:flutter/material.dart';
import 'package:taskr/services/services.dart';
import '../shared/shared.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:taskr/performance/performance_heatmap.dart';
import 'package:taskr/performance/performance_average_header.dart';
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
    final theme = Theme.of(context);
    final t = theme.appTokens;
    final performance = Provider.of<List<Map<String, dynamic>>?>(context);

    if (performance == null) {
      return const LoadingScreen(message: 'Loading Performance Data...');
    }

    if (performance.isEmpty) {
      return const EmptyState(
        icon: Icons.query_stats,
        title: 'No performance data yet',
        message: 'Complete some tasks to start tracking your progress.',
      );
    }

    final chartData = performance.map((days) => days['completed'] as Map<String, dynamic>).toList();

    // Y-axis max reflects the series actually shown: the total ('ALL') in Total
    // mode, or the largest per-effort value in Breakdown mode. Previously the max
    // was the total scaled by 0.6, so tall single-effort days ran off the top.
    int displayedMax = 0;
    for (final day in chartData) {
      day.forEach((key, value) {
        if (value is! int) return;
        final included = isShowingAll ? key == 'ALL' : key != 'ALL';
        if (included && value > displayedMax) displayedMax = value;
      });
    }
    final maxYAxis = displayedMax <= 0 ? 4 : (displayedMax * 1.2).ceil();

    // Chart series colors derived from the theme (accent teal for the single
    // "ALL" line, priority accents for the categorical breakdown).
    final seriesColors = <Color>[
      theme.colorScheme.primary,
      t.of(Effort.high).accent,
      t.of(Effort.medium).accent,
      t.of(Effort.low).accent,
      t.textFaint,
    ];
    final chartSeries = computeChartSeries(chartData, isShowingAll, seriesColors);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.md, Insets.lg, Insets.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(child: PerformanceAverageHeader(userId: widget.userId)),
          const SizedBox(height: Insets.lg),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Daily score', style: theme.textTheme.titleMedium),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Total')),
                        ButtonSegment(value: false, label: Text('Breakdown')),
                      ],
                      selected: {isShowingAll},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => isShowingAll = s.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.lg),
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipColor: (touchedSpot) => t.surfaceRaised.withValues(alpha: 0.95),
                          getTooltipItems: (data) => data.map((spot) {
                            return LineTooltipItem(spot.y.toString(), TextStyle(color: theme.colorScheme.onSurface));
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
                                  bottomTitleWidgets(value, meta, chartData.length, t.textMuted)),
                        ),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                              getTitlesWidget: (v, m) => leftTitleWidgets(v, m, t.textMuted),
                              showTitles: true,
                              interval: 2),
                        ),
                      ),
                      borderData: FlBorderData(
                        show: true,
                        border: Border(
                          bottom: BorderSide(color: t.hairline, width: 2),
                          left: const BorderSide(color: Colors.transparent),
                          right: const BorderSide(color: Colors.transparent),
                          top: const BorderSide(color: Colors.transparent),
                        ),
                      ),
                      lineBarsData: seriesToBars(chartSeries, isShowingAll),
                      maxY: maxYAxis.toDouble(),
                      minY: 0,
                    ),
                  ),
                ),
                // Breakdown legend: identify which line is which tag.
                if (!isShowingAll)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.md),
                    child: Wrap(
                      spacing: Insets.lg,
                      runSpacing: Insets.sm,
                      children: chartSeries
                          .where((s) => s.shown)
                          .map((s) => _LegendDot(color: s.color, label: s.key))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Insets.lg),
          AppCard(child: PerformanceHeatmap(userId: widget.userId)),
          const SizedBox(height: Insets.lg),
          Padding(
            padding: const EdgeInsets.only(left: Insets.xs, bottom: Insets.sm),
            child: Text('Latest accomplishments', style: theme.textTheme.titleMedium),
          ),
          const _AccomplishmentsSummary(),
        ],
      ),
    );
  }
}

Widget bottomTitleWidgets(double value, TitleMeta meta, int dataLength, Color color) {
  final style = TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: color);
  final day = DateService().dayAxisLabel(dataLength - 1 - value.toInt());
  return SideTitleWidget(axisSide: meta.axisSide, space: 10, child: Text(day, style: style));
}

Widget leftTitleWidgets(double value, TitleMeta meta, Color color) {
  final style = TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: color);
  return Text(value.toInt().toString(), style: style, textAlign: TextAlign.center);
}

class ChartSeries {
  final String key;
  final Color color;
  final bool shown;
  final List<FlSpot> spots;
  const ChartSeries(this.key, this.color, this.shown, this.spots);
}

/// Build the per-series data (key + color + spots). In "Total" mode only the
/// ALL series is shown; in "Breakdown" mode each tag/effort series is shown.
/// The `key` is surfaced so the UI can render a matching legend.
List<ChartSeries> computeChartSeries(
    List<Map<String, dynamic>> chartData, bool showAll, List<Color> seriesColors) {
  final Set uniqueKeys = {};
  for (int i = 0; i < chartData.length; i++) {
    uniqueKeys.addAll(chartData[i].keys);
  }
  final Map<String, List<FlSpot>> lines = {};
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
  final series = <ChartSeries>[];
  final keys = lines.keys.toList();
  for (int j = 0; j < keys.length; j++) {
    final key = keys[j];
    final show = showAll ? key == 'ALL' : key != 'ALL';
    final color = showAll ? seriesColors[0] : seriesColors[j % seriesColors.length];
    series.add(ChartSeries(key, color, show, lines[key]!));
  }
  return series;
}

List<LineChartBarData> seriesToBars(List<ChartSeries> series, bool showAll) {
  return series
      .map((s) => LineChartBarData(
            isCurved: true,
            show: s.shown,
            preventCurveOverShooting: true,
            color: s.color,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(show: s.shown),
            belowBarData: BarAreaData(show: showAll),
            spots: s.spots,
          ))
      .toList();
}

/// A colored dot + label used in the breakdown legend.
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.appTokens.textMuted)),
      ],
    );
  }
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
                final t = Theme.of(context).appTokens;
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
                            style: TextStyle(fontSize: 14, color: t.textMuted),
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
