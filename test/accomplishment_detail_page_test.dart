import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/accomplishments/accomplishment_detail_page.dart';
import 'package:taskr/accomplishments/accomplishment_form.dart';
import 'package:taskr/services/models.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Accomplishment sample({String? id, String? description}) => Accomplishment(
        id: id,
        title: 'Shipped v2',
        description: description,
        date: '2026-08-14T10:00:00.000',
        difficultyScore: 7,
      );

  /// Mounts a launcher page so the detail page is pushed onto a navigator and
  /// can pop, the way it does from the list.
  Future<void> mountAndOpen(WidgetTester tester, Accomplishment a) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AccomplishmentDetailPage(accomplishment: a)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(400, 1000),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('renders an unsaved accomplishment directly, without a stream', (tester) async {
    await pumpApp(tester, AccomplishmentDetailPage(accomplishment: sample()));
    await settle(tester);

    expect(find.text('Shipped v2'), findsNWidgets(2)); // app bar + heading
    expect(find.text('Date: 2026-08-14T10:00:00.000'), findsOneWidget);
    expect(find.text('7 / 10'), findsOneWidget);
    expect(find.text('No description provided.'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a saved accomplishment is read live and reflects later edits', (tester) async {
    await env.col('accomplishments').doc('a').set(sample(description: 'Big release').toJson()..remove('id'));
    await mountAndOpen(tester, sample(id: 'a'));

    expect(find.text('Big release'), findsOneWidget);

    await env.col('accomplishments').doc('a').update({'title': 'Shipped v3', 'difficultyScore': 2});
    await settle(tester);

    expect(find.text('Shipped v3'), findsNWidgets(2));
    expect(find.text('2 / 10'), findsOneWidget);
  });

  testWidgets('the page pops itself when the document is deleted elsewhere', (tester) async {
    await env.col('accomplishments').doc('a').set(sample().toJson()..remove('id'));
    await mountAndOpen(tester, sample(id: 'a'));
    expect(find.byType(AccomplishmentDetailPage), findsOneWidget);

    await env.col('accomplishments').doc('a').delete();
    await settle(tester, frames: 12);

    expect(find.byType(AccomplishmentDetailPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('Edit opens the form pre-filled for this accomplishment', (tester) async {
    await env.col('accomplishments').doc('a').set(sample(description: 'Big release').toJson()..remove('id'));
    await mountAndOpen(tester, sample(id: 'a'));

    await tester.tap(find.text('Edit'));
    await settle(tester);

    expect(find.byType(AccomplishmentForm), findsOneWidget);
    expect(find.text('Edit Accomplishment'), findsOneWidget);
    expect(find.text('Big release'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('Delete asks for confirmation; Cancel keeps the entry', (tester) async {
    await env.col('accomplishments').doc('a').set(sample().toJson()..remove('id'));
    await mountAndOpen(tester, sample(id: 'a'));

    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete Accomplishment'), findsOneWidget);
    expect(find.text('Are you sure you want to delete this accomplishment?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(find.text('Delete Accomplishment'), findsNothing);
    expect(find.byType(AccomplishmentDetailPage), findsOneWidget);
    expect((await env.col('accomplishments').doc('a').get()).exists, isTrue);
  });

  testWidgets('confirming Delete removes the document and pops', (tester) async {
    await env.col('accomplishments').doc('a').set(sample().toJson()..remove('id'));
    await mountAndOpen(tester, sample(id: 'a'));

    await tester.tap(find.text('Delete'));
    await settle(tester);
    // The dialog's own "Delete" is the last one in the tree.
    await tester.tap(find.text('Delete').last);
    await settle(tester);

    expect((await env.col('accomplishments').doc('a').get()).exists, isFalse);
    expect(find.byType(AccomplishmentDetailPage), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('confirming Delete on an unsaved entry is a no-op', (tester) async {
    await mountAndOpen(tester, sample());

    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Delete').last);
    await settle(tester);

    // Nothing to delete, so the page stays (no id to pop on).
    expect(find.byType(AccomplishmentDetailPage), findsOneWidget);
  });
}
