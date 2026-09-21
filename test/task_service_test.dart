import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/shared/error_reporting.dart';
import 'package:taskr/shared/write_ack.dart';

import 'helpers/harness.dart';

/// A Firestore whose collection-group queries fail the way the real one does
/// while a composite index is still building.
class _NoCollectionGroups extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collectionGroup(String collectionPath) => _FailingQuery();
}

// ignore: subtype_of_sealed_class
/// Accepts any query shaping and fails on read, which is where the real SDK
/// reports a missing index.
class _FailingQuery implements CollectionReference<Map<String, dynamic>> {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #get) {
      return Future<QuerySnapshot<Map<String, dynamic>>>.error(
        FirebaseException(plugin: 'cloud_firestore', code: 'failed-precondition', message: 'index building'),
      );
    }
    return this;
  }
}

void main() {
  // reportError surfaces a snackbar through the global messenger, which needs a
  // binding even when no MaterialApp is mounted.
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late TaskService service;
  const uid = 'u1';

  setUp(() async {
    env = await TestEnv.create();
    service = TaskService();
  });
  tearDown(() => env.dispose());

  Task t(String title, {String? date, Effort priority = Effort.medium, String? id}) =>
      Task(id: id, added: 1, title: title, dueDate: date, priority: priority);

  Future<List<String>> order(String date) async {
    final doc = await env.col('tasks').doc(date).get();
    return List<String>.from(doc.data()?['taskOrder'] ?? const []);
  }

  Future<Map<String, dynamic>?> item(String date, String id) async {
    final doc = await env.col('tasks').doc(date).collection('items').doc(id).get();
    return doc.data();
  }

  Future<Task?> reload(String date, String id) async {
    final data = await item(date, id);
    if (data == null) return null;
    return Task.fromJson({...data, 'id': id, 'tags': <dynamic>[]});
  }

  Future<Map<String, dynamic>?> countdown(String id) async => (await env.col('countdowns').doc(id).get()).data();

  Future<Map<String, dynamic>?> perf(String date) async => (await env.col('performance').doc(date).get()).data();

  final today = DateService().getString(DateTime.now());

  group('addTask', () {
    test('stamps userId and records the id in taskOrder', () async {
      final id = await service.addTask(t('a', date: '2026-08-01'));
      expect((await item('2026-08-01', id))!['userId'], uid);
      expect(await order('2026-08-01'), [id]);
    });

    test('appends a second untimed task after the first', () async {
      final a = await service.addTask(t('a', date: '2026-08-01'));
      final b = await service.addTask(t('b', date: '2026-08-01'));
      expect(await order('2026-08-01'), [a, b]);
    });

    test('a backlog task lands in the unassigned partition', () async {
      final id = await service.addTask(t('later'));
      expect(await item(TaskService.defaultUnassignedDate, id), isNotNull);
      expect(await order(TaskService.defaultUnassignedDate), [id]);
    });

    test('throws with no signed-in user', () async {
      AuthService().user = null;
      expect(() => service.addTask(t('a')), throwsA(isA<String>()));
    });

    // Regression: taskOrder listing an id with no document (deleted on another
    // device, or a partially-populated offline cache) threw `Bad state: No
    // element` out of getTasksInOrder and aborted the whole save.
    test('a stale id in taskOrder is skipped instead of failing the save', () async {
      final a = await service.addTask(t('a', date: '2026-08-01'));
      await env.col('tasks').doc('2026-08-01').set({
        'taskOrder': [a, 'ghost-id']
      });

      expect(await service.getTasksInOrder(uid, '2026-08-01'), hasLength(1));

      final b = await service.addTask(t('b', date: '2026-08-01'));
      expect(await order('2026-08-01'), contains(b));
      expect((await item('2026-08-01', b))!['title'], 'b');
    });
  });

  group('countdown index', () {
    test('countdownEligible', () {
      expect(service.countdownEligible(Task(added: 1, title: 'x', countdown: true, dueDate: '2026-01-01')), isTrue);
      expect(service.countdownEligible(Task(added: 1, title: 'x', countdown: true)), isFalse);
      expect(service.countdownEligible(Task(added: 1, title: 'x', countdown: false, dueDate: '2026-01-01')), isFalse);
      expect(
          service.countdownEligible(
              Task(added: 1, title: 'x', countdown: true, dueDate: '2026-01-01', completed: true)),
          isFalse);
      expect(
          service.countdownEligible(Task(
              added: 1,
              title: 'x',
              countdown: true,
              dueDate: '2026-01-01',
              multiDayGroupId: 'g',
              multiDayPosition: 'middle')),
          isFalse);
      expect(
          service.countdownEligible(Task(
              added: 1, title: 'x', countdown: true, dueDate: '2026-01-01', multiDayGroupId: 'g', multiDayPosition: 'start')),
          isTrue);
    });

    test('adding a countdown task writes the index with its label', () async {
      final id = await service.addTask(
          Task(added: 1, title: 'trip', dueDate: '2026-12-01', countdown: true, countdownLabel: 'Vacation'));
      expect(await countdown(id), {'title': 'trip', 'dueDate': '2026-12-01', 'label': 'Vacation'});
      final list = await service.streamCountdowns(uid).first;
      expect(list.single['taskId'], id);
    });

    test('updating a task out of the index removes it', () async {
      final task = Task(added: 1, title: 'trip', dueDate: '2026-12-01', countdown: true);
      final id = await service.addTask(task);
      expect(await countdown(id), isNotNull);
      await service.updateTask(id, task.copyWith(countdown: false), task);
      expect(await countdown(id), isNull);
    });

    test('an empty countdownLabel is not written', () async {
      final id = await service
          .addTask(Task(added: 1, title: 'trip', dueDate: '2026-12-01', countdown: true, countdownLabel: ''));
      expect((await countdown(id))!.containsKey('label'), isFalse);
    });
  });

  group('task order', () {
    test('getTaskOrder and taskOrderStream are empty for an unknown day', () async {
      expect(await service.getTaskOrder(uid, '2030-01-01'), isEmpty);
      expect(await service.taskOrderStream(uid, null).first, isEmpty);
    });

    test('updateTaskOrder rewrites the day order', () async {
      final a = await service.addTask(t('a', date: '2026-08-01'));
      final b = await service.addTask(t('b', date: '2026-08-01'));
      await service.updateTaskOrder(uid, [b, a], '2026-08-01');
      expect(await order('2026-08-01'), [b, a]);
      expect(await service.taskOrderStream(uid, '2026-08-01').first, [b, a]);
    });

    test('getTasks returns the raw rows with ids', () async {
      final a = await service.addTask(t('a', date: '2026-08-01'));
      final rows = await service.getTasks(uid, '2026-08-01');
      expect(rows.single['id'], a);
      expect(rows.single['title'], 'a');
    });
  });

  group('streamTasks', () {
    test('resolves tag ids and tag maps, dropping unknown tags', () async {
      final tagA = Tag(id: 'ta', label: 'Work');
      final tagB = Tag(id: 'tb', label: 'Home');
      final a = await service.addTask(Task(added: 1, title: 'a', dueDate: '2026-08-01', tags: [tagA]));
      final b = await service.addTask(Task(added: 1, title: 'b', dueDate: '2026-08-01', tags: [tagB]));
      // A legacy row that stores tags as maps, plus an unknown id.
      await env.col('tasks').doc('2026-08-01').collection('items').doc(b).update({
        'tags': [
          {'id': 'tb'},
          'unknown',
        ]
      });

      final tasks = await service.streamTasks(uid, '2026-08-01', [tagA, tagB]).first;
      expect(tasks.map((x) => x.id), [a, b]);
      expect(tasks[0].tags.single.label, 'Work');
      expect(tasks[1].tags.single.label, 'Home');
    });

    test('ignores ids in taskOrder with no document', () async {
      final a = await service.addTask(t('a', date: '2026-08-01'));
      await env.col('tasks').doc('2026-08-01').set({
        'taskOrder': ['ghost', a]
      });
      final tasks = await service.streamTasks(uid, '2026-08-01', const []).first;
      expect(tasks.map((x) => x.id), [a]);
    });

    test('the unassigned partition is used when no date is given', () async {
      final a = await service.addTask(t('a'));
      final tasks = await service.streamTasks(uid, null, const []).first;
      expect(tasks.single.id, a);
    });
  });

  group('subtasks', () {
    Future<Task> parentTask({String? date}) async {
      final p = t('parent', date: date);
      final id = await service.addTask(p);
      return p.copyWith(id: id);
    }

    test('addSubtask converts the parent into a backlog container on the first child', () async {
      final parent = await parentTask(date: '2026-08-01');
      final childId = await service.addSubtask(parent, '  child one ', priority: Effort.high);

      // The first child inherits the parent's date.
      final child = await reload('2026-08-01', childId);
      expect(child!.title, 'child one');
      expect(child.parentId, parent.id);
      expect(child.parentTitle, 'parent');
      expect(child.priority, Effort.high);

      // The parent moved to the backlog with seeded counters.
      expect(await item('2026-08-01', parent.id!), isNull);
      expect(await order('2026-08-01'), isNot(contains(parent.id)));
      final moved = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(moved!['childCount'], 1);
      expect(moved['childCompletedCount'], 0);
      expect(moved.containsKey('dueDate'), isFalse);
      expect(await order(TaskService.defaultUnassignedDate), contains(parent.id));
    });

    test('later children start unassigned and bump the counter', () async {
      final parent = await parentTask();
      await service.addSubtask(parent, 'one');
      final containerParent = parent.copyWith(childCount: 1);
      final secondId = await service.addSubtask(containerParent, 'two');
      expect(await item(TaskService.defaultUnassignedDate, secondId), isNotNull);
      final stored = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(stored!['childCount'], 2);
      expect(stored['completed'], isFalse);
    });

    test('addSubtask refuses recurring and multi-day parents, and no user', () async {
      final parent = await parentTask();
      const refusal = "Recurring and multi-day tasks can't have subtasks";
      expect(() => service.addSubtask(parent.copyWith(recurringTemplateId: 'r'), 'x'), throwsA(refusal));
      expect(() => service.addSubtask(parent.copyWith(multiDayGroupId: 'g'), 'x'), throwsA(refusal));
      AuthService().user = null;
      expect(() => service.addSubtask(parent, 'x'), throwsA(isA<String>()));
    });

    test('getSubtasksOf finds children across partitions', () async {
      final parent = await parentTask(date: '2026-08-01');
      final first = await service.addSubtask(parent, 'one');
      final second = await service.addSubtask(parent.copyWith(childCount: 1), 'two');
      final children = await service.getSubtasksOf(parent.id!);
      expect(children.map((c) => c.id), unorderedEquals([first, second]));
    });

    test('toggleSubtaskComplete keeps the parent counters in step and auto-completes', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      final twoId = await service.addSubtask(parent.copyWith(childCount: 1), 'two');
      final one = (await reload(TaskService.defaultUnassignedDate, oneId))!;
      final two = (await reload(TaskService.defaultUnassignedDate, twoId))!;

      await service.toggleSubtaskComplete(one, true);
      var stored = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(stored!['childCompletedCount'], 1);
      expect(stored['completed'], isFalse);
      expect((await item(TaskService.defaultUnassignedDate, oneId))!['completedTime'], isNotNull);

      await service.toggleSubtaskComplete(two, true);
      stored = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(stored!['childCompletedCount'], 2);
      expect(stored['completed'], isTrue);

      await service.toggleSubtaskComplete(one, false);
      stored = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(stored!['childCompletedCount'], 1);
      expect(stored['completed'], isFalse);
      expect((await item(TaskService.defaultUnassignedDate, oneId))!['completedTime'], isNull);
    });

    test('toggleSubtaskComplete tolerates a missing parent document', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      final one = (await reload(TaskService.defaultUnassignedDate, oneId))!;
      await env.col('tasks').doc(TaskService.defaultUnassignedDate).collection('items').doc(parent.id).delete();
      await service.toggleSubtaskComplete(one, true);
      expect((await item(TaskService.defaultUnassignedDate, oneId))!['completed'], isTrue);
    });

    test('deleteParent with keepChildren orphans the children', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      await service.deleteParent(parent, keepChildren: true);
      final child = await item(TaskService.defaultUnassignedDate, oneId);
      expect(child, isNotNull);
      expect(child!.containsKey('parentId'), isFalse);
      expect(child.containsKey('parentTitle'), isFalse);
      expect(await item(TaskService.defaultUnassignedDate, parent.id!), isNull);
    });

    test('deleteParent without keepChildren removes them too', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      await service.deleteParent(parent, keepChildren: false);
      expect(await item(TaskService.defaultUnassignedDate, oneId), isNull);
      expect(await item(TaskService.defaultUnassignedDate, parent.id!), isNull);
    });

    test('recomputeParentCounters recovers from drift', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      await env.col('tasks').doc(TaskService.defaultUnassignedDate).collection('items').doc(oneId).update({
        'completed': true,
      });
      await env.col('tasks').doc(TaskService.defaultUnassignedDate).collection('items').doc(parent.id).update({
        'childCount': 9,
        'childCompletedCount': 0,
      });
      await service.recomputeParentCounters(parent.id!);
      final stored = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(stored!['childCount'], 1);
      expect(stored['childCompletedCount'], 1);
      expect(stored['completed'], isTrue);
    });

    test('recomputeParentCounters with no children left leaves the parent open', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      await env.col('tasks').doc(TaskService.defaultUnassignedDate).collection('items').doc(oneId).delete();
      await service.recomputeParentCounters(parent.id!);
      final stored = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(stored!['childCount'], 0);
      expect(stored['childCompletedCount'], 0);
      expect(stored['completed'], isFalse);
    });

    test('scheduleSubtask moves the child between partitions', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      final one = (await reload(TaskService.defaultUnassignedDate, oneId))!;
      await service.scheduleSubtask(one, '2026-08-05');
      expect(await item(TaskService.defaultUnassignedDate, oneId), isNull);
      final moved = await reload('2026-08-05', oneId);
      expect(moved!.parentId, parent.id);
      expect(await order('2026-08-05'), contains(oneId));

      await service.scheduleSubtask(moved, null);
      expect(await item('2026-08-05', oneId), isNull);
      expect(await item(TaskService.defaultUnassignedDate, oneId), isNotNull);
    });

    test('deleteSubtask reconciles the parent, and a plain task has no parent to touch', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      final twoId = await service.addSubtask(parent.copyWith(childCount: 1), 'two');
      final two = (await reload(TaskService.defaultUnassignedDate, twoId))!;
      await service.toggleSubtaskComplete((await reload(TaskService.defaultUnassignedDate, oneId))!, true);

      await service.deleteSubtask(two);
      final stored = await item(TaskService.defaultUnassignedDate, parent.id!);
      expect(stored!['childCount'], 1);
      expect(stored['completed'], isTrue);

      final loneId = await service.addTask(t('lone'));
      await service.deleteSubtask((await reload(TaskService.defaultUnassignedDate, loneId))!);
      expect(await item(TaskService.defaultUnassignedDate, loneId), isNull);
    });

    test('assignParentDate cascades only unassigned, incomplete children', () async {
      final parent = await parentTask();
      final oneId = await service.addSubtask(parent, 'one');
      final twoId = await service.addSubtask(parent.copyWith(childCount: 1), 'two');
      final threeId = await service.addSubtask(parent.copyWith(childCount: 2), 'three');
      await service.toggleSubtaskComplete((await reload(TaskService.defaultUnassignedDate, twoId))!, true);
      await service.scheduleSubtask((await reload(TaskService.defaultUnassignedDate, threeId))!, '2026-01-01');

      await service.assignParentDate(parent, '2026-08-09');
      expect(await item('2026-08-09', oneId), isNotNull);
      expect(await item(TaskService.defaultUnassignedDate, twoId), isNotNull);
      expect(await item('2026-01-01', threeId), isNotNull);
    });

    test('streamSubtasks re-subscribes after a query error instead of dying', () async {
      // fake_cloud_firestore rejects `parentId != null` in a collection-group
      // query, which is exactly the "index still building" failure the retry
      // exists for: the stream must neither error out nor complete.
      final parent = await parentTask();
      await service.addSubtask(parent, 'one');
      final events = <Object>[];
      final sub = service.streamSubtasks(uid, [Tag(id: 'tx', label: 'X')]).listen(
        events.add,
        onError: events.add,
        onDone: () => events.add('done'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();
      expect(events, isEmpty);
    });
  });

  group('dividers', () {
    test('addDivider is inserted at the top of the day', () async {
      final a = await service.addTask(t('a', date: '2026-08-01'));
      final d = await service.addDivider('Morning', '2026-08-01');
      expect(await order('2026-08-01'), [d, a]);
      expect((await item('2026-08-01', d))!['type'], 'divider');
    });

    test('addDivider defaults to the backlog and needs a user', () async {
      final d = await service.addDivider('Later', null);
      expect(await order(TaskService.defaultUnassignedDate), [d]);
      AuthService().user = null;
      expect(() => service.addDivider('x', null), throwsA(isA<String>()));
    });
  });

  group('updateTask', () {
    test('rewrites the document and keeps the owner stamp', () async {
      final task = t('a', date: '2026-08-01');
      final id = await service.addTask(task);
      await service.updateTask(id, task.copyWith(title: 'renamed'), task);
      final stored = await item('2026-08-01', id);
      expect(stored!['title'], 'renamed');
      expect(stored['userId'], uid);
    });

    test('moves points when a completed task changes priority', () async {
      final old = Task(added: 1, title: 'a', dueDate: '2026-08-01', priority: Effort.low, completed: true);
      final id = await service.addTask(old);
      await service.updateTask(id, old.copyWith(priority: Effort.high), old);
      final p = await perf('2026-08-01');
      // low (1) removed, high (3) added, starting from nothing: first write
      // initialises with the points, then the add applies +3.
      expect(p!['completed']['ALL'], 4);
    });

    test('an incomplete task changing priority moves no points', () async {
      final old = t('a', date: '2026-08-01', priority: Effort.low);
      final id = await service.addTask(old);
      await service.updateTask(id, old.copyWith(priority: Effort.high), old);
      expect(await perf('2026-08-01'), isNull);
      expect((await item('2026-08-01', id))!['priority'], 'high');
    });

    test('a completed task keeping its priority moves no points either', () async {
      final old = Task(added: 1, title: 'a', dueDate: '2026-08-01', priority: Effort.low, completed: true);
      final id = await service.addTask(old);
      await service.updateTask(id, old.copyWith(title: 'renamed'), old);
      expect(await perf('2026-08-01'), isNull);
    });

    test('throws with no user', () async {
      AuthService().user = null;
      expect(() => service.updateTask('x', t('a'), t('a')), throwsA(isA<String>()));
    });
  });

  group('updateTaskByKey', () {
    test('completing a countdown task drops it from the index and scores it', () async {
      final task = Task(added: 1, title: 'trip', dueDate: '2026-12-01', countdown: true, priority: Effort.high);
      final id = await service.addTask(task);
      await service.updateTaskByKey({'completed': true}, task.copyWith(id: id));
      expect(await countdown(id), isNull);
      expect((await item('2026-12-01', id))!['completed'], isTrue);
      expect((await perf('2026-12-01'))!['completed']['ALL'], 3);
    });

    test('un-completing a countdown task keeps its index entry', () async {
      final task = Task(added: 1, title: 'trip', dueDate: '2026-12-01', countdown: true);
      final id = await service.addTask(task);
      expect(await countdown(id), isNotNull);
      await env.col('tasks').doc('2026-12-01').collection('items').doc(id).update({'completed': true});
      await service.updateTaskByKey({'completed': false}, task.copyWith(id: id, completed: true));
      expect(await countdown(id), isNotNull);
      expect((await item('2026-12-01', id))!['completed'], isFalse);
    });

    test('a non-completion update touches nothing else', () async {
      final task = t('a', date: '2026-08-01');
      final id = await service.addTask(task);
      await service.updateTaskByKey({'title': 'b'}, task.copyWith(id: id));
      expect((await item('2026-08-01', id))!['title'], 'b');
      expect(await perf('2026-08-01'), isNull);
    });

    test('throws with no user', () async {
      AuthService().user = null;
      expect(() => service.updateTaskByKey({}, t('a', id: 'x')), throwsA(isA<String>()));
    });
  });

  group('deleteTask / restoreTask', () {
    test('removes the doc, the order entry, its points and its countdown', () async {
      final task = Task(
          added: 1, title: 'trip', dueDate: '2026-12-01', countdown: true, priority: Effort.high, completed: true);
      final id = await service.addTask(task);
      await service.updateTaskByKey({'completed': true}, task.copyWith(id: id));
      // The countdown index ignores completed tasks, so seed one to prove delete clears it.
      await env.col('countdowns').doc(id).set({'title': 'trip'});

      await service.deleteTask(task.copyWith(id: id));
      expect(await item('2026-12-01', id), isNull);
      expect(await order('2026-12-01'), isNot(contains(id)));
      expect(await countdown(id), isNull);
      expect((await perf('2026-12-01'))!['completed']['ALL'], 0);
    });

    test('cancels a scheduled reminder without blocking the delete', () async {
      env.functions['cancelReminder'] = (_) => null;
      final task = Task(added: 1, title: 'a', dueDate: '2026-08-01', reminderTaskName: 'queues/q/tasks/1');
      final id = await service.addTask(task);
      await service.deleteTask(task.copyWith(id: id));
      await Future<void>.delayed(Duration.zero);
      expect(env.functionCalls.map((c) => c.name), contains('cancelReminder'));
      expect(await item('2026-08-01', id), isNull);
    });

    test('a failing reminder cancel is reported, not thrown', () async {
      env.functions['cancelReminder'] = (_) => throw Exception('boom');
      final task = Task(added: 1, title: 'a', dueDate: '2026-08-01', reminderTaskName: 'queues/q/tasks/1');
      final id = await service.addTask(task);
      await service.deleteTask(task.copyWith(id: id));
      await Future<void>.delayed(Duration.zero);
      expect(await item('2026-08-01', id), isNull);
    });

    test('a completed divider carries no points to remove', () async {
      final divider = Task(added: 1, title: 'sep', dueDate: '2026-08-01', type: 'divider', completed: true);
      final id = await service.addTask(divider);
      await service.deleteTask(divider.copyWith(id: id));
      expect(await perf('2026-08-01'), isNull);
    });

    test('restoreTask brings back the doc, order entry and points', () async {
      final task = Task(added: 1, title: 'a', dueDate: '2026-08-01', priority: Effort.medium, completed: true);
      final id = await service.addTask(task);
      await service.deleteTask(task.copyWith(id: id));

      await service.restoreTask(task.copyWith(id: id));
      expect((await item('2026-08-01', id))!['userId'], uid);
      expect(await order('2026-08-01'), contains(id));
      // The perf doc did not exist when the delete ran, so that write seeded
      // ALL with the points instead of subtracting; the restore then adds 2.
      expect((await perf('2026-08-01'))!['completed']['ALL'], 4);
    });

    test('restoreTask of an incomplete backlog task writes no points', () async {
      await service.restoreTask(t('a', id: 'fixed'));
      expect(await item(TaskService.defaultUnassignedDate, 'fixed'), isNotNull);
      expect(await env.col('performance').get().then((s) => s.docs), isEmpty);
    });

    test('both throw with no user', () async {
      AuthService().user = null;
      expect(() => service.deleteTask(t('a', id: 'x')), throwsA(isA<String>()));
      expect(() => service.restoreTask(t('a', id: 'x')), throwsA(isA<String>()));
    });
  });

  group('pushTask', () {
    // Regression: push used to delete + re-add with a NEW id, breaking id-keyed
    // links (e.g. a goal generation's taskIds). It now moves the doc, same id.
    test('moves the task to the next day keeping the same document id', () async {
      final id = await service.addTask(t('goalie', date: '2020-01-01', priority: Effort.high));

      await service.pushTask(t('goalie', date: '2020-01-01', priority: Effort.high, id: id));

      expect(await order('2020-01-01'), isNot(contains(id)));
      expect(await item('2020-01-01', id), isNull);
      expect(await order('2020-01-02'), contains(id));
      final moved = await item('2020-01-02', id);
      expect(moved!['pushCount'], 1);
      expect((await perf('2020-01-01'))!['pushed']['ALL'], 3);
    });

    test("pushing today's task also decrements the running score", () async {
      final id = await service.addTask(t('now', date: today, priority: Effort.low));
      await service.pushTask(t('now', date: today, priority: Effort.low, id: id));
      expect((await env.userDoc())!['currentScore'], -1);
    });

    test('a task with no due date is pushed from today', () async {
      final id = await service.addTask(t('backlog'));
      await service.pushTask(t('backlog', id: id));
      final tomorrow = DateService().incrementDate(DateTime.now());
      expect(await item(tomorrow, id), isNotNull);
      expect((await perf(today))!['pushed']['ALL'], 2);
    });

    test('cancels a scheduled reminder before moving', () async {
      env.functions['cancelReminder'] = (_) => null;
      final task = Task(added: 1, title: 'a', dueDate: '2020-01-01', reminderTaskName: 'queues/q/tasks/1');
      final id = await service.addTask(task);
      await service.pushTask(task.copyWith(id: id));
      // Exactly once: the awaited cancel clears the field so deleteTask does not
      // fire the same callable again.
      expect(env.functionCalls.where((c) => c.name == 'cancelReminder'), hasLength(1));
      final moved = await item('2020-01-02', id);
      expect(moved!.containsKey('reminderTaskName'), isFalse);
    });

    test('a failing reminder cancel aborts the push so the task stays put', () async {
      env.functions['cancelReminder'] = (_) => throw Exception('down');
      final task = Task(added: 1, title: 'a', dueDate: '2020-01-01', reminderTaskName: 'queues/q/tasks/1');
      final id = await service.addTask(task);
      await expectLater(service.pushTask(task.copyWith(id: id)), throwsException);
      expect(await item('2020-01-01', id), isNotNull);
      expect(await item('2020-01-02', id), isNull);
    });

    test('pushing a task due on another day leaves the running score alone', () async {
      // Same calendar day and month as today, a year ago: only a check on all
      // three date parts keeps this from counting as "today".
      final now = DateTime.now();
      final lastYear = DateService().getString(DateTime(now.year - 1, now.month, now.day));
      final id = await service.addTask(t('old', date: lastYear));
      await service.pushTask(t('old', date: lastYear, id: id));
      expect((await env.userDoc())?['currentScore'] ?? 0, 0);
      expect((await perf(lastYear))!['pushed']['ALL'], 2);
    });

    test('each push adds one to the running push count', () async {
      final task = Task(added: 1, title: 'again', dueDate: '2020-01-01', pushCount: 2);
      final id = await service.addTask(task);
      await service.pushTask(task.copyWith(id: id));
      expect((await item('2020-01-02', id))!['pushCount'], 3);
    });

    test('a series reminder inside the window is handed to Cloud Tasks', () async {
      env.functions['scheduleReminder'] = (_) => {'reminderTaskName': 'queues/q/tasks/new'};
      final written = await service.createRecurringSeries(
        RecurringTask(
          recurrenceType: 'Daily',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 10)),
          reminderTimeOfDay: '23:59',
        ),
        t('standup'),
      );
      final target = written.occurrences[2];
      final newDate = DateService().incrementDate(DateService().getDate(target.dueDate!));
      await service.pushTask(target);
      expect(env.functionCalls.where((c) => c.name == 'scheduleReminder'), isNotEmpty);
      expect((await item(newDate, target.id!))!['reminderTaskName'], 'queues/q/tasks/new');
    });
  });

  group('multi-day groups', () {
    Future<Task> seedGroup(String start, int days) async {
      Task? template;
      for (var i = 0; i < days; i++) {
        final date = DateService().getString(DateService().getDate(start).add(Duration(days: i)));
        final position = i == 0 ? 'start' : (i == days - 1 ? 'end' : 'middle');
        final task = Task(
            added: 1,
            title: 'conf',
            dueDate: date,
            multiDayGroupId: 'g1',
            multiDayPosition: position,
            priority: Effort.high);
        final id = await service.addTask(task);
        template ??= task.copyWith(id: id);
      }
      return template!;
    }

    test('getMultiDayGroup walks backward and forward from any known day', () async {
      await seedGroup('2026-03-10', 3);
      final group = await service.getMultiDayGroup('g1', knownDate: '2026-03-11');
      expect(group.map((x) => x.dueDate), ['2026-03-10', '2026-03-11', '2026-03-12']);
      expect(await service.getMultiDayGroup('nope', knownDate: '2026-03-11'), isEmpty);
      AuthService().user = null;
      expect(() => service.getMultiDayGroup('g1', knownDate: '2026-03-11'), throwsA(isA<String>()));
    });

    test('updateMultiDayEndDate extends the group and re-labels positions', () async {
      final template = await seedGroup('2026-03-10', 2);
      await service.updateMultiDayEndDate('g1', '2026-03-13', template);
      final group = await service.getMultiDayGroup('g1', knownDate: '2026-03-10');
      expect(group.map((x) => x.dueDate), ['2026-03-10', '2026-03-11', '2026-03-12', '2026-03-13']);
      expect(group.map((x) => x.multiDayPosition), ['start', 'middle', 'middle', 'end']);
    });

    test('updateMultiDayEndDate shrinks the group and deletes leftovers', () async {
      final template = await seedGroup('2026-03-10', 4);
      await service.updateMultiDayEndDate('g1', '2026-03-11', template);
      final group = await service.getMultiDayGroup('g1', knownDate: '2026-03-10');
      expect(group.map((x) => x.dueDate), ['2026-03-10', '2026-03-11']);
      expect(group.map((x) => x.multiDayPosition), ['start', 'end']);
      expect(await item('2026-03-12', group.first.id!), isNull);
    });

    test('updateMultiDayEndDate ignores an end on or before the start, or a missing group', () async {
      final template = await seedGroup('2026-03-10', 2);
      await service.updateMultiDayEndDate('g1', '2026-03-10', template);
      expect((await service.getMultiDayGroup('g1', knownDate: '2026-03-10')).length, 2);
      await service.updateMultiDayEndDate('missing', '2026-03-15', template);
      expect((await service.getMultiDayGroup('g1', knownDate: '2026-03-10')).length, 2);
    });
  });

  group('callRemoteMethod', () {
    test('invokes the callable and logs the result', () async {
      env.functions['ping'] = (p) => {'ok': p};
      await service.callRemoteMethod('ping', {'a': 1});
      expect(env.functionCalls.single.name, 'ping');
    });

    test('reports a failure instead of throwing', () async {
      env.functions['ping'] = (_) => throw Exception('down');
      await service.callRemoteMethod('ping', null);
    });

    testWidgets('the failure is surfaced to the user as an error snackbar', (tester) async {
      resetErrorSnackDedupe();
      await pumpApp(tester, const SizedBox(), wrapInScaffold: true);
      env.functions['ping'] = (_) => throw Exception('down');
      await service.callRemoteMethod('ping', null);
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Server call "ping" failed'), findsOneWidget);
    });
  });

  group('recurring series', () {
    RecurringTask daily({int days = 5, String? reminder}) => RecurringTask(
          recurrenceType: 'Daily',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(days: days)),
          reminderTimeOfDay: reminder,
        );

    test('createRecurringSeries writes the template, every occurrence and the countdown index', () async {
      final proto = Task(added: 1, title: 'standup', countdown: true, priority: Effort.medium);
      final written = await service.createRecurringSeries(daily(days: 3, reminder: '09:00'), proto);
      expect(written.ack, WriteAck.confirmed);
      expect(written.occurrences, hasLength(4));
      final template = await service.getRecurringTemplate(written.templateId);
      expect(template.lastMaterializedDate, written.occurrences.last.dueDate);
      for (final occ in written.occurrences) {
        expect(occ.reminderTime, isNotNull);
        expect((await item(occ.dueDate!, occ.id!))!['recurringTemplateId'], written.templateId);
        expect(await order(occ.dueDate!), contains(occ.id));
        expect(await countdown(occ.id!), isNotNull);
      }
    });

    test('createRecurringSeries and materializeOccurrences need a user', () async {
      AuthService().user = null;
      expect(() => service.createRecurringSeries(daily(), t('x')), throwsA(isA<String>()));
      expect(
          () => service.materializeOccurrences(templateId: 'a', template: daily(), prototype: t('x'), dates: const []),
          throwsA(isA<String>()));
    });

    test('materializeOccurrences with no dates is a confirmed no-op', () async {
      final r = await service.materializeOccurrences(templateId: 'a', template: daily(), prototype: t('x'), dates: const []);
      expect(r.ack, WriteAck.confirmed);
      expect(r.occurrences, isEmpty);
    });

    test('materializeOccurrences advances the watermark and chunks large batches', () async {
      final written = await service.createRecurringSeries(daily(days: 1), t('standup'));
      final base = DateTime.utc(2030, 1, 1);
      final dates = List.generate(250, (i) => base.add(Duration(days: i)));
      final r = await service.materializeOccurrences(
        templateId: written.templateId,
        template: daily(),
        prototype: t('standup'),
        dates: dates,
      );
      expect(r.occurrences, hasLength(250));
      expect((await service.getRecurringTemplate(written.templateId)).lastMaterializedDate, '2030-09-07');
      expect(await item('2030-09-07', r.occurrences.last.id!), isNotNull);
    });

    test('getRecurringTemplate throws for an unknown id', () async {
      expect(() => service.getRecurringTemplate('nope'), throwsA(isA<Exception>()));
    });

    test('seriesInstances honours fromDate and skips other users', () async {
      final written = await service.createRecurringSeries(daily(days: 4), t('standup'));
      final all = await service.seriesInstances(written.templateId);
      expect(all, hasLength(5));
      final fromDay3 = await service.seriesInstances(written.templateId, fromDate: written.occurrences[2].dueDate);
      expect(fromDay3, hasLength(3));
    });

    test('tasksWithPendingReminders is empty with no user', () async {
      AuthService().user = null;
      expect(await service.tasksWithPendingReminders(), isEmpty);
    });

    test('generateInstancesInWindow expands from the given start', () async {
      final dates = service.generateInstancesInWindow(daily(days: 3), DateTime.now());
      expect(dates, hasLength(4));
    });

    test('deleteRecurringTemplate removes outstanding occurrences, keeps completed ones, cancels reminders',
        () async {
      env.functions['cancelReminder'] = (_) => null;
      final written = await service.createRecurringSeries(daily(days: 3), t('standup'));
      final done = written.occurrences[1];
      await env.col('tasks').doc(done.dueDate).collection('items').doc(done.id).update({'completed': true});
      final scheduled = written.occurrences[2];
      await env.col('tasks').doc(scheduled.dueDate).collection('items').doc(scheduled.id).update({
        'reminderTaskName': 'queues/q/tasks/s',
      });

      await service.deleteRecurringTemplate(
        written.occurrences.first.copyWith(recurringTemplateId: written.templateId),
        daily(days: 3),
      );

      expect(await item(done.dueDate!, done.id!), isNotNull);
      expect(await item(written.occurrences.first.dueDate!, written.occurrences.first.id!), isNull);
      expect(await item(scheduled.dueDate!, scheduled.id!), isNull);
      // One cancel per scheduled occurrence, not two.
      expect(env.functionCalls.where((c) => c.name == 'cancelReminder'), hasLength(1));
      expect((await env.col('recurring').doc(written.templateId).get()).exists, isFalse);
    });

    test('updateRecurringTemplate rewrites the series and enqueues reminders', () async {
      env.functions['scheduleReminder'] = (_) => {'reminderTaskName': 'queues/q/tasks/new'};
      final written = await service.createRecurringSeries(daily(days: 2), t('standup'));
      final first = written.occurrences.first;

      await service.updateRecurringTemplate(
        first.copyWith(title: 'renamed'),
        daily(days: 1, reminder: '23:59'),
      );

      final templates = await env.col('recurring').get();
      expect(templates.docs, hasLength(1));
      expect(templates.docs.single.id, isNot(written.templateId));
      final instances = await service.seriesInstances(templates.docs.single.id);
      expect(instances, hasLength(2));
      expect(instances!.every((x) => x.title == 'renamed'), isTrue);
      expect(env.functionCalls.where((c) => c.name == 'scheduleReminder'), hasLength(2));
    });

    test('updateRecurringTemplate rethrows when the template is missing', () async {
      expect(
        () => service.updateRecurringTemplate(t('x', id: 'a').copyWith(recurringTemplateId: 'gone'), daily()),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('while a collection-group index is still building', () {
    RecurringTask daily(int days) => RecurringTask(
          recurrenceType: 'Daily',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(Duration(days: days)),
        );

    setUp(() => service.db = _NoCollectionGroups());

    test('seriesInstances degrades to null, bounded or not', () async {
      expect(await service.seriesInstances('abc', fromDate: '2026-01-01'), isNull);
      expect(await service.seriesInstances('abc'), isNull);
    });

    test('tasksWithPendingReminders degrades to nothing', () async {
      expect(await service.tasksWithPendingReminders(), isEmpty);
    });

    test('deleteRecurringTemplate falls back to a per-date scan', () async {
      final written = await service.createRecurringSeries(daily(3), t('standup'));
      final done = written.occurrences[1];
      await service.taskCollection(uid, done.dueDate!).doc(done.id).update({'completed': true});

      await service.deleteRecurringTemplate(
        written.occurrences.first.copyWith(recurringTemplateId: written.templateId),
        daily(3),
      );

      for (final occ in written.occurrences) {
        final doc = await service.taskCollection(uid, occ.dueDate!).doc(occ.id).get();
        expect(doc.exists, occ.id == done.id, reason: occ.dueDate);
      }
    });
  });

  group('reminder bookkeeping', () {
    test('tasksWithPendingReminders returns an unscheduled reminder inside the window', () async {
      final soon = DateTime.now().toUtc().add(const Duration(days: 3)).toIso8601String();
      final id = await service.addTask(Task(added: 1, title: 'a', dueDate: '2027-05-30', reminderTime: soon));
      expect((await service.tasksWithPendingReminders()).map((x) => x.id), [id]);
    });

    test('an occurrence whose template is gone pushes without a reminder', () async {
      final written = await service.createRecurringSeries(
        RecurringTask(
          recurrenceType: 'Daily',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 5)),
          reminderTimeOfDay: '08:30',
        ),
        t('standup'),
      );
      await env.col('recurring').doc(written.templateId).delete();
      final target = written.occurrences[3];
      final newDate = DateService().incrementDate(DateService().getDate(target.dueDate!));
      await service.pushTask(target);
      expect((await item(newDate, target.id!))!.containsKey('reminderTime'), isFalse);
    });

    test('deleteRecurringTemplate reports a failure instead of throwing', () async {
      await service.deleteRecurringTemplate(t('orphan', id: 'x'), RecurringTask(recurrenceType: 'Daily'));
    });

    testWidgets('a reminder that cannot be cancelled stops the series delete and is reported', (tester) async {
      resetErrorSnackDedupe();
      await pumpApp(tester, const SizedBox(), wrapInScaffold: true);
      env.functions['cancelReminder'] = (_) => throw Exception('down');
      final written = await service.createRecurringSeries(
        RecurringTask(
          recurrenceType: 'Daily',
          startDate: DateTime.now(),
          endDate: DateTime.now().add(const Duration(days: 2)),
        ),
        t('standup'),
      );
      final scheduled = written.occurrences.last;
      await env.col('tasks').doc(scheduled.dueDate).collection('items').doc(scheduled.id).update({
        'reminderTaskName': 'queues/q/tasks/s',
      });

      await service.deleteRecurringTemplate(
        written.occurrences.first.copyWith(recurringTemplateId: written.templateId),
        RecurringTask(recurrenceType: 'Daily'),
      );
      await tester.pump();

      // The scheduled occurrence and the template survive; the user hears why.
      expect(await item(scheduled.dueDate!, scheduled.id!), isNotNull);
      expect((await env.col('recurring').doc(written.templateId).get()).exists, isTrue);
      expect(find.textContaining("Couldn't delete the recurring series"), findsOneWidget);
    });
  });

  group('searchTasks', () {
    test('returns nothing when Algolia is not configured', () async {
      expect(await service.searchTasks('milk'), isEmpty);
    });

    test('a failing Algolia call is reported as no results', () async {
      // The widget binding's stub HttpClient answers every request with 400,
      // so the configured client fails without touching the network.
      env.dispose();
      env = await TestEnv.create(env: {'ALGOLIA_APP_ID': 'nope', 'ALGOLIA_SEARCH_KEY': 'nope'});
      service = TaskService();
      expect(await service.searchTasks('milk'), isEmpty);
    });
  });

  group('streamMissedPoints', () {
    test('sums effort points of tasks left incomplete on a day', () async {
      await service.addTask(t('high', date: '2020-01-01', priority: Effort.high));
      await service.addTask(t('low', date: '2020-01-01', priority: Effort.low));
      await service.addTask(t('other day', date: '2020-01-02', priority: Effort.high));

      final missed = await service.streamMissedPoints(uid, ['2020-01-01', '2020-01-02']).first;
      expect(missed, {'2020-01-01': 4, '2020-01-02': 3});
    });

    test('completed tasks and dividers carry no missed points', () async {
      final done = await service.addTask(t('done', date: '2020-01-01', priority: Effort.high));
      await env.col('tasks').doc('2020-01-01').collection('items').doc(done).update({'completed': true});
      await service.addTask(
          Task(added: 1, title: 'sep', dueDate: '2020-01-01', priority: Effort.high, type: 'divider'));
      await service.addTask(t('real', date: '2020-01-01', priority: Effort.medium));

      final missed = await service.streamMissedPoints(uid, ['2020-01-01']).first;
      expect(missed, {'2020-01-01': 2});
    });

    test('a day with no tasks reports zero rather than dropping out', () async {
      final missed = await service.streamMissedPoints(uid, ['2020-01-01']).first;
      expect(missed, {'2020-01-01': 0});
    });

    test('no dates yields an empty map', () async {
      expect(await service.streamMissedPoints(uid, const []).first, isEmpty);
    });

    test('a row with no priority counts as low effort', () async {
      await env.col('tasks').doc('2020-01-01').collection('items').add({'title': 'legacy', 'completed': false});
      expect(await service.streamMissedPoints(uid, ['2020-01-01']).first, {'2020-01-01': 1});
    });
  });
}
