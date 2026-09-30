import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/work/work_detail_page.dart';

import 'helpers/clipboard.dart';
import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late WorkService service;
  var clock = 0;
  setUp(() async {
    env = await TestEnv.create();
    clock = DateTime(2026, 9, 1).millisecondsSinceEpoch;
    service = WorkService()..now = () => clock += 60 * 60 * 1000;
  });
  tearDown(() => env.dispose());

  Future<void> pump(WidgetTester tester, String id, {bool archived = false}) async {
    await pumpApp(tester, WorkDetailPage(itemId: id, archived: archived, service: service), size: const Size(400, 1200));
    await settle(tester);
  }

  Future<String> seed() async {
    final id = await service.add(WorkItem(title: 'Proj', notes: 'See https://jira.test/X-1'));
    await service.setNextActions(id, [
      NextAction(id: 'a', text: 'Draft', createdAt: service.now()),
      NextAction(id: 'b', text: 'Wait', createdAt: service.now(), waitingOn: 'Sam'),
    ]);
    final item = (await service.getActive(id))!;
    await service.setNextActions(id, [item.nextActions[0].copyWith(completedAt: service.now()), item.nextActions[1]]);
    await service.addUpdate(id, 'Shipped phase 1');
    return id;
  }

  testWidgets('shows notes, open actions, and timeline oldest first', (tester) async {
    final id = await seed();
    await pump(tester, id);
    expect(find.text('Work item'), findsOneWidget);
    expect(find.text('Wait'), findsWidgets);
    expect(find.text('Waiting on Sam'), findsOneWidget);
    expect(find.byKey(const Key('detail-action-a')), findsNothing);
    final labels = ['Created', 'Next action added', 'Done', 'Update'];
    final ys = labels.map((l) => tester.getTopLeft(find.textContaining('$l ·').first).dy).toList();
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i] > ys[i - 1], isTrue, reason: '${labels[i]} after ${labels[i - 1]}');
    }
    expect(find.text('Shipped phase 1'), findsOneWidget);
    expect(find.textContaining('Next action added ·'), findsNWidgets(2));
  });

  testWidgets('copy as markdown writes the item', (tester) async {
    final spy = ClipboardSpy(tester);
    final id = await seed();
    await pump(tester, id);
    await tester.tap(find.byKey(const Key('detail-menu')));
    await settle(tester);
    await tester.tap(find.text('Copy as Markdown'));
    await settle(tester);
    expect(spy.text, startsWith('## Proj'));
    expect(spy.text, contains('- [x] Draft'));
    expect(spy.text, contains('(waiting on Sam)'));
    expect(spy.text, contains('### Updates'));
    expect(find.text('Copied "Proj" as Markdown'), findsOneWidget);
  });

  testWidgets('complete from detail with undo, add action and update', (tester) async {
    final id = await service.add(WorkItem(title: 'P', nextActions: [NextAction(id: 'a', text: 'Draft', createdAt: 1)]));
    await pump(tester, id);
    await tester.tap(find.byKey(const Key('complete-a')));
    await settle(tester);
    expect(find.text('Draft'), findsWidgets); // still present in the timeline
    expect(find.byKey(const Key('detail-action-a')), findsNothing);
    expect(find.textContaining('Done ·'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.byKey(const Key('detail-action-a')), findsOneWidget);

    await tester.tap(find.byKey(const Key('detail-add-action')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('next-action-text')), 'Second');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.byKey(const Key('detail-action-')), findsNothing);
    expect(find.text('Second'), findsWidgets);

    await tester.tap(find.byKey(const Key('detail-menu')));
    await settle(tester);
    await tester.tap(find.text('Add update'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('work-update-text')), 'Note');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.textContaining('Update ·'), findsOneWidget);
  });

  testWidgets('archive from detail pops and moves the item', (tester) async {
    final id = await service.add(WorkItem(title: 'P'));
    await pumpApp(
      tester,
      Builder(
        builder: (c) => ElevatedButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => WorkDetailPage(itemId: id, archived: false, service: service))),
          child: const Text('go'),
        ),
      ),
      wrapInScaffold: true,
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('detail-menu')));
    await settle(tester);
    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(find.text('go'), findsOneWidget);
    expect((await env.col('workArchive').doc(id).get()).exists, isTrue);
  });

  testWidgets('archived mode is read-mostly with restore and timeline events', (tester) async {
    final id = await service.add(WorkItem(title: 'P', nextActions: [NextAction(id: 'a', text: 'Open', createdAt: 1, waitingOn: 'Bo')]));
    await service.archive(id);
    await pumpApp(
      tester,
      Builder(
        builder: (c) => ElevatedButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => WorkDetailPage(itemId: id, archived: true, service: service))),
          child: const Text('go'),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(400, 1200),
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    expect(find.text('Archived work'), findsOneWidget);
    expect(find.byKey(const Key('complete-a')), findsNothing);
    expect(find.byKey(const Key('detail-add-action')), findsNothing);
    expect(find.text('Open (waiting on Bo)'), findsOneWidget);
    expect(find.textContaining('Archived ·'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-menu')));
    await settle(tester);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Copy as Markdown'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    await tester.tap(find.byKey(const Key('detail-restore')));
    await settle(tester);
    expect(find.text('go'), findsOneWidget);
    final back = (await env.col('work').doc(id).get()).data()!;
    expect(back['restoredAt'], isA<int>());
    expect(back['archivedAt'], isNull);
  });

  testWidgets('delete from archived detail after confirm', (tester) async {
    final id = await service.add(WorkItem(title: 'P'));
    await service.archive(id);
    await pumpApp(
      tester,
      Builder(
        builder: (c) => ElevatedButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => WorkDetailPage(itemId: id, archived: true, service: service))),
          child: const Text('go'),
        ),
      ),
      wrapInScaffold: true,
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('detail-menu')));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    expect(find.text('go'), findsOneWidget);
    expect((await env.col('workArchive').doc(id).get()).exists, isFalse);
  });

  testWidgets('item removed underneath pops the page', (tester) async {
    final id = await service.add(WorkItem(title: 'P'));
    await pumpApp(
      tester,
      Builder(
        builder: (c) => ElevatedButton(
          onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => WorkDetailPage(itemId: id, archived: false, service: service))),
          child: const Text('go'),
        ),
      ),
      wrapInScaffold: true,
    );
    await tester.tap(find.text('go'));
    await settle(tester);
    expect(find.text('Work item'), findsOneWidget);
    await service.delete(id);
    await settle(tester);
    expect(find.text('go'), findsOneWidget);
  });
}
