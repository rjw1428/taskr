import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:taskr/people/person_detail.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/services/people.service.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

class _FailingService extends PeopleService {
  @override
  Future<void> deletePerson(String personId) async => throw Exception('no delete');
  @override
  Future<void> deleteLog(String personId, String logId) async => throw Exception('no log delete');
}

/// Pushes the detail page from a home route so `Navigator.pop` has somewhere
/// to land, as it does in production.
class _Host extends StatelessWidget {
  const _Host(this.personId);
  final String personId;
  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PersonDetailPage(personId: personId)),
          ),
          child: const Text('open'),
        ),
      );
}

int mirrorBirthdayAge(String birthday) {
  final b = DateTime.parse(birthday);
  final now = DateTime.now();
  var age = now.year - b.year;
  if (now.month < b.month || (now.month == b.month && now.day < b.day)) age--;
  return age;
}

int mirrorAddedAge(int age, String dateAdded) {
  final d = DateTime.parse(dateAdded);
  final now = DateTime.now();
  if (now.month > d.month || (now.month == d.month && now.day >= d.day)) return age + (now.year - d.year);
  return age + (now.year - d.year - 1);
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> open(WidgetTester tester, String id, {List<SingleChildWidget> extra = const []}) async {
    await pumpApp(tester, _Host(id), wrapInScaffold: true, size: const Size(400, 1200), extraProviders: extra);
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester, frames: 12);
  }

  /// The options button inside the card that shows [entry].
  Finder menuFor(String entry) => find.descendant(
        of: find.ancestor(of: find.text(entry), matching: find.byType(Card)),
        matching: find.byTooltip('Log options'),
      );

  Future<String> seedFull() async {
    final s = PeopleService();
    final id = await s.addPerson(Person(
      name: 'Ada Lovelace',
      age: 36,
      birthday: '1990-05-20',
      spouse: 'William',
      job: 'Mathematician',
      kids: [
        Kid(name: 'Jan', age: 0, birthday: '2020-01-01', dateAdded: '2020-01-01'),
        Kid(name: 'Dec', age: 0, birthday: '2020-12-31', dateAdded: '2020-12-31'),
        Kid(name: 'Early', age: 3, dateAdded: '2024-01-01'),
        Kid(name: 'Late', age: 3, dateAdded: '2024-12-31'),
      ],
    ));
    await s.addLog(id, ConversationLog(id: 'l1', date: '2026-09-01', entry: 'First chat'));
    await s.addLog(id, ConversationLog(id: 'l2', date: '2026-09-03', entry: 'Second chat'));
    await s.addLog(id, ConversationLog(id: 'l3', date: '2026-09-05', entry: 'Third chat'));
    await s.addLog(id, ConversationLog(id: 'l4', date: '2026-09-05', entry: 'Fourth chat'));
    // l3 and l4 share a date; pin createdAt so the tie-break is deterministic.
    final logs = ((await env.col('people').doc(id).get()).data()!['logs'] as List).cast<Map<String, dynamic>>();
    for (final l in logs) {
      if (l['id'] == 'l3') l['createdAt'] = 1000;
      if (l['id'] == 'l4') l['createdAt'] = 2000;
    }
    await env.col('people').doc(id).update({'logs': logs});
    return id;
  }

  testWidgets('shows a not-found screen for an unknown id', (tester) async {
    await open(tester, 'nope');
    expect(find.text('Person not found'), findsOneWidget);
  });

  testWidgets('renders facts, kids with computed ages, and logs newest first', (tester) async {
    final id = await seedFull();
    await open(tester, id);

    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(find.text('Mathematician'), findsWidgets);
    expect(find.text('AGE'), findsOneWidget);
    expect(find.text('36'), findsOneWidget);
    expect(find.text('BIRTHDAY'), findsOneWidget);
    expect(find.text('May 20'), findsOneWidget);
    expect(find.text('William'), findsOneWidget);
    expect(find.text('KIDS'), findsOneWidget);
    expect(find.text('Jan · ${mirrorBirthdayAge('2020-01-01')}'), findsOneWidget);
    expect(find.text('Dec · ${mirrorBirthdayAge('2020-12-31')}'), findsOneWidget);
    expect(find.text('Early · ${mirrorAddedAge(3, '2024-01-01')}'), findsOneWidget);
    expect(find.text('Late · ${mirrorAddedAge(3, '2024-12-31')}'), findsOneWidget);

    expect(find.text('Sep 5, 2026'), findsNWidgets(2));
    expect(find.text('Sep 3, 2026'), findsOneWidget);
    expect(find.text('Sep 1, 2026'), findsOneWidget);
    final fourth = tester.getTopLeft(find.text('Fourth chat')).dy;
    final third = tester.getTopLeft(find.text('Third chat')).dy;
    final second = tester.getTopLeft(find.text('Second chat')).dy;
    final first = tester.getTopLeft(find.text('First chat')).dy;
    expect(fourth, lessThan(third));
    expect(third, lessThan(second));
    expect(second, lessThan(first));
  });

  testWidgets('a bare person shows no facts and "No logs yet"', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    await open(tester, id);
    expect(find.text('No logs yet'), findsOneWidget);
    expect(find.text('AGE'), findsNothing);
    expect(find.text('KIDS'), findsNothing);
  });

  testWidgets('kid ages honor the month and day boundaries around today', (tester) async {
    // Kids placed around today's month/day so every branch of the age math
    // is exercised: same month earlier/later/same day, and adjacent months.
    final now = DateTime.now();
    String ymd(int y, int m, int d) => DateService().getString(DateTime(y, m, d));
    final prevMonth = DateTime(now.year, now.month - 1, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final kids = <String, Kid>{
      'B1': Kid(name: 'B1', age: 0, birthday: ymd(now.year - 5, now.month, 1), dateAdded: '2020-01-01'),
      'B28': Kid(name: 'B28', age: 0, birthday: ymd(now.year - 5, now.month, 28), dateAdded: '2020-01-01'),
      'BToday': Kid(name: 'BToday', age: 0, birthday: ymd(now.year - 5, now.month, now.day), dateAdded: '2020-01-01'),
      'BPrev': Kid(name: 'BPrev', age: 0, birthday: ymd(prevMonth.year - 5, prevMonth.month, 28), dateAdded: '2020-01-01'),
      'BNext': Kid(name: 'BNext', age: 0, birthday: ymd(nextMonth.year - 5, nextMonth.month, 1), dateAdded: '2020-01-01'),
      'A1': Kid(name: 'A1', age: 3, dateAdded: ymd(now.year - 2, now.month, 1)),
      'A28': Kid(name: 'A28', age: 3, dateAdded: ymd(now.year - 2, now.month, 28)),
      'AToday': Kid(name: 'AToday', age: 3, dateAdded: ymd(now.year - 2, now.month, now.day)),
      'APrev': Kid(name: 'APrev', age: 3, dateAdded: ymd(prevMonth.year - 2, prevMonth.month, 28)),
      'ANext': Kid(name: 'ANext', age: 3, dateAdded: ymd(nextMonth.year - 2, nextMonth.month, 1)),
    };
    final id = await PeopleService().addPerson(Person(name: 'Parent', kids: kids.values.toList()));
    await open(tester, id);

    for (final kid in kids.values) {
      final expected = kid.birthday != null ? mirrorBirthdayAge(kid.birthday!) : mirrorAddedAge(kid.age, kid.dateAdded);
      expect(find.text('${kid.name} · $expected'), findsOneWidget, reason: kid.name);
    }
    // Spot checks that do not depend on the mirror: a birthday on the 1st of
    // this month has passed, one in next month has not.
    expect(find.text('B1 · 5'), findsOneWidget);
    expect(find.text('BNext · 4'), findsOneWidget);
    expect(find.text('BToday · 5'), findsOneWidget);
    expect(find.text('A1 · 5'), findsOneWidget);
    expect(find.text('ANext · 4'), findsOneWidget);
    expect(find.text('AToday · 5'), findsOneWidget);
  });

  testWidgets('the header divider appears only when there are facts or kids', (tester) async {
    final s = PeopleService();
    final bare = await s.addPerson(Person(name: 'Bare'));
    await open(tester, bare);
    expect(find.byType(Divider), findsNothing);
    await tester.pageBack();
    await settle(tester);

    final kidsOnly = await s.addPerson(Person(name: 'Kids', kids: [Kid(name: 'Jo', age: 1, dateAdded: '2026-01-01')]));
    await open(tester, kidsOnly);
    expect(find.text('KIDS'), findsOneWidget);
    expect(find.byType(Divider), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    final factsOnly = await s.addPerson(Person(name: 'Facts', age: 40));
    await open(tester, factsOnly);
    expect(find.text('AGE'), findsOneWidget);
    expect(find.text('KIDS'), findsNothing);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('the FAB opens the add-log form and the saved log appears', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    await open(tester, id);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('Add Log Entry'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Talked shop');
    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);
    expect(find.text('Add Log Entry'), findsNothing);
    expect(find.text('Talked shop'), findsOneWidget);
  });

  testWidgets('the person menu opens the edit form', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    await open(tester, id);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Edit'));
    await settle(tester);
    expect(find.text('Edit Person'), findsOneWidget);
  });

  testWidgets('deleting the person can be cancelled or confirmed', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    await open(tester, id);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete Bob and all their logs?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Delete Person'), findsNothing);
    expect((await env.col('people').doc(id).get()).exists, isTrue);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester, frames: 12);
    expect(find.text('open'), findsOneWidget);
    expect((await env.col('people').doc(id).get()).exists, isFalse);
  });

  testWidgets('a failed person delete reports an error snackbar', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    final provider = PeopleProvider.withService(_FailingService());
    await open(tester, id, extra: [ChangeNotifierProvider<PeopleProvider>.value(value: provider)]);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester, frames: 12);
    expect(find.textContaining('Error deleting person'), findsOneWidget);
  });

  group('log menu', () {
    testWidgets('Edit opens the log form prefilled', (tester) async {
      final id = await seedFull();
      await open(tester, id);
      await tester.tap(menuFor('Third chat'));
      await settle(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester);
      expect(find.text('Edit Log Entry'), findsOneWidget);
      expect(find.text('Third chat'), findsOneWidget);
    });

    testWidgets('Delete can be cancelled or confirmed', (tester) async {
      final id = await seedFull();
      await open(tester, id);
      await tester.tap(menuFor('Third chat'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Delete this conversation log?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(find.text('Third chat'), findsOneWidget);

      await tester.tap(menuFor('Third chat'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester, frames: 12);
      expect(find.text('Delete this conversation log?'), findsNothing, reason: 'dialog closed');
      expect(find.text('Third chat'), findsNothing);
      expect(find.text('Second chat'), findsOneWidget);
      final logs = ((await env.col('people').doc(id).get()).data()!['logs'] as List).cast<Map>();
      expect(logs.map((l) => l['id']), isNot(contains('l3')));
    });

    testWidgets('a legacy log without an id cannot be removed individually', (tester) async {
      final id = await PeopleService().addPerson(Person(name: 'Bob'));
      await env.col('people').doc(id).update({
        'logs': [
          {'date': '2026-09-01', 'entry': 'Old note'},
        ],
      });
      await open(tester, id);
      await tester.tap(find.byTooltip('Log options'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester);
      expect(find.text('Delete this conversation log?'), findsNothing, reason: 'dialog closed');
      expect(find.textContaining('older log has no id'), findsOneWidget);
      expect(find.text('Old note'), findsOneWidget);
    });

    testWidgets('a failed log delete reports an error snackbar', (tester) async {
      final id = await seedFull();
      final provider = PeopleProvider.withService(_FailingService());
      await open(tester, id, extra: [ChangeNotifierProvider<PeopleProvider>.value(value: provider)]);
      await tester.tap(menuFor('Third chat'));
      await settle(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.text('Delete').last);
      await settle(tester, frames: 12);
      expect(find.textContaining('Error deleting log'), findsOneWidget);
    });
  });
}
