import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/services/people.service.dart';

import 'helpers/harness.dart';

class _ErrorService extends PeopleService {
  @override
  Stream<List<Person>> getPeople() => Stream.error(Exception('stream broke'));
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test('starts loading, then exposes the people from the stream', () async {
    await PeopleService().addPerson(Person(name: 'Ada'));
    final provider = PeopleProvider();
    var notifications = 0;
    provider.addListener(() => notifications++);
    expect(provider.isLoading, isTrue);
    expect(provider.people, isEmpty);

    await tick();
    expect(provider.isLoading, isFalse);
    expect(provider.error, isNull);
    expect(provider.people.single.name, 'Ada');
    expect(notifications, greaterThan(0));
    provider.dispose();
  });

  test('records the error when the stream fails', () async {
    final provider = PeopleProvider.withService(_ErrorService());
    await tick();
    expect(provider.isLoading, isFalse);
    expect(provider.error, contains('stream broke'));
    provider.dispose();
  });

  test('mutations write through the service and flow back via the stream', () async {
    final provider = PeopleProvider();
    await tick();

    await provider.addPerson(Person(name: 'Ada'));
    await tick();
    final ada = provider.people.single;
    expect(ada.name, 'Ada');

    await provider.updatePerson(Person(id: ada.id, name: 'Ada L'));
    await tick();
    expect(provider.people.single.name, 'Ada L');

    await provider.addLog(ada.id!, ConversationLog(id: 'l1', date: '2026-09-01', entry: 'Hi'));
    await tick();
    expect(provider.people.single.logs.single.entry, 'Hi');

    await provider.updateLog(ada.id!, 'l1', ConversationLog(date: '2026-09-02', entry: 'Edited'));
    await tick();
    expect(provider.people.single.logs.single.entry, 'Edited');

    await provider.deleteLog(ada.id!, 'l1');
    await tick();
    expect(provider.people.single.logs, isEmpty);

    await provider.deletePerson(ada.id!);
    await tick();
    expect(provider.people, isEmpty);
    provider.dispose();
  });

  test('dispose cancels the subscription so later writes do not notify', () async {
    final provider = PeopleProvider();
    await tick();
    provider.dispose();
    await PeopleService().addPerson(Person(name: 'Ada'));
    await tick();
    expect(provider.people, isEmpty);
  });
}
