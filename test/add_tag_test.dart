import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/task_list/add_tag.dart';

import 'helpers/harness.dart';

/// Holds `addTag` until [gate] completes so the in-flight state is visible.
class _GatedTagProvider extends TagProvider {
  final gate = Completer<void>();
  @override
  Future<void> addTag(String label) async {
    await gate.future;
    return super.addTag(label);
  }
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  late TagProvider provider;

  /// Opens the dialog through showDialog, as settings does.
  Future<void> open(WidgetTester tester, {Tag? tag, TagProvider? tagProvider}) async {
    await pumpApp(
      extraProviders: [
        if (tagProvider != null) ChangeNotifierProvider<TagProvider>.value(value: tagProvider),
      ],
      tester,
      Builder(
        builder: (context) {
          provider = context.read<TagProvider>();
          return TextButton(
            onPressed: () => showDialog(context: context, builder: (_) => AddTagScreen(tag: tag)),
            child: const Text('open'),
          );
        },
      ),
      wrapInScaffold: true,
    );
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('adds a tag and closes', (tester) async {
    await open(tester);
    expect(find.text('Add tag'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '  Work ');
    await tester.tap(find.text('Add'));
    await settle(tester);

    final tags = await env.col('tags').get();
    expect(tags.docs.single.data(), {'label': 'Work', 'deleted': false, 'archived': false});
    expect(find.text('Add tag'), findsNothing);
    // The provider's stream picks the new tag up.
    expect(provider.tags.map((t) => t.label), ['Work']);
  });

  testWidgets('an empty name fails validation and nothing is written', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Enter a tag name'), findsOneWidget);
    expect(find.text('Add tag'), findsOneWidget);
    expect((await env.col('tags').get()).docs, isEmpty);
  });

  testWidgets('submitting from the keyboard also saves', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField), 'Home');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect((await env.col('tags').get()).docs.single.data()['label'], 'Home');
  });

  testWidgets('renames an existing tag', (tester) async {
    final ref = await env.col('tags').add({'label': 'Old', 'deleted': false, 'archived': false});
    await open(tester, tag: Tag(id: ref.id, label: 'Old'));
    expect(find.text('Edit tag'), findsOneWidget);
    expect(find.text('Old'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'New');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect((await ref.get()).data()!['label'], 'New');
    expect(find.text('Edit tag'), findsNothing);
  });

  testWidgets('cancel closes without writing', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextFormField), 'Dropped');
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Add tag'), findsNothing);
    expect((await env.col('tags').get()).docs, isEmpty);
  });

  testWidgets('a failed save shows a snackbar and re-enables the buttons', (tester) async {
    await open(tester);
    AuthService().user = null; // TagProvider.addTag throws with no user
    await tester.enterText(find.byType(TextFormField), 'Nope');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.textContaining('Could not save tag'), findsOneWidget);
    expect(find.text('Add tag'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
  });

  testWidgets('while saving, both buttons are disabled and a spinner replaces Add', (tester) async {
    final gated = _GatedTagProvider();
    await open(tester, tagProvider: gated);
    await tester.enterText(find.byType(TextFormField), 'Slow');
    await tester.tap(find.text('Add'));
    await tester.pump();

    expect(find.text('Add'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Cancel')).onPressed, isNull);
    expect((await env.col('tags').get()).docs, isEmpty);

    gated.gate.complete();
    await settle(tester);
    expect(find.text('Add tag'), findsNothing);
    expect((await env.col('tags').get()).docs.single.data()['label'], 'Slow');
  });

  testWidgets('deleting through the provider hides the tag', (tester) async {
    final ref = await env.col('tags').add({'label': 'Gone', 'deleted': false, 'archived': false});
    await open(tester);
    expect(provider.tags.map((t) => t.label), ['Gone']);
    await provider.deleteTag(ref.id);
    await settle(tester);
    expect(provider.tags, isEmpty);
    expect((await ref.get()).data()!['deleted'], true);
  });
}
