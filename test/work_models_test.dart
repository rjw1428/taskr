import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';

void main() {
  group('WorkItem serialization', () {
    test('round-trips with nested lists as maps', () {
      final item = WorkItem(
        id: 'doc1',
        title: 'Migrate billing',
        notes: 'see https://x.y',
        position: 3,
        nextActions: [NextAction(id: 'a', text: 'Draft', createdAt: 10, waitingOn: 'Sam', completedAt: 20)],
        updates: [WorkUpdate(id: 'u', text: 'Shipped', createdAt: 30)],
        createdAt: 1,
        lastUpdated: 2,
        archivedAt: 40,
        restoredAt: 50,
      );
      final json = item.toJson();
      expect(json['nextActions'], isA<List>());
      expect(json['nextActions'][0], isA<Map>());
      expect(json['updates'][0], isA<Map>());
      final back = WorkItem.fromJson({...json, 'id': 'doc1'});
      expect(back.id, 'doc1');
      expect(back.title, 'Migrate billing');
      expect(back.notes, 'see https://x.y');
      expect(back.position, 3);
      expect(back.nextActions.single.waitingOn, 'Sam');
      expect(back.nextActions.single.completedAt, 20);
      expect(back.updates.single.text, 'Shipped');
      expect(back.archivedAt, 40);
      expect(back.restoredAt, 50);
    });

    test('does not emit id', () {
      final json = WorkItem(id: 'x', title: 't').toJson();
      expect(json.containsKey('id'), isFalse);
    });

    test('defaults missing optional fields', () {
      final item = WorkItem.fromJson({'title': 'Only title'});
      expect(item.notes, '');
      expect(item.position, 0);
      expect(item.nextActions, isEmpty);
      expect(item.updates, isEmpty);
      expect(item.createdAt, 0);
      expect(item.archivedAt, isNull);
      expect(item.isArchived, isFalse);
    });

    test('openActions filters completed', () {
      final item = WorkItem(title: 't', nextActions: [
        NextAction(id: 'a', text: 'open', createdAt: 1),
        NextAction(id: 'b', text: 'done', createdAt: 1, completedAt: 2),
      ]);
      expect(item.openActions.map((a) => a.id), ['a']);
    });

    test('copyWith can clear nullable fields', () {
      final a = NextAction(id: 'a', text: 't', createdAt: 1, waitingOn: 'Sam', completedAt: 5);
      final cleared = a.copyWith(waitingOn: null, completedAt: null);
      expect(cleared.waitingOn, isNull);
      expect(cleared.completedAt, isNull);
      expect(a.copyWith().waitingOn, 'Sam');
      final item = WorkItem(title: 't', archivedAt: 9, restoredAt: 8);
      expect(item.copyWith(archivedAt: null).archivedAt, isNull);
      expect(item.copyWith().restoredAt, 8);
    });

    test('isWaiting ignores blank labels', () {
      expect(NextAction(id: 'a', text: 't', createdAt: 1, waitingOn: '  ').isWaiting, isFalse);
      expect(NextAction(id: 'a', text: 't', createdAt: 1, waitingOn: 'Bob').isWaiting, isTrue);
    });

    test('pinnedAt round-trips through JSON', () {
      final json = NextAction(id: 'a', text: 't', createdAt: 1, pinnedAt: 99).toJson();
      expect(json['pinnedAt'], 99);
      final back = NextAction.fromJson(json);
      expect(back.pinnedAt, 99);
      expect(back.isPinned, isTrue);
    });

    test('missing pinnedAt parses as unpinned', () {
      final action = NextAction.fromJson({'id': 'a', 'text': 't', 'createdAt': 1});
      expect(action.pinnedAt, isNull);
      expect(action.isPinned, isFalse);
    });

    test('copyWith can set and clear pinnedAt', () {
      final a = NextAction(id: 'a', text: 't', createdAt: 1);
      expect(a.copyWith(pinnedAt: 7).pinnedAt, 7);
      expect(a.copyWith(pinnedAt: 7).copyWith(pinnedAt: null).pinnedAt, isNull);
    });

    test('unrelated copyWith preserves pinnedAt', () {
      final a = NextAction(id: 'a', text: 't', createdAt: 1, pinnedAt: 7);
      expect(a.copyWith(text: 'new').pinnedAt, 7);
      expect(a.copyWith(completedAt: 5).pinnedAt, 7);
      expect(a.copyWith(waitingOn: 'Sam').pinnedAt, 7);
    });
  });
}
