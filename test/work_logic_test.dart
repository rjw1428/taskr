import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/work/work_logic.dart';

NextAction a(String id, {int at = 1, int? done, String? waiting}) =>
    NextAction(id: id, text: 'text $id', createdAt: at, completedAt: done, waitingOn: waiting);

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
