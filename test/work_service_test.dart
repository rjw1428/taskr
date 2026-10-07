import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/work/work_actions.dart';
import 'package:taskr/work/work_logic.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late WorkService service;
  var clock = 1000;

  setUp(() async {
    env = await TestEnv.create();
    clock = 1000;
    service = WorkService()..now = () => ++clock;
  });
  tearDown(() => env.dispose());

  Future<Map<String, dynamic>?> active(String id) async => (await env.col('work').doc(id).get()).data();
  Future<Map<String, dynamic>?> archived(String id) async => (await env.col('workArchive').doc(id).get()).data();

  group('add', () {
    test('appends with position = count and timestamps, no id field', () async {
      final a = await service.add(WorkItem(title: 'A', id: 'ignored', archivedAt: 5));
      final b = await service.add(WorkItem(title: 'B', notes: 'n'));
      final da = (await active(a))!;
      final db = (await active(b))!;
      expect(da['position'], 0);
      expect(db['position'], 1);
      expect(da.containsKey('id'), isFalse);
      expect(da['archivedAt'], isNull);
      expect(da['createdAt'], isA<int>());
      expect(da['lastUpdated'], da['createdAt']);
      expect(db['notes'], 'n');
      expect(da['nextActions'], isEmpty);
      expect(da['updates'], isEmpty);
    });
  });

  group('streams', () {
    test('streamActive orders by position', () async {
      final a = await service.add(WorkItem(title: 'A'));
      final b = await service.add(WorkItem(title: 'B'));
      final c = await service.add(WorkItem(title: 'C'));
      await service.reorder([c, a, b]);
      final items = await service.streamActive().first;
      expect(items.map((i) => i.title), ['C', 'A', 'B']);
      expect(items.first.id, c);
    });

    test('streamArchived orders newest archive first', () async {
      final a = await service.add(WorkItem(title: 'A'));
      final b = await service.add(WorkItem(title: 'B'));
      await service.archive(a);
      await service.archive(b);
      final items = await service.streamArchived().first;
      expect(items.map((i) => i.title), ['B', 'A']);
    });

    test('streamOne and getters resolve from the right collection', () async {
      final a = await service.add(WorkItem(title: 'A'));
      expect((await service.streamOne(a, archived: false).first)?.title, 'A');
      expect(await service.streamOne(a, archived: true).first, isNull);
      expect((await service.getActive(a))?.title, 'A');
      expect(await service.getArchived(a), isNull);
      await service.archive(a);
      expect((await service.getArchived(a))?.title, 'A');
      expect(await service.getActive(a), isNull);
      expect((await service.streamOne(a, archived: true).first)?.isArchived, isTrue);
    });
  });

  group('reorder', () {
    test('rewrites only position', () async {
      final a = await service.add(WorkItem(title: 'A', notes: 'keep'));
      final b = await service.add(WorkItem(title: 'B'));
      await service.setNextActions(a, [NextAction(id: 'x', text: 't', createdAt: 1)]);
      final before = (await active(a))!;
      await service.reorder([b, a]);
      final after = (await active(a))!;
      expect(after['position'], 1);
      expect((await active(b))!['position'], 0);
      expect(after['notes'], 'keep');
      expect(after['nextActions'], before['nextActions']);
      expect(after['lastUpdated'], before['lastUpdated']);
    });
  });

  group('details, next actions, updates', () {
    test('updateDetails touches title, notes, lastUpdated only', () async {
      final a = await service.add(WorkItem(title: 'A'));
      await service.setNextActions(a, [NextAction(id: 'x', text: 't', createdAt: 1)]);
      final before = (await active(a))!;
      await service.updateDetails(a, title: 'A2', notes: 'notes');
      final after = (await active(a))!;
      expect(after['title'], 'A2');
      expect(after['notes'], 'notes');
      expect(after['nextActions'], before['nextActions']);
      expect(after['position'], before['position']);
      expect(after['lastUpdated'], greaterThan(before['lastUpdated'] as int));
    });

    test('setNextActions stores maps', () async {
      final a = await service.add(WorkItem(title: 'A'));
      await service.setNextActions(a, [NextAction(id: 'x', text: 't', createdAt: 1, waitingOn: 'Sam')]);
      final stored = (await active(a))!['nextActions'] as List;
      expect(stored.single, isA<Map>());
      expect(stored.single['waitingOn'], 'Sam');
    });

    test('addUpdate appends with id and time; unknown item is a no-op', () async {
      final a = await service.add(WorkItem(title: 'A'));
      await service.addUpdate(a, 'first');
      await service.addUpdate(a, 'second');
      final updates = (await active(a))!['updates'] as List;
      expect(updates.map((u) => u['text']), ['first', 'second']);
      expect(updates[0]['id'], isNotEmpty);
      expect(updates[0]['id'] != updates[1]['id'], isTrue);
      expect(updates[1]['createdAt'], greaterThan(updates[0]['createdAt'] as int));
      await service.addUpdate('missing', 'x');
      expect(await active('missing'), isNull);
    });

    test('newId is unique', () {
      expect(service.newId(), isNot(service.newId()));
    });
  });

  group('togglePin', () {
    test('pins with the clock time and unpins back to null', () async {
      final actions = WorkActions(service);
      final a = await service.add(WorkItem(title: 'A'));
      await service.setNextActions(a, [NextAction(id: 'x', text: 't', createdAt: 1)]);
      final open = (await service.getActive(a))!.nextActions.single;
      final beforePin = clock;
      await actions.togglePin(a, open);
      final pinned = (await active(a))!['nextActions'] as List;
      expect(pinned.single['pinnedAt'], greaterThan(beforePin));
      await actions.togglePin(a, NextAction.fromJson(Map<String, dynamic>.from(pinned.single as Map)));
      final unpinned = (await active(a))!['nextActions'] as List;
      expect(unpinned.single['pinnedAt'], isNull);
    });

    test('re-reads the latest item and touches only the target action', () async {
      final actions = WorkActions(service);
      final a = await service.add(WorkItem(title: 'A', notes: 'keep'));
      await service.setNextActions(a, [
        NextAction(id: 'x', text: 'first', createdAt: 1),
        NextAction(id: 'y', text: 'second', createdAt: 2, waitingOn: 'Sam'),
      ]);
      final stale = (await service.getActive(a))!.nextActions.first;
      // Concurrent edit lands after our copy was taken; the pin must not undo it.
      await service.setNextActions(a, WorkLogic.updateNextAction(
          (await service.getActive(a))!.nextActions, 'x', text: 'renamed'));
      await actions.togglePin(a, stale);
      final doc = (await active(a))!;
      final stored = doc['nextActions'] as List;
      expect(stored[0]['text'], 'renamed');
      expect(stored[0]['pinnedAt'], isA<int>());
      expect(stored[1]['pinnedAt'], isNull);
      expect(stored[1]['waitingOn'], 'Sam');
      expect(doc['notes'], 'keep');
    });

    test('unknown item is a no-op', () async {
      final actions = WorkActions(service);
      await actions.togglePin('missing', NextAction(id: 'x', text: 't', createdAt: 1));
      expect(await active('missing'), isNull);
    });
  });

  group('archive and restore', () {
    test('archive moves the document with archivedAt and identical content', () async {
      final a = await service.add(WorkItem(title: 'A', notes: 'n'));
      await service.setNextActions(a, [NextAction(id: 'x', text: 't', createdAt: 1)]);
      final before = (await active(a))!;
      await service.archive(a);
      expect(await active(a), isNull);
      final arch = (await archived(a))!;
      expect(arch['archivedAt'], isA<int>());
      expect(arch['title'], 'A');
      expect(arch['notes'], 'n');
      expect(arch['nextActions'], before['nextActions']);
      expect(arch['createdAt'], before['createdAt']);
    });

    test('restore appends to bottom, clears archivedAt, sets restoredAt', () async {
      final a = await service.add(WorkItem(title: 'A'));
      await service.archive(a);
      await service.add(WorkItem(title: 'B'));
      await service.add(WorkItem(title: 'C'));
      await service.add(WorkItem(title: 'D'));
      await service.restore(a);
      expect(await archived(a), isNull);
      final back = (await active(a))!;
      expect(back['position'], 3);
      expect(back['archivedAt'], isNull);
      expect(back['restoredAt'], isA<int>());
      final items = await service.streamActive().first;
      expect(items.map((i) => i.title), ['B', 'C', 'D', 'A']);
    });

    test('archive and restore of missing ids are no-ops', () async {
      await service.archive('nope');
      await service.restore('nope');
      expect(await active('nope'), isNull);
      expect(await archived('nope'), isNull);
    });

    test('delete paths', () async {
      final a = await service.add(WorkItem(title: 'A'));
      final b = await service.add(WorkItem(title: 'B'));
      await service.archive(b);
      await service.delete(a);
      await service.deleteArchived(b);
      expect(await active(a), isNull);
      expect(await archived(b), isNull);
    });
  });

  group('isolation', () {
    Future<Map<String, int>> counts() async => {
          'performance': (await env.col('performance').get()).size,
          'accomplishments': (await env.col('accomplishments').get()).size,
          'tasks': (await env.col('tasks').get()).size,
        };

    test('a full lifecycle leaves performance, accomplishments, and tasks untouched', () async {
      final userBefore = await env.userDoc();
      final before = await counts();
      final a = await service.add(WorkItem(title: 'Proj'));
      final id = service.newId();
      await service.setNextActions(a, [NextAction(id: id, text: 'step', createdAt: service.now())]);
      var item = (await service.getActive(a))!;
      await service.setNextActions(a, WorkLogic.completeNextAction(item.nextActions, id, service.now()));
      item = (await service.getActive(a))!;
      await service.setNextActions(a, WorkLogic.undoComplete(item.nextActions, id));
      await service.addUpdate(a, 'progress');
      await service.archive(a);
      await service.restore(a);
      await service.delete(a);
      expect(await counts(), before);
      expect(await env.userDoc(), userBefore);
      final all = await env.db.collection('todos').doc(env.uid).collection('work').get();
      expect(all.size, 0);
    });

    test('work.service.dart does not import performance or accomplishment services', () {
      final src = File('lib/services/work.service.dart').readAsStringSync();
      expect(src.contains('performance.service'), isFalse);
      expect(src.contains('accomplishment.service'), isFalse);
      expect(src.contains('task.service'), isFalse);
    });
  });
}
