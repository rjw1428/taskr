import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.service.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late PeopleService service;
  setUp(() async {
    env = await TestEnv.create();
    service = PeopleService();
  });
  tearDown(() => env.dispose());

  Future<Map<String, dynamic>> stored(String id) async => (await env.col('people').doc(id).get()).data()!;

  test('addPerson writes the person with timestamps and returns the id', () async {
    final id = await service.addPerson(Person(name: 'Ada', job: 'Engineer', kids: [
      Kid(name: 'Kim', age: 4, dateAdded: '2026-01-01'),
    ]));
    final data = await stored(id);
    expect(data['name'], 'Ada');
    expect(data['job'], 'Engineer');
    expect(data['createdAt'], isA<int>());
    expect(data['lastUpdated'], data['createdAt']);
    expect(data['logs'], isEmpty);
    expect((data['kids'] as List).single['name'], 'Kim');
  });

  test('updatePerson merges static fields and preserves logs and createdAt', () async {
    final id = await service.addPerson(Person(name: 'Ada'));
    await service.addLog(id, ConversationLog(date: '2026-09-01', entry: 'Hello'));
    final before = await stored(id);

    await service.updatePerson(id, Person(id: id, name: 'Ada L', spouse: 'Bob'));
    final after = await stored(id);
    expect(after['name'], 'Ada L');
    expect(after['spouse'], 'Bob');
    expect(after['createdAt'], before['createdAt']);
    expect((after['logs'] as List).single['entry'], 'Hello');
  });

  test('neither addPerson nor updatePerson persists the id field', () async {
    final id = await service.addPerson(Person(name: 'Ada'));
    expect((await stored(id)).containsKey('id'), isFalse);
    await service.updatePerson(id, Person(id: id, name: 'Ada L'));
    expect((await stored(id)).containsKey('id'), isFalse);
  });

  test('deletePerson removes the document', () async {
    final id = await service.addPerson(Person(name: 'Ada'));
    await service.deletePerson(id);
    expect((await env.col('people').doc(id).get()).exists, isFalse);
  });

  test('getPeople streams every person with its id', () async {
    final a = await service.addPerson(Person(name: 'Ada'));
    final b = await service.addPerson(Person(name: 'Bob'));
    final people = await service.getPeople().first;
    expect(people.map((p) => p.id).toSet(), {a, b});
    expect(people.map((p) => p.name).toSet(), {'Ada', 'Bob'});
  });

  test('getPerson streams the person, or null when it does not exist', () async {
    final id = await service.addPerson(Person(name: 'Ada'));
    final person = await service.getPerson(id).first;
    expect(person?.id, id);
    expect(person?.name, 'Ada');
    expect(await service.getPerson('missing').first, isNull);
  });

  group('logs', () {
    test('addLog generates an id when the log has none', () async {
      final id = await service.addPerson(Person(name: 'Ada'));
      await service.addLog(id, ConversationLog(date: '2026-09-01', entry: 'Hi'));
      final data = await stored(id);
      final log = (data['logs'] as List).single as Map;
      expect(log['id'], isNotEmpty);
      expect(log['createdAt'], isA<int>());
      expect(log['updatedAt'], log['createdAt']);
      expect(data['lastUpdated'], log['createdAt']);
    });

    test('addLog keeps a supplied id', () async {
      final id = await service.addPerson(Person(name: 'Ada'));
      await service.addLog(id, ConversationLog(id: 'log-1', date: '2026-09-01', entry: 'Hi'));
      final log = ((await stored(id))['logs'] as List).single as Map;
      expect(log['id'], 'log-1');
    });

    test('addLog throws when the person no longer exists', () async {
      expect(
        () => service.addLog('missing', ConversationLog(date: '2026-09-01', entry: 'Hi')),
        throwsA(isA<Exception>()),
      );
    });

    test('updateLog rewrites the matching log and keeps its id', () async {
      final id = await service.addPerson(Person(name: 'Ada'));
      await service.addLog(id, ConversationLog(id: 'log-1', date: '2026-09-01', entry: 'Hi'));
      await service.addLog(id, ConversationLog(id: 'log-2', date: '2026-09-02', entry: 'Bye'));

      await service.updateLog(id, 'log-1', ConversationLog(date: '2026-09-03', entry: 'Edited'));
      final logs = ((await stored(id))['logs'] as List).cast<Map>();
      final edited = logs.firstWhere((l) => l['id'] == 'log-1');
      expect(edited['entry'], 'Edited');
      expect(edited['date'], '2026-09-03');
      expect(logs.firstWhere((l) => l['id'] == 'log-2')['entry'], 'Bye');
    });

    test('updateLog with an unknown id leaves the person untouched', () async {
      final id = await service.addPerson(Person(name: 'Ada'));
      await service.addLog(id, ConversationLog(id: 'log-1', date: '2026-09-01', entry: 'Hi'));
      final before = await stored(id);
      await service.updateLog(id, 'nope', ConversationLog(date: '2026-09-03', entry: 'Edited'));
      expect(await stored(id), before);
    });

    test('deleteLog removes only the matching log', () async {
      final id = await service.addPerson(Person(name: 'Ada'));
      await service.addLog(id, ConversationLog(id: 'log-1', date: '2026-09-01', entry: 'Hi'));
      await service.addLog(id, ConversationLog(id: 'log-2', date: '2026-09-02', entry: 'Bye'));
      await service.deleteLog(id, 'log-1');
      final logs = ((await stored(id))['logs'] as List).cast<Map>();
      expect(logs.map((l) => l['id']), ['log-2']);
    });
  });

  test('every method fails when nobody is signed in', () async {
    env.dispose();
    env = await TestEnv.create(signedIn: false);
    final s = PeopleService();
    expect(() => s.addPerson(Person(name: 'x')), throwsA(isA<TypeError>()));
    expect(() => s.getPeople(), throwsA(isA<TypeError>()));
  });

  test('db and auth setters override the resolved handles', () async {
    final other = FakeFirebaseFirestore();
    final s = PeopleService()
      ..db = other
      ..auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'other'));
    final id = await s.addPerson(Person(name: 'Zed'));
    expect((await other.collection('todos').doc('other').collection('people').doc(id).get()).exists, isTrue);
    expect((await env.col('people').get()).docs, isEmpty);
  });
}
