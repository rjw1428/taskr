import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taskr/people/people_list.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/services/people.service.dart';

import 'helpers/harness.dart';

/// A service that ignores auth so the list can be mounted while signed out.
class _StaticService extends PeopleService {
  _StaticService(this.people);
  final List<Person> people;
  @override
  Stream<List<Person>> getPeople() => Stream.value(people);
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<Map<String, dynamic>?> prefs() async => (await env.col('settings').doc('preferences').get()).data();

  /// Inserted out of alphabetical order so a name sort is observable.
  Future<void> seed() async {
    final s = PeopleService();
    final cy = await s.addPerson(Person(name: 'Cy'));
    await s.addLog(cy, ConversationLog(id: 'l2', date: '2026-09-01', entry: 'Hi'));
    await s.addLog(cy, ConversationLog(id: 'l3', date: '2026-09-02', entry: 'Again'));
    await env.col('people').doc(cy).update({'lastUpdated': 200});
    final bob = await s.addPerson(Person(name: 'Bob'));
    await s.addLog(bob, ConversationLog(id: 'l1', date: '2026-09-01', entry: 'Hi'));
    await env.col('people').doc(bob).update({'lastUpdated': 300});
    final ada = await s.addPerson(Person(name: 'Ada', job: 'Engineer'));
    await env.col('people').doc(ada).update({'lastUpdated': 100});
    await s.addPerson(Person(name: 'Di'));
  }

  double top(WidgetTester tester, String text) => tester.getTopLeft(find.text(text)).dy;

  testWidgets('shows the empty state once the stream delivers', (tester) async {
    await pumpApp(tester, const PeopleListPage(), wrapInScaffold: true, size: const Size(600, 800));
    await settle(tester);
    expect(find.text('No people yet'), findsOneWidget);
    expect(find.text('Add a person to get started'), findsOneWidget);
  });

  testWidgets('lists people sorted by name with job or note-count subtitles', (tester) async {
    await seed();
    await pumpApp(tester, const PeopleListPage(), wrapInScaffold: true, size: const Size(600, 1000));
    await settle(tester, frames: 12);

    expect(find.text('Engineer'), findsOneWidget);
    expect(find.text('1 note'), findsOneWidget);
    expect(find.text('2 notes'), findsOneWidget);
    expect(find.text('Di'), findsOneWidget);
    expect(top(tester, 'Ada'), lessThan(top(tester, 'Bob')));
    expect(top(tester, 'Bob'), lessThan(top(tester, 'Cy')));
    expect(top(tester, 'Cy'), lessThan(top(tester, 'Di')));
  });

  testWidgets('search filters by name and shows a no-results state', (tester) async {
    await seed();
    await pumpApp(tester, const PeopleListPage(), wrapInScaffold: true, size: const Size(600, 1000));
    await settle(tester, frames: 12);

    await tester.enterText(find.byType(TextField), 'bo');
    await settle(tester, frames: 12);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Ada'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    expect(find.text('No results found'), findsOneWidget);
    expect(find.text('Add a person to get started'), findsNothing);
  });

  testWidgets('choosing Recent re-sorts and persists peopleSortBy', (tester) async {
    await seed();
    await pumpApp(tester, const PeopleListPage(), wrapInScaffold: true, size: const Size(600, 1000));
    await settle(tester, frames: 12);

    await tester.tap(find.text('Recent'));
    await settle(tester, frames: 12);
    expect((await prefs())!['peopleSortBy'], 'lastUpdated');
    // Di was added last with a live timestamp; the rest carry seeded values.
    expect(top(tester, 'Di'), lessThan(top(tester, 'Bob')));
    expect(top(tester, 'Bob'), lessThan(top(tester, 'Cy')));
    expect(top(tester, 'Cy'), lessThan(top(tester, 'Ada')));

    await tester.tap(find.text('Name'));
    await settle(tester, frames: 12);
    expect((await prefs())!['peopleSortBy'], 'name');
  });

  testWidgets('a stored sort preference is applied on open', (tester) async {
    await seed();
    await env.col('settings').doc('preferences').set({'peopleSortBy': 'lastUpdated'});
    await pumpApp(tester, const PeopleListPage(), wrapInScaffold: true, size: const Size(600, 1000));
    await settle(tester, frames: 12);
    expect(top(tester, 'Bob'), lessThan(top(tester, 'Ada')));
  });

  testWidgets('the FAB opens the add-person form', (tester) async {
    await pumpApp(tester, const PeopleListPage(), wrapInScaffold: true, size: const Size(600, 800));
    await settle(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('Add Person'), findsOneWidget);
  });

  testWidgets('tapping a person opens the detail page', (tester) async {
    await seed();
    await pumpApp(tester, const PeopleListPage(), wrapInScaffold: true, size: const Size(600, 1000));
    await settle(tester, frames: 12);
    await tester.tap(find.text('Ada'));
    await settle(tester, frames: 12);
    expect(find.text('Conversation Log'), findsOneWidget);
    expect(find.text('Engineer'), findsWidgets);
  });

  testWidgets('signed out: renders and sorting does not touch Firestore', (tester) async {
    env.dispose();
    env = await TestEnv.create(signedIn: false);
    final provider = PeopleProvider.withService(_StaticService([Person(id: 'p1', name: 'Ada')]));
    await pumpApp(
      tester,
      const PeopleListPage(),
      wrapInScaffold: true,
      size: const Size(600, 800),
      extraProviders: [ChangeNotifierProvider<PeopleProvider>.value(value: provider)],
    );
    await settle(tester);
    expect(find.text('Ada'), findsOneWidget);
    await tester.tap(find.text('Recent'));
    await settle(tester);
    expect((await env.db.collection('todos').get()).docs, isEmpty);
  });
}
