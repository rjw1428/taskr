import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:taskr/people/person_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/services/people.service.dart';

import 'helpers/harness.dart';

class _FailingService extends PeopleService {
  @override
  Future<String> addPerson(Person person) async => throw Exception('no add');
}

class _Host extends StatelessWidget {
  const _Host({this.person});
  final Person? person;
  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PersonFormPage(person: person)),
          ),
          child: const Text('open'),
        ),
      );
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> open(WidgetTester tester, {Person? person, List<SingleChildWidget> extra = const []}) async {
    await pumpApp(tester, _Host(person: person), wrapInScaffold: true, size: const Size(400, 1400), extraProviders: extra);
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  // The kid rows' inner TextFields reuse the 'Age' label, so take the first
  // match, which is always the person's own field.
  Finder field(String label) =>
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label).first;

  test('KidForm round-trips a Kid and defaults age and dateAdded', () {
    final k = KidForm.fromKid(Kid(name: 'Kim', age: 4, birthday: '2022-02-02', dateAdded: '2026-01-01')).toKid();
    expect(k.name, 'Kim');
    expect(k.age, 4);
    expect(k.birthday, '2022-02-02');
    expect(k.dateAdded, '2026-01-01');

    final blank = (KidForm()..name = 'New').toKid();
    expect(blank.age, 0);
    expect(blank.dateAdded, DateTime.now().toIso8601String().split('T')[0]);
  });

  testWidgets('requires a name', (tester) async {
    await open(tester);
    expect(find.text('Add Person'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Name is required'), findsOneWidget);
    expect((await env.col('people').get()).docs, isEmpty);
  });

  testWidgets('creates a person with fields, a picked birthday and kids', (tester) async {
    await open(tester);
    await tester.enterText(field('Name *'), '  Ada  ');
    await tester.enterText(field('Age'), '36');
    await tester.enterText(field('Job'), 'Engineer');
    await tester.enterText(field('Spouse'), '   ');

    // Birthday picker: cancel first, then pick the 1st of the current month.
    await tester.tap(field('Birthday'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(tester.widget<TextField>(field('Birthday')).controller!.text, '');
    await tester.tap(field('Birthday'));
    await settle(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('OK'));
    await settle(tester);
    final now = DateTime.now();
    final firstOfMonth = DateTime(now.year, now.month, 1).toIso8601String().split('T')[0];

    // Three kids: one filled in, one removed, one left blank (dropped on save).
    await tester.tap(find.byTooltip('Add kid'));
    await tester.tap(find.byTooltip('Add kid'));
    await tester.tap(find.byTooltip('Add kid'));
    await settle(tester);
    expect(find.byType(TextFormField), findsNWidgets(9));
    await tester.enterText(find.byType(TextFormField).at(0), 'Kim');
    await tester.enterText(find.byType(TextFormField).at(1), '4');
    await tester.enterText(find.byType(TextFormField).at(3), 'Gone');
    await tester.tap(find.byTooltip('Remove kid').at(1));
    await settle(tester);
    expect(find.byType(TextFormField), findsNWidgets(6));

    // Kid birthday picker on the first kid: cancel, then pick.
    await tester.tap(find.byType(TextFormField).at(2));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    await tester.tap(find.byType(TextFormField).at(2));
    await settle(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('OK'));
    await settle(tester);

    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);
    expect(find.text('open'), findsOneWidget);

    final doc = (await env.col('people').get()).docs.single.data();
    expect(doc['name'], 'Ada');
    expect(doc['age'], 36);
    expect(doc['job'], 'Engineer');
    expect(doc['spouse'], isNull);
    expect(doc['birthday'], firstOfMonth);
    final kids = (doc['kids'] as List).cast<Map>();
    expect(kids.length, 1);
    expect(kids.single['name'], 'Kim');
    expect(kids.single['age'], 4);
    expect(kids.single['birthday'], firstOfMonth);
  });

  testWidgets('edits an existing person, keeping logs and createdAt', (tester) async {
    final s = PeopleService();
    final id = await s.addPerson(Person(
      name: 'Ada',
      age: 36,
      birthday: '1990-05-20',
      job: 'Engineer',
      spouse: 'Bill',
      kids: [Kid(name: 'Kim', age: 4, birthday: '2022-02-02', dateAdded: '2026-01-01')],
    ));
    await s.addLog(id, ConversationLog(id: 'l1', date: '2026-09-01', entry: 'Hi'));
    final person = Person(
      id: id,
      name: 'Ada',
      age: 36,
      birthday: '1990-05-20',
      job: 'Engineer',
      spouse: 'Bill',
      kids: [Kid(name: 'Kim', age: 4, birthday: '2022-02-02', dateAdded: '2026-01-01')],
    );
    final before = (await env.col('people').doc(id).get()).data()!;

    await open(tester, person: person);
    expect(find.text('Edit Person'), findsOneWidget);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.text('May 20, 1990'), findsOneWidget);
    expect(find.text('Kim'), findsOneWidget);
    expect(find.text('Feb 2'), findsOneWidget);

    await tester.tap(find.text('May 20, 1990'));
    await settle(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('May 1, 1990'), findsOneWidget);

    await tester.enterText(field('Name *'), 'Ada L');
    await tester.enterText(field('Age'), 'abc');
    await tester.enterText(field('Job'), '');
    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);
    expect(find.text('open'), findsOneWidget);

    final after = (await env.col('people').doc(id).get()).data()!;
    expect(after['name'], 'Ada L');
    expect(after['age'], isNull);
    expect(after['job'], isNull);
    expect(after['spouse'], 'Bill');
    expect(after['birthday'], '1990-05-01');
    expect(after['createdAt'], before['createdAt']);
    expect((after['logs'] as List).single['entry'], 'Hi');
    expect((after['kids'] as List).single['dateAdded'], '2026-01-01');
  });

  testWidgets('a failed save shows an error and stays open', (tester) async {
    final provider = PeopleProvider.withService(_FailingService());
    await open(tester, extra: [ChangeNotifierProvider<PeopleProvider>.value(value: provider)]);
    await tester.enterText(field('Name *'), 'Ada');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.textContaining('Error: Exception: no add'), findsOneWidget);
    expect(find.text('Add Person'), findsOneWidget);
  });
}
