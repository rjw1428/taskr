import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/accomplishments/accomplishment_form.dart';
import 'package:taskr/services/models.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<List<Map<String, dynamic>>> stored() async =>
      (await env.col('accomplishments').get()).docs.map((d) => {...d.data(), 'id': d.id}).toList();

  Future<void> mountAndOpen(WidgetTester tester, {Accomplishment? accomplishment}) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AccomplishmentForm(accomplishment: accomplishment)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(400, 1400),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);

  testWidgets('an empty title fails validation and nothing is written', (tester) async {
    await mountAndOpen(tester);
    expect(find.text('Add Accomplishment'), findsOneWidget);
    expect(find.text('1 / 10'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(find.text('Please enter a title'), findsOneWidget);
    expect(find.byType(AccomplishmentForm), findsOneWidget);
    expect(await stored(), isEmpty);
  });

  testWidgets('creates an accomplishment with the chosen difficulty and pops', (tester) async {
    await mountAndOpen(tester);

    await tester.enterText(field('Title'), 'Ran a marathon');
    await tester.enterText(field('Description'), 'Four hours flat');

    // Drag the slider most of the way right: score rises above the default 1.
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(300, 0));
    await settle(tester);
    expect(find.text('1 / 10'), findsNothing);
    final scoreText = tester.widget<Text>(find.textContaining(' / 10')).data!;
    final score = int.parse(scoreText.split(' ').first);
    expect(score, greaterThan(1));

    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(find.byType(AccomplishmentForm), findsNothing);
    final rows = await stored();
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Ran a marathon');
    expect(rows.single['description'], 'Four hours flat');
    expect(rows.single['difficultyScore'], score);
    expect(DateTime.tryParse(rows.single['date'] as String), isNotNull);
  });

  testWidgets('editing pre-fills the fields and updates the existing document', (tester) async {
    await env.col('accomplishments').doc('a').set({
      'title': 'Old title',
      'description': 'Old description',
      'date': '2026-08-14T10:00:00.000',
      'difficultyScore': 4,
    });
    await mountAndOpen(
      tester,
      accomplishment: Accomplishment(
        id: 'a',
        title: 'Old title',
        description: 'Old description',
        date: '2026-08-14T10:00:00.000',
        difficultyScore: 4,
      ),
    );

    expect(find.text('Edit Accomplishment'), findsOneWidget);
    expect(find.text('Old title'), findsOneWidget);
    expect(find.text('Old description'), findsOneWidget);
    expect(find.text('4 / 10'), findsOneWidget);

    await tester.enterText(field('Title'), 'New title');
    await tester.tap(find.text('Update'));
    await settle(tester);

    expect(find.byType(AccomplishmentForm), findsNothing);
    final row = (await env.col('accomplishments').doc('a').get()).data()!;
    expect(row['title'], 'New title');
    expect(row['description'], 'Old description');
    expect(row['difficultyScore'], 4);
    expect(row['date'], '2026-08-14T10:00:00.000'); // date is kept on edit
  });

  testWidgets('editing an entry with no description shows an empty field', (tester) async {
    await mountAndOpen(
      tester,
      accomplishment: Accomplishment(id: 'a', title: 'T', date: '2026-08-14T10:00:00.000', difficultyScore: 10),
    );
    expect(find.text('10 / 10'), findsOneWidget);
    expect(tester.widget<TextFormField>(field('Description')).initialValue, '');
  });
}
