import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/work/work_logic.dart';

NextAction a(String id, {int at = 1, int? done, String? waiting, int? pinned}) =>
    NextAction(id: id, text: 'text $id', createdAt: at, completedAt: done, waitingOn: waiting, pinnedAt: pinned);

void main() {
  group('WorkLogic next actions', () {
    test('complete and undo keep ids and positions', () {
      final done = WorkLogic.completeNextAction([a('1'), a('2')], '1', 99);
      expect(done[0].completedAt, 99);
      expect(done[1].completedAt, isNull);
      final undone = WorkLogic.undoComplete(done, '1');
      expect(undone[0].completedAt, isNull);
      expect(undone.map((x) => x.id), ['1', '2']);
    });

    test('updateNextAction normalizes blank waitingOn to null', () {
      final out = WorkLogic.updateNextAction([a('1', waiting: 'Sam')], '1', text: 'new', waitingOn: '   ');
      expect(out.single.text, 'new');
      expect(out.single.waitingOn, isNull);
      final again = WorkLogic.updateNextAction(out, '1', text: 'new', waitingOn: ' Finance ');
      expect(again.single.waitingOn, 'Finance');
    });

    test('add and append are pure', () {
      final actions = [a('1')];
      final more = WorkLogic.addNextAction(actions, a('2'));
      expect(actions.length, 1);
      expect(more.length, 2);
      final updates = <WorkUpdate>[];
      final u = WorkLogic.appendUpdate(updates, WorkUpdate(id: 'u', text: 't', createdAt: 1));
      expect(updates, isEmpty);
      expect(u.single.id, 'u');
    });

    test('openActions filters completed', () {
      final item = WorkItem(title: 't', nextActions: [a('1'), a('2', done: 5)]);
      expect(WorkLogic.openActions(item).map((x) => x.id), ['1']);
    });

    test('setPinned pins only the matching action', () {
      final out = WorkLogic.setPinned([a('1'), a('2')], '1', 99);
      expect(out[0].pinnedAt, 99);
      expect(out[1].pinnedAt, isNull);
      final cleared = WorkLogic.setPinned(out, '1', null);
      expect(cleared[0].pinnedAt, isNull);
      expect(cleared.map((x) => x.id), ['1', '2']);
    });

    test('complete and undo leave pinnedAt untouched', () {
      final done = WorkLogic.completeNextAction([a('1', pinned: 7)], '1', 99);
      expect(done.single.pinnedAt, 7);
      final undone = WorkLogic.undoComplete(done, '1');
      expect(undone.single.pinnedAt, 7);
      expect(undone.single.completedAt, isNull);
    });
  });

  group('WorkLogic.pinnedActions', () {
    test('excludes completed and unpinned actions', () {
      final items = [
        WorkItem(id: 'i1', title: 'A', nextActions: [a('1', pinned: 10), a('2'), a('3', pinned: 5, done: 99)]),
      ];
      expect(WorkLogic.pinnedActions(items).map((p) => p.$2.id), ['1']);
    });

    test('spans items and orders by pin time, oldest first', () {
      final items = [
        WorkItem(id: 'i1', title: 'A', nextActions: [a('1', pinned: 30)]),
        WorkItem(id: 'i2', title: 'B', nextActions: [a('2', pinned: 10), a('3', pinned: 20)]),
      ];
      final pairs = WorkLogic.pinnedActions(items);
      expect(pairs.map((p) => p.$2.id), ['2', '3', '1']);
      expect(pairs.map((p) => p.$1.title), ['B', 'B', 'A']);
    });

    test('empty when nothing is pinned', () {
      expect(WorkLogic.pinnedActions([WorkItem(title: 'A', nextActions: [a('1')])]), isEmpty);
    });
  });

  group('WorkLogic.buildTimeline', () {
    test('orders created, action added, completed, update oldest first', () {
      final item = WorkItem(
        title: 'Proj',
        createdAt: 100,
        nextActions: [a('1', at: 200, done: 300)],
        updates: [WorkUpdate(id: 'u', text: 'Shipped', createdAt: 400)],
      );
      final t = WorkLogic.buildTimeline(item);
      expect(t.map((e) => e.kind), [
        WorkEventKind.created,
        WorkEventKind.actionAdded,
        WorkEventKind.actionCompleted,
        WorkEventKind.updateAdded,
      ]);
      expect(t.map((e) => e.at), [100, 200, 300, 400]);
      expect(t[3].text, 'Shipped');
    });

    test('includes archive and restore events at their times', () {
      final item = WorkItem(title: 'P', createdAt: 1, archivedAt: 50, restoredAt: 60);
      final kinds = WorkLogic.buildTimeline(item).map((e) => e.kind).toList();
      expect(kinds, [WorkEventKind.created, WorkEventKind.archived, WorkEventKind.restored]);
    });

    test('interleaves by timestamp across lists', () {
      final item = WorkItem(
        title: 'P',
        createdAt: 1,
        nextActions: [a('1', at: 10), a('2', at: 30)],
        updates: [WorkUpdate(id: 'u', text: 'mid', createdAt: 20)],
      );
      expect(WorkLogic.buildTimeline(item).map((e) => e.at), [1, 10, 20, 30]);
    });

    test('equal timestamps keep insertion order', () {
      final item = WorkItem(title: 'P', createdAt: 5, nextActions: [a('1', at: 5), a('2', at: 5)]);
      expect(WorkLogic.buildTimeline(item).map((e) => e.text), ['P', 'text 1', 'text 2']);
    });

    test('WorkEvent equality', () {
      const e1 = WorkEvent(kind: WorkEventKind.created, at: 1, text: 'x');
      const e2 = WorkEvent(kind: WorkEventKind.created, at: 1, text: 'x');
      expect(e1, e2);
      expect(e1.hashCode, e2.hashCode);
      expect(e1.toString(), contains('created'));
    });
  });
}
