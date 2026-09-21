import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/journal_modal.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  const date = '2026-09-19';

  /// Pushes the modal as its own route, as the task list does, so Save can pop it.
  Future<void> open(WidgetTester tester) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JournalModal(date: date))),
          child: const Text('open'),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(400, 1400),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
  }

  testWidgets('loads the empty form; saving writes only the filled fields', (tester) async {
    await open(tester);
    await settle(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Journal — $date'), findsOneWidget);
    expect(find.text('What are you thinking?'), findsOneWidget);
    expect(find.text('How are you feeling?'), findsOneWidget);
    expect(find.text('What are you grateful for?'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '  planning the week  ');
    await tester.enterText(find.byType(TextField).at(2), 'coffee');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'saving state shown');
    expect(find.text('Save'), findsNothing);
    await settle(tester);

    final doc = await env.col('journal').doc(date).get();
    expect(doc.data(), {'date': date, 'thinking': 'planning the week', 'gratitude': 'coffee'});
    // Popped back to the host.
    expect(find.text('Journal — $date'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('loads an existing entry into the fields and saves edits', (tester) async {
    await JournalService().saveEntry(JournalEntry(date: date, thinking: 't0', feeling: 'f0', gratitude: 'g0'));
    await open(tester);
    await settle(tester);

    expect(find.text('t0'), findsOneWidget);
    expect(find.text('f0'), findsOneWidget);
    expect(find.text('g0'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'calm');
    await tester.enterText(find.byType(TextField).at(0), '');
    await tester.tap(find.text('Save'));
    await settle(tester);

    final entry = await JournalService().getEntry(date);
    expect(entry!.thinking, isNull);
    expect(entry.feeling, 'calm');
    expect(entry.gratitude, 'g0');
  });

  testWidgets('an entry with null fields loads as blanks; saving nothing stores just the date', (tester) async {
    await env.col('journal').doc(date).set({'date': date});
    await open(tester);
    await settle(tester);
    for (final f in find.byType(TextField).evaluate()) {
      expect((f.widget as TextField).controller!.text, '');
    }
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((await env.col('journal').doc(date).get()).data(), {'date': date});
  });
}
