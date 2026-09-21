import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

/// A Firestore whose collection-group queries fail the way the real one does
/// while a composite index is still building.
class _NoCollectionGroups extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collectionGroup(String collectionPath) => _FailingQuery();
}

// ignore: subtype_of_sealed_class
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
  late FakeFirebaseFirestore fake;
  late GoalService service;
  const uid = 'u1';
  const goalId = 'g1';
  // A Wednesday, so generation targets the week of Monday 2026-09-14.
  final wednesday = DateTime(2026, 9, 16, 10);

  Goal goal({String? id = goalId, GoalStatus status = GoalStatus.active}) => Goal(
        id: id,
        title: 'Run more',
        timeframe: GoalTimeframe.oneMonth,
        frequency: GoalFrequency.auto,
        startDate: '2026-09-01',
        endDate: '2026-10-01',
        status: status,
        createdAt: 1,
        modifiedAt: 1,
      );

  Future<void> seedTask(String date, String id, {required bool completed, String? goal = goalId}) {
    return fake.collection('todos').doc(uid).collection('tasks').doc(date).collection('items').doc(id).set({
      'title': id,
      'completed': completed,
      'userId': uid,
      if (goal != null) 'goalId': goal,
    });
  }

  Future<Map<String, dynamic>?> goalDoc(String id) async =>
      (await fake.collection('todos').doc(uid).collection('goals').doc(id).get()).data();

  Future<List<Map<String, dynamic>>> itemsOn(String date) async =>
      (await fake.collection('todos').doc(uid).collection('tasks').doc(date).collection('items').get())
          .docs
          .map((d) => {...d.data(), 'id': d.id})
          .toList();

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    PerformanceService().db = fake; // TaskService.addTask records pushed points
    service = GoalService()
      ..db = fake
      ..clock = () => wednesday;
  });

  group('goal CRUD', () {
    test('addGoal strips the id and nulls, and streamGoals reads it back newest first', () async {
      final oldId = await service.addGoal(goal(id: null).copyWith(createdAt: 1));
      final newId = await service.addGoal(goal(id: null).copyWith(createdAt: 2));

      final stored = await goalDoc(oldId);
      expect(stored!.containsKey('id'), isFalse);
      expect(stored.containsKey('description'), isFalse, reason: 'nulls are dropped');
      expect(stored['status'], 'active');

      final goals = await service.streamGoals().first;
      expect(goals.map((g) => g.id), [newId, oldId]);
    });

    test('addGoal drops a preset id rather than storing it as a field', () async {
      final id = await service.addGoal(goal(id: 'preset'));
      expect(id, isNot('preset'));
      expect((await goalDoc(id))!.containsKey('id'), isFalse);
    });

    test('getGoal returns null for a missing doc and the goal otherwise', () async {
      expect(await service.getGoal('nope'), isNull);
      final id = await service.addGoal(goal(id: null));
      expect((await service.getGoal(id))?.title, 'Run more');
    });

    test('updateGoal, pauseGoal and resumeGoal change the stored doc', () async {
      final id = await service.addGoal(goal(id: null));
      await service.updateGoal(goal(id: id).copyWith(title: 'Run daily'));
      expect((await goalDoc(id))!['title'], 'Run daily');
      expect((await goalDoc(id))!.containsKey('id'), isFalse, reason: 'the id is the doc key, not a field');

      await service.pauseGoal(goal(id: id));
      expect((await goalDoc(id))!['status'], 'paused');
      await service.resumeGoal(goal(id: id));
      expect((await goalDoc(id))!['status'], 'active');
    });

    test('mutations throw when nobody is signed in', () async {
      AuthService().user = null;
      expect(() => service.addGoal(goal()), throwsException);
      expect(() => service.updateGoal(goal()), throwsException);
      expect(await service.getGoal(goalId), isNull);
      expect(await service.streamGoals().first, isEmpty);
    });
  });

  group('generations', () {
    Generation gen(int at, {List<String> taskIds = const []}) => Generation(
        generatedAt: at, weekStart: 'ws', weekEnd: 'we', taskIds: taskIds, prompt: 'p', response: '[]');

    test('getLatestGeneration and getGenerations order by generatedAt desc', () async {
      await service.addGeneration(goalId, gen(1));
      await service.addGeneration(goalId, gen(3));
      await service.addGeneration(goalId, gen(2));

      expect((await service.getLatestGeneration(goalId))!.generatedAt, 3);
      expect((await service.getGenerations(goalId)).map((g) => g.generatedAt), [3, 2, 1]);
      expect(await service.getLatestGeneration('other'), isNull);

      final raw = await fake
          .collection('todos').doc(uid).collection('goals').doc(goalId).collection('generations').get();
      expect(raw.docs.every((d) => !d.data().containsKey('id')), isTrue, reason: 'no id field is stored');
    });

    test('updateGenerationCompletedTask appends without duplicating', () async {
      await service.addGeneration(goalId, gen(1, taskIds: ['t1', 't2']));
      final id = (await service.getLatestGeneration(goalId))!.id!;
      await service.updateGenerationCompletedTask(goalId, id, 't1');
      await service.updateGenerationCompletedTask(goalId, id, 't1');
      await service.updateGenerationCompletedTask(goalId, id, 't2');
      expect((await service.getLatestGeneration(goalId))!.completedTaskIds, ['t1', 't2']);
    });
  });

  group('submitTaskFeedback', () {
    test('writes feedback on the task and on the generation that produced it', () async {
      await seedTask('2026-09-15', 't1', completed: false);
      await service.addGeneration(
          goalId,
          Generation(
              generatedAt: 1, weekStart: 'a', weekEnd: 'b', taskIds: ['other'], prompt: '', response: ''));
      await service.addGeneration(
          goalId,
          Generation(
              generatedAt: 2, weekStart: 'a', weekEnd: 'b', taskIds: ['t1'], prompt: '', response: ''));

      final task = Task(id: 't1', added: 1, title: 't1', dueDate: '2026-09-15', goalId: goalId);
      await service.submitTaskFeedback(task, 'too easy');

      expect((await itemsOn('2026-09-15')).single['feedback'], 'too easy');
      final gens = await service.getGenerations(goalId);
      expect(gens.firstWhere((g) => g.generatedAt == 2).taskFeedback, {'t1': 'too easy'});
      expect(gens.firstWhere((g) => g.generatedAt == 1).taskFeedback, isEmpty);
    });

    test('is a no-op for a task with no goal', () async {
      await seedTask('2026-09-15', 't1', completed: false, goal: null);
      await service.submitTaskFeedback(
          Task(id: 't1', added: 1, title: 't1', dueDate: '2026-09-15'), 'x');
      expect((await itemsOn('2026-09-15')).single.containsKey('feedback'), isFalse);
    });
  });

  group('generateTasksForGoal', () {
    List<Map<String, dynamic>> plan() => [
          {'title': 'Mon run', 'description': 'easy', 'dayOffset': 0, 'effort': 'low'},
          {'title': 'Wed run', 'dayOffset': 2, 'effort': 'medium'},
          {'title': 'Sat run', 'dayOffset': 5, 'effort': 'high'},
          {'title': 'Way out', 'dayOffset': 40},
        ];

    test('creates tasks for the week, skips days already past, and records a generation', () async {
      final prompts = <String>[];
      service.llm = (p) async {
        prompts.add(p);
        return plan();
      };

      final created = await service.generateTasksForGoal(goal());

      // Monday is before Wednesday's "today", so it is dropped.
      expect(created.map((t) => t.title), ['Wed run', 'Sat run', 'Way out']);
      expect(created.map((t) => t.dueDate), ['2026-09-16', '2026-09-19', '2026-09-20']);
      expect(created.map((t) => t.priority), [Effort.medium, Effort.high, Effort.low]);
      expect(created.every((t) => t.goalId == goalId && t.id != null), isTrue);
      expect(created.first.description, isNull);

      expect((await itemsOn('2026-09-16')).single['title'], 'Wed run');

      final gen = (await service.getLatestGeneration(goalId))!;
      expect(gen.weekStart, '2026-09-14');
      expect(gen.weekEnd, '2026-09-20');
      expect(gen.taskIds, created.map((t) => t.id).toList());
      expect(gen.prompt, prompts.single);
      expect(gen.response, contains('Wed run'));
    });

    test('retries once with a stricter prompt, then rethrows', () async {
      var calls = 0;
      service.llm = (p) async {
        calls++;
        if (calls == 1) throw Exception('flaky');
        expect(p, contains('IMPORTANT: Return ONLY a valid JSON array'));
        return plan();
      };
      final created = await service.generateTasksForGoal(goal());
      expect(calls, 2);
      expect(created, isNotEmpty);

      service.llm = (_) async => throw Exception('down');
      await expectLater(service.generateTasksForGoal(goal()), throwsException);
      expect(await service.getGenerations(goalId), hasLength(1), reason: 'nothing recorded on failure');
    });

    test('regeneration deletes the latest week\'s uncompleted tasks but keeps completed ones', () async {
      service.llm = (_) async => plan();
      final first = await service.generateTasksForGoal(goal());
      final keep = first.firstWhere((t) => t.title == 'Wed run');
      await fake
          .collection('todos').doc(uid).collection('tasks').doc(keep.dueDate)
          .collection('items').doc(keep.id)
          .update({'completed': true});

      service.llm = (_) async => [
            {'title': 'Fresh', 'dayOffset': 4}
          ];
      await service.generateTasksForGoal(goal(), isRegeneration: true);

      expect((await itemsOn('2026-09-16')).map((t) => t['title']), ['Wed run']);
      expect((await itemsOn('2026-09-19')).map((t) => t['title']), isEmpty, reason: 'Sat run removed');
      expect((await itemsOn('2026-09-18')).map((t) => t['title']), ['Fresh']);
      expect(await service.getGenerations(goalId), hasLength(2));
    });

    test('throws when nobody is signed in', () async {
      AuthService().user = null;
      service.llm = (_) async => plan();
      expect(() => service.generateTasksForGoal(goal()), throwsException);
    });
  });

  group('deleteGoal', () {
    test('marks the goal deleted and removes its uncompleted tasks from every generation', () async {
      service.llm = (_) async => [
            {'title': 'A', 'dayOffset': 2},
            {'title': 'B', 'dayOffset': 3},
          ];
      final id = await service.addGoal(goal(id: null));
      final created = await service.generateTasksForGoal(goal(id: id));
      final done = created.first;
      await fake
          .collection('todos').doc(uid).collection('tasks').doc(done.dueDate)
          .collection('items').doc(done.id)
          .update({'completed': true});

      await service.deleteGoal(goal(id: id));

      expect((await goalDoc(id))!['status'], 'deleted');
      expect((await itemsOn('2026-09-16')).map((t) => t['title']), ['A']);
      expect(await itemsOn('2026-09-17'), isEmpty);
      final order = (await fake.collection('todos').doc(uid).collection('tasks').doc('2026-09-17').get()).data();
      expect(order?['taskOrder'] ?? [], isEmpty, reason: 'taskOrder entry removed too');
    });
  });

  group('getGoalStats', () {
    // Regression: goal progress used to be summed from a generation's
    // completedTaskIds, which undercounted after a push (new id) or non-checkbox
    // completion. It now counts the tasks actually tagged to the goal.
    test('counts tagged tasks across date partitions', () async {
      await seedTask('2026-08-01', 't1', completed: true);
      await seedTask('2026-08-02', 't2', completed: true);
      await seedTask('2026-08-03', 't3', completed: false);
      // Not part of this goal -> must be excluded.
      await seedTask('2026-08-03', 't4', completed: true, goal: null);
      await seedTask('2026-08-04', 't5', completed: true, goal: 'other-goal');

      final stats = await service.getGoalStats(goalId);
      expect(stats['totalTasks'], 3);
      expect(stats['completedTasks'], 2);
    });

    test('returns zeros for a goal with no tasks', () async {
      final stats = await service.getGoalStats('empty-goal');
      expect(stats['totalTasks'], 0);
      expect(stats['completedTasks'], 0);
      expect(stats['weeksActive'], 0);
    });

    test('while the index is building, the tally sums every generation', () async {
      fake = _NoCollectionGroups();
      service.db = fake;
      Generation gen(int at, List<String> ids, List<String> done) => Generation(
          generatedAt: at, weekStart: 'a', weekEnd: 'b', taskIds: ids, completedTaskIds: done, prompt: '', response: '');
      await service.addGeneration(goalId, gen(1, ['t1', 't2', 't3'], ['t1']));
      await service.addGeneration(goalId, gen(2, ['t4', 't5'], ['t4', 't5']));

      final stats = await service.getGoalStats(goalId);
      expect(stats['totalTasks'], 5);
      expect(stats['completedTasks'], 3);
      expect(stats['weeksActive'], 2);
    });

    test('weeksActive is the generation count', () async {
      await service.addGeneration(goalId,
          Generation(generatedAt: 1, weekStart: 'a', weekEnd: 'b', prompt: '', response: ''));
      expect((await service.getGoalStats(goalId))['weeksActive'], 1);
    });
  });

  group('signed-out branches', () {
    setUp(() => AuthService().user = null);

    test('every mutation throws and every read is empty', () async {
      expect(() => service.pauseGoal(goal()), throwsException);
      expect(() => service.resumeGoal(goal()), throwsException);
      expect(() => service.deleteGoal(goal()), throwsException);
      expect(
          () => service.addGeneration(
              goalId, Generation(generatedAt: 1, weekStart: 'a', weekEnd: 'b', prompt: '', response: '')),
          throwsException);
      expect(await service.getGenerations(goalId), isEmpty);
      expect(await service.getLatestGeneration(goalId), isNull);
    });

    test('updateGenerationCompletedTask and submitTaskFeedback are no-ops', () async {
      await service.updateGenerationCompletedTask(goalId, 'gen', 't1');
      await service.submitTaskFeedback(Task(id: 't1', added: 1, title: 't', goalId: goalId), 'x');
      expect((await fake.collection('todos').doc(uid).collection('goals').get()).size, 0);
    });

    test('getGoalStats falls back to the generation tally', () async {
      final stats = await service.getGoalStats(goalId);
      expect(stats, {'totalTasks': 0, 'completedTasks': 0, 'weeksActive': 0});
    });
  });

  group('the real model call', () {
    late HttpServer server;
    final requests = <Map<String, dynamic>>[];
    late int status;
    late String body;
    late String savedEndpoint;

    setUp(() async {
      requests.clear();
      status = 200;
      body = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '```json\n[{"title":"From Gemini","dayOffset":6,"effort":"high"}]\n```'}
              ]
            }
          }
        ]
      });
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(server.forEach((req) async {
        requests.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>);
        req.response.statusCode = status;
        req.response.write(body);
        await req.response.close();
      }));
      savedEndpoint = GoalService.geminiEndpoint;
      GoalService.geminiEndpoint = 'http://${server.address.host}:${server.port}/generate';
      dotenv.testLoad(fileInput: 'GEMINI_API_KEY=secret');
    });

    tearDown(() async {
      GoalService.geminiEndpoint = savedEndpoint;
      await server.close(force: true);
    });

    test('posts the system instruction and prompt, and parses the fenced JSON reply', () async {
      final created = await service.generateTasksForGoal(goal());

      expect(created.single.title, 'From Gemini');
      expect(created.single.priority, Effort.high);
      expect(created.single.dueDate, '2026-09-20');

      final req = requests.single;
      expect(req['system_instruction']['parts'][0]['text'], contains('personal development coach'));
      expect(req['contents'][0]['parts'][0]['text'], contains('Goal: Run more'));
      expect(req['generationConfig']['responseMimeType'], 'application/json');
    });

    test('a non-200 reply is an error on both attempts', () async {
      status = 500;
      body = 'boom';
      await expectLater(service.generateTasksForGoal(goal()), throwsA(predicate((e) => '$e'.contains('500'))));
      expect(requests, hasLength(2), reason: 'first attempt plus the stricter retry');
      expect(requests.last['contents'][0]['parts'][0]['text'], contains('IMPORTANT: Return ONLY'));
    });

    test('a missing API key fails before any request is made', () async {
      dotenv.testLoad(fileInput: '');
      await expectLater(service.generateTasksForGoal(goal()),
          throwsA(predicate((e) => '$e'.contains('GEMINI_API_KEY not set'))));
      expect(requests, isEmpty);
    });
  });
}
