import 'package:intl/intl.dart';
import 'package:taskr/services/date.service.dart';

/// A time window the Performance tab can show, picked from the header toggle
/// and shared by the average, the score line chart and the points-lost bars.
///
/// Every range is drawn from the one year-long history listener the page
/// already holds, so switching ranges re-slices memory and reads nothing.
///
/// Longer ranges are bucketed so the charts stay readable: the line chart
/// averages each bucket, the bar chart sums it. Buckets are whole, so a
/// bucketed chart covers the nearest whole number of buckets (52 weeks for a
/// year, 13 weeks for 90 days) rather than the exact day count.
class PerformanceRange {
  final String label;
  final int days;

  /// Days averaged into one point of the score line chart.
  final int lineBucketDays;

  /// Days summed into one bar of the points-lost chart.
  final int barBucketDays;

  const PerformanceRange(this.label, this.days, {this.lineBucketDays = 1, this.barBucketDays = 1});

  static const all = [
    PerformanceRange('7d', 7),
    PerformanceRange('30d', 30),
    PerformanceRange('90d', 90, barBucketDays: 7),
    PerformanceRange('1y', 365, lineBucketDays: 7, barBucketDays: 28),
  ];

  /// How many buckets of [bucketDays] the range is drawn as.
  int bucketCount(int bucketDays) => (days / bucketDays).round();
}

/// The last day of bucket [i] of [count], where the final bucket ends [today].
DateTime _bucketEnd(DateTime today, int count, int bucketDays, int i) =>
    DateService.shiftDays(today, -(count - 1 - i) * bucketDays);

/// One x-axis label per bucket, oldest first. A week is labelled by weekday on
/// every bucket; anything longer labels roughly six buckets, counted back from
/// today so the newest bucket always carries one, and leaves the rest blank.
List<String> bucketAxisLabels(DateTime today, int count, int bucketDays) {
  final totalDays = count * bucketDays;
  final format = totalDays <= 7
      ? DateFormat('E')
      : totalDays > 120
          ? DateFormat('MMM')
          : DateFormat('M/d');
  final step = count <= 7 ? 1 : (count / 6).ceil();
  return List.generate(count, (i) {
    if ((count - 1 - i) % step != 0) return '';
    return format.format(_bucketEnd(today, count, bucketDays, i));
  });
}

/// The dates bucket [i] covers, for tooltips: "Nov 3" or "Oct 28 – Nov 3".
String bucketSpanLabel(DateTime today, int count, int bucketDays, int i) {
  final end = _bucketEnd(today, count, bucketDays, i);
  final format = DateFormat('MMM d');
  if (bucketDays <= 1) return format.format(end);
  return '${format.format(DateService.shiftDays(end, -(bucketDays - 1)))} – ${format.format(end)}';
}
