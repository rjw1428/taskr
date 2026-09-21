import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:taskr/people/log_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/people.provider.dart';
import 'package:taskr/services/people.service.dart';

import 'helpers/harness.dart';

class _FailingService extends PeopleService {
  @override
  Future<void> addLog(String personId, ConversationLog log) async => throw Exception('no add');
}

class _Host extends StatelessWidget {
  const _Host(this.personId, {this.log});
  final String personId;
  final ConversationLog? log;
  @override
  Widget build(BuildContext context) => Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => LogFormPage(personId: personId, log: log)),
          ),
          child: const Text('open'),
        ),
      );
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> open(WidgetTester tester, Widget host, {List<SingleChildWidget> extra = const []}) async {
    await pumpApp(tester, host, wrapInScaffold: true, size: const Size(400, 1400), extraProviders: extra);
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<List<Map>> logsOf(String id) async =>
      ((await env.col('people').doc(id).get()).data()!['logs'] as List).cast<Map>();

  testWidgets('refuses to save an empty entry', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    await open(tester, _Host(id));
    expect(find.text('Add Log Entry'), findsOneWidget);
    expect(find.text(DateFormat('MMM d, yyyy').format(DateTime.now())), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Entry cannot be empty'), findsOneWidget);
    expect(await logsOf(id), isEmpty);
  });

  testWidgets('saves a new log dated today and pops', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    await open(tester, _Host(id));
    await tester.enterText(find.byType(TextField).last, 'Caught up');
    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);
    expect(find.text('open'), findsOneWidget);
    final log = (await logsOf(id)).single;
    expect(log['entry'], 'Caught up');
    expect(log['date'], DateTime.now().toIso8601String().split('T')[0]);
    expect(log['id'], isNotEmpty);
  });

  testWidgets('edits an existing log, including a picked date', (tester) async {
    final s = PeopleService();
    final id = await s.addPerson(Person(name: 'Bob'));
    await s.addLog(id, ConversationLog(id: 'l1', date: '2026-03-15', entry: 'Old'));
    final log = ConversationLog(id: 'l1', date: '2026-03-15', entry: 'Old');
    await open(tester, _Host(id, log: log));
    expect(find.text('Edit Log Entry'), findsOneWidget);
    expect(find.text('Mar 15, 2026'), findsOneWidget);
    expect(find.text('Old'), findsOneWidget);

    // Cancel leaves the date alone.
    await tester.tap(find.text('Mar 15, 2026'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Mar 15, 2026'), findsOneWidget);

    await tester.tap(find.text('Mar 15, 2026'));
    await settle(tester);
    await tester.tap(find.text('1'));
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('Mar 1, 2026'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'New text');
    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);
    expect(find.text('open'), findsOneWidget);
    final stored = (await logsOf(id)).single;
    expect(stored['id'], 'l1');
    expect(stored['entry'], 'New text');
    expect(stored['date'], '2026-03-01');
  });

  testWidgets('a failed save shows an error and stays open', (tester) async {
    final id = await PeopleService().addPerson(Person(name: 'Bob'));
    final provider = PeopleProvider.withService(_FailingService());
    await open(tester, _Host(id), extra: [ChangeNotifierProvider<PeopleProvider>.value(value: provider)]);
    await tester.enterText(find.byType(TextField).last, 'Caught up');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.textContaining('Error: Exception: no add'), findsOneWidget);
    expect(find.text('Add Log Entry'), findsOneWidget);
  });
}
