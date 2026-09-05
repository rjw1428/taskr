import 'package:cloud_firestore/cloud_firestore.dart';

/// Every performance doc the Performance tab needs, read once and shared.
///
/// The header, heatmap, chart and records card each used to open their own
/// listener, with `DateTime.now()` baked into the query bounds. A query with a
/// different bound is a different query to the SDK, so every rebuild — a
/// toggle, a new snapshot — tore down three year-long listeners and re-read
/// the whole year three times over. Now one listener feeds all of them and
/// each card slices the window it wants in memory.
class PerformanceHistory {
  final List<Map<String, dynamic>> docs;
  const PerformanceHistory(this.docs);

  static DateTime? _dateOf(Map<String, dynamic> doc) => (doc['date'] as Timestamp?)?.toDate();

  /// Docs dated strictly after [after] and, when given, no later than [until].
  List<Map<String, dynamic>> between({DateTime? after, DateTime? until}) {
    return docs.where((doc) {
      final date = _dateOf(doc);
      if (date == null) return false;
      if (after != null && !date.isAfter(after)) return false;
      if (until != null && date.isAfter(until)) return false;
      return true;
    }).toList();
  }

  /// `completed.ALL` per day (date-only keys) for docs no later than [until].
  Map<DateTime, int> scoresByDay({DateTime? until}) {
    final scores = <DateTime, int>{};
    for (final doc in docs) {
      final date = _dateOf(doc);
      if (date == null) continue;
      if (until != null && date.isAfter(until)) continue;
      final completed = doc['completed'] as Map<String, dynamic>?;
      scores[DateTime(date.year, date.month, date.day)] = (completed?['ALL'] as int?) ?? 0;
    }
    return scores;
  }
}
