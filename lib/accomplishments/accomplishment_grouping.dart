import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';

/// A run of accomplishments that share a calendar month, in the order they
/// arrived from the query (newest-first).
class AccomplishmentMonth {
  /// Sort key, `yyyy-MM`. Entries with an unparseable date group under ''.
  final String key;

  /// Heading shown above the group, e.g. "August 2026".
  final String label;

  final List<Accomplishment> accomplishments;

  const AccomplishmentMonth({
    required this.key,
    required this.label,
    required this.accomplishments,
  });
}

/// Groups [accomplishments] into consecutive month runs, preserving the input
/// order both within and across groups.
///
/// The input is expected newest-first (the query orders it that way), so the
/// groups come out newest-first too. Grouping is done on consecutive runs
/// rather than by bucketing, so a correctly ordered input yields one group per
/// month and a misordered one degrades into repeated headings rather than
/// silently reordering the user's entries.
///
/// `date` is caller-supplied and unvalidated; an entry whose date will not
/// parse is grouped under an "Undated" heading instead of throwing.
List<AccomplishmentMonth> groupByMonth(List<Accomplishment> accomplishments) {
  final groups = <AccomplishmentMonth>[];

  for (final accomplishment in accomplishments) {
    final date = DateTime.tryParse(accomplishment.date);
    final key = date == null ? '' : DateFormat('yyyy-MM').format(date);

    if (groups.isNotEmpty && groups.last.key == key) {
      groups.last.accomplishments.add(accomplishment);
      continue;
    }

    groups.add(AccomplishmentMonth(
      key: key,
      label: date == null ? 'Undated' : DateFormat('MMMM yyyy').format(date),
      accomplishments: [accomplishment],
    ));
  }

  return groups;
}
