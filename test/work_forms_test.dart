import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/work/work_item_form.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late WorkService service;
  setUp(() async {
    env = await TestEnv.create();
    service = WorkService();
  });
  tearDown(() => env.dispose());

  Future<List<Map<String, dynamic>>> all() async => (await env.col('work').get()).docs.map((d) => d.data()).toList();

  Future<void> open(WidgetTester tester, {WorkItem? item}) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => WorkItemForm(item: item, service: service),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      wrapInScaffold: true,
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  testWidgets('title is required', (tester) async {
    await open(tester);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Title is required'), findsOneWidget);
    expect(await all(), isEmpty);
    await tester.enterText(find.byKey(const Key('work-title')), 'x');
    await tester.pump();
    expect(find.text('Title is required'), findsNothing);
  });

  testWidgets('create without first action', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('work-title')), '  Migrate  ');
    await tester.enterText(find.byKey(const Key('work-notes')), 'ctx');
    await tester.tap(find.text('Add'));
    await settle(tester);
    final docs = await all();
    expect(docs.single['title'], 'Migrate');
    expect(docs.single['notes'], 'ctx');
    expect(docs.single['nextActions'], isEmpty);
    expect(find.byKey(const Key('work-title')), findsNothing);
  });

  testWidgets('create with first next action and waiting', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('work-title')), 'Migrate');
    await tester.enterText(find.byKey(const Key('work-first-action')), 'Ask Sam');
    await tester.enterText(find.byKey(const Key('work-first-waiting')), 'Sam');
    await tester.tap(find.text('Add'));
    await settle(tester);
    final actions = (await all()).single['nextActions'] as List;
    expect(actions.single['text'], 'Ask Sam');
    expect(actions.single['waitingOn'], 'Sam');
    expect(actions.single['completedAt'], isNull);
    expect(actions.single['id'], isNotEmpty);
  });

  testWidgets('edit updates title and notes only, leaving actions and updates', (tester) async {
    final id = await service.add(WorkItem(
      title: 'Old',
      notes: 'n',
      nextActions: [NextAction(id: 'a', text: 'step', createdAt: 1)],
    ));
    await service.addUpdate(id, 'progress');
    final item = (await service.getActive(id))!;
    await open(tester, item: item);
    expect(find.byKey(const Key('work-first-action')), findsNothing);
    expect(find.text('Edit work item'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('work-title')), 'New');
    await tester.enterText(find.byKey(const Key('work-notes')), 'n2');
    await tester.tap(find.text('Save'));
    await settle(tester);
    final doc = (await all()).single;
    expect(doc['title'], 'New');
    expect(doc['notes'], 'n2');
    expect((doc['nextActions'] as List).single['text'], 'step');
    expect((doc['updates'] as List).single['text'], 'progress');
  });
}
