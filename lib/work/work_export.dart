import 'package:intl/intl.dart';
import 'package:taskr/services/models.dart';

/// Pure Markdown formatting for work items. The shape is part of the
/// work-export spec and is locked by golden tests; change both together.
class WorkExport {
  WorkExport._();

  static final DateFormat _day = DateFormat('yyyy-MM-dd');

  static String date(int epochMs) => _day.format(DateTime.fromMillisecondsSinceEpoch(epochMs));

  static String item(WorkItem item) {
    final b = StringBuffer();
    b.writeln('## ${item.title}');
    final archived = item.archivedAt != null ? ', archived ${date(item.archivedAt!)}' : '';
    b.writeln('_Created ${date(item.createdAt)}${archived}_');
    if (item.notes.trim().isNotEmpty) {
      b.writeln();
      b.writeln(item.notes.trim());
    }
    b.writeln();
    b.writeln('### Next actions');
    for (final a in item.nextActions) {
      if (a.completedAt != null) {
        b.writeln('- [x] ${a.text}  (done ${date(a.completedAt!)})');
      } else if (a.isWaiting) {
        b.writeln('- [ ] ${a.text}  (waiting on ${a.waitingOn})');
      } else {
        b.writeln('- [ ] ${a.text}');
      }
    }
    if (item.updates.isNotEmpty) {
      b.writeln();
      b.writeln('### Updates');
      for (final u in item.updates) {
        b.writeln('- ${date(u.createdAt)}: ${u.text}');
      }
    }
    return b.toString().trimRight();
  }

  static String board(List<WorkItem> active, List<WorkItem> archived, {required int now}) {
    final b = StringBuffer();
    b.writeln('_Exported ${date(now)}_');
    b.writeln();
    b.writeln('# Work');
    b.writeln();
    _section(b, active);
    b.writeln();
    b.writeln('# Archived');
    b.writeln();
    _section(b, archived);
    return b.toString().trimRight();
  }

  static void _section(StringBuffer b, List<WorkItem> items) {
    if (items.isEmpty) {
      b.writeln('_None_');
      return;
    }
    for (var i = 0; i < items.length; i++) {
      if (i > 0) b.writeln();
      b.writeln(item(items[i]));
    }
  }
}
