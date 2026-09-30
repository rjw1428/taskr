import 'package:taskr/services/models.dart';

/// Pure, Firebase-free helpers for work items. Every board mutation is expressed
/// here as a function from an item to a new item so it can be unit tested and
/// so the service only has to persist results.
enum WorkEventKind { created, actionAdded, actionCompleted, updateAdded, archived, restored }

class WorkEvent {
  final WorkEventKind kind;
  final int at;
  final String text;
  const WorkEvent({required this.kind, required this.at, required this.text});

  @override
  bool operator ==(Object other) =>
      other is WorkEvent && other.kind == kind && other.at == at && other.text == text;

  @override
  int get hashCode => Object.hash(kind, at, text);

  @override
  String toString() => 'WorkEvent($kind, $at, $text)';
}

class WorkLogic {
  WorkLogic._();

  static List<NextAction> openActions(WorkItem item) => item.nextActions.where((a) => a.isOpen).toList();

  static List<NextAction> completeNextAction(List<NextAction> actions, String id, int now) =>
      [for (final a in actions) a.id == id ? a.copyWith(completedAt: now) : a];

  static List<NextAction> undoComplete(List<NextAction> actions, String id) =>
      [for (final a in actions) a.id == id ? a.copyWith(completedAt: null) : a];

  static List<NextAction> updateNextAction(List<NextAction> actions, String id, {required String text, String? waitingOn}) =>
      [for (final a in actions) a.id == id ? a.copyWith(text: text, waitingOn: _normalize(waitingOn)) : a];

  static List<NextAction> addNextAction(List<NextAction> actions, NextAction action) => [...actions, action];

  static List<WorkUpdate> appendUpdate(List<WorkUpdate> updates, WorkUpdate update) => [...updates, update];

  static String? _normalize(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// The item's history, derived from its timestamps, oldest first. Nothing is
  /// stored for this; the embedded lists are the single source of truth.
  static List<WorkEvent> buildTimeline(WorkItem item) {
    final events = <WorkEvent>[
      WorkEvent(kind: WorkEventKind.created, at: item.createdAt, text: item.title),
      for (final a in item.nextActions) ...[
        WorkEvent(kind: WorkEventKind.actionAdded, at: a.createdAt, text: a.text),
        if (a.completedAt != null) WorkEvent(kind: WorkEventKind.actionCompleted, at: a.completedAt!, text: a.text),
      ],
      for (final u in item.updates) WorkEvent(kind: WorkEventKind.updateAdded, at: u.createdAt, text: u.text),
      if (item.archivedAt != null) WorkEvent(kind: WorkEventKind.archived, at: item.archivedAt!, text: ''),
      if (item.restoredAt != null) WorkEvent(kind: WorkEventKind.restored, at: item.restoredAt!, text: ''),
    ];
    // Stable sort so events sharing a timestamp keep insertion order.
    final indexed = events.asMap().entries.toList()
      ..sort((x, y) {
        final c = x.value.at.compareTo(y.value.at);
        return c != 0 ? c : x.key.compareTo(y.key);
      });
    return indexed.map((e) => e.value).toList();
  }
}
