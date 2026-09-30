import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/work.service.dart';
import 'package:taskr/work/work_page.dart';

import 'helpers/clipboard.dart';
import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  late WorkService service;
  var clock = 1000;

  setUp(() async {
    env = await TestEnv.create();
    clock = 1000;
    service = WorkService()..now = () => ++clock;
  });
  tearDown(() => env.dispose());

  Future<Map<String, dynamic>?> stored(String id) async => (await env.col('work').doc(id).get()).data();

  Future<void> pump(WidgetTester tester) async {
    await pumpApp(tester, WorkPage(service: service), wrapInScaffold: true, size: const Size(400, 900));
    await settle(tester);
  }

  NextAction act(String id, String text, {String? waiting, int? done}) =>
      NextAction(id: id, text: text, createdAt: 1, waitingOn: waiting, completedAt: done);

  testWidgets('empty state', (tester) async {
    await pump(tester);
    expect(find.text('Nothing in flight'), findsOneWidget);
  });

  testWidgets('items render in position order with open actions, completed hidden, badge logic', (tester) async {
    final a = await service.add(WorkItem(title: 'Alpha', nextActions: [act('1', 'Do one'), act('2', 'Old', done: 5)]));
    final b = await service.add(WorkItem(title: 'Beta'));
    final c = await service.add(WorkItem(title: 'Gamma', nextActions: [act('3', 'Three'), act('4', 'Four')]));
    await service.reorder([c, a, b]);
    await pump(tester);

    final titles = ['Gamma', 'Alpha', 'Beta'].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(titles[0] < titles[1] && titles[1] < titles[2], isTrue);
    expect(find.text('Do one'), findsOneWidget);
    expect(find.text('Old'), findsNothing);
    expect(find.text('Three'), findsOneWidget);
    expect(find.text('Four'), findsOneWidget);
    expect(find.byKey(Key('no-next-action-$b')), findsOneWidget);
    expect(find.byKey(Key('no-next-action-$a')), findsNothing);
    expect(find.text('3 priorities'), findsOneWidget);
  });

  testWidgets('waiting row shows glyph and label, keeps insertion order', (tester) async {
    await service.add(WorkItem(title: 'P', nextActions: [act('w', 'Numbers', waiting: 'Finance'), act('x', 'Draft')]));
    await pump(tester);
    expect(find.byKey(const Key('waiting-glyph')), findsOneWidget);
    expect(find.text('Waiting on Finance'), findsOneWidget);
    expect(find.byKey(const Key('complete-w')), findsNothing);
    expect(find.byKey(const Key('complete-x')), findsOneWidget);
    expect(tester.getTopLeft(find.text('Numbers')).dy < tester.getTopLeft(find.text('Draft')).dy, isTrue);
  });

  testWidgets('send to end moves a next action last in one write', (tester) async {
    final id = await service.add(WorkItem(title: 'P', nextActions: [act('1', 'One'), act('2', 'Two'), act('3', 'Three')]));
    await pump(tester);
    await tester.tap(find.byKey(const Key('send-to-end-1')));
    await settle(tester);
    final ids = ((await stored(id))!['nextActions'] as List).map((m) => m['id']).toList();
    expect(ids, ['2', '3', '1']);
    expect(tester.getTopLeft(find.text('One')).dy > tester.getTopLeft(find.text('Three')).dy, isTrue);
  });

  testWidgets('complete hides the action and undo restores it in place', (tester) async {
    final id = await service.add(WorkItem(title: 'P', nextActions: [act('1', 'One'), act('2', 'Two')]));
    await pump(tester);
    await tester.tap(find.byKey(const Key('complete-1')));
    await settle(tester);
    expect(find.text('One'), findsNothing);
    expect(find.text('Done: One'), findsOneWidget);
    expect(((await stored(id))!['nextActions'] as List).first['completedAt'], isA<int>());
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(find.text('One'), findsOneWidget);
    final actions = (await stored(id))!['nextActions'] as List;
    expect(actions.map((m) => m['id']), ['1', '2']);
    expect(actions.first['completedAt'], isNull);
  });

  testWidgets('waiting action completes via its menu', (tester) async {
    await service.add(WorkItem(title: 'P', nextActions: [act('w', 'Numbers', waiting: 'Sam')]));
    await pump(tester);
    await tester.tap(find.byKey(const Key('waiting-menu-w')));
    await settle(tester);
    await tester.tap(find.text('Mark done'));
    await settle(tester);
    expect(find.text('Numbers'), findsNothing);
    expect(find.byKey(const Key('no-next-action-')), findsNothing);
    expect(find.textContaining('No next action'), findsOneWidget);
  });

  testWidgets('send to bottom via overflow rewrites positions only', (tester) async {
    final a = await service.add(WorkItem(title: 'Alpha', notes: 'keep'));
    final b = await service.add(WorkItem(title: 'Beta'));
    final c = await service.add(WorkItem(title: 'Gamma'));
    await pump(tester);
    await tester.tap(find.byKey(Key('item-menu-$a')));
    await settle(tester);
    await tester.tap(find.text('Send to bottom'));
    await settle(tester);
    expect((await stored(a))!['position'], 2);
    expect((await stored(b))!['position'], 0);
    expect((await stored(c))!['position'], 1);
    expect((await stored(a))!['notes'], 'keep');
    expect(tester.getTopLeft(find.text('Alpha')).dy > tester.getTopLeft(find.text('Gamma')).dy, isTrue);
  });

  testWidgets('drag reorder persists position only', (tester) async {
    final a = await service.add(WorkItem(title: 'Alpha', notes: 'keep'));
    final b = await service.add(WorkItem(title: 'Beta'));
    await service.add(WorkItem(title: 'Gamma'));
    await pump(tester);
    final handle = find.byKey(Key('drag-$a'));
    final target = tester.getCenter(find.text('Gamma'));
    final start = tester.getCenter(handle);
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 50));
    final total = target.dy + 60 - start.dy;
    for (var i = 1; i <= 10; i++) {
      await gesture.moveBy(Offset(0, total / 10));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await gesture.up();
    await settle(tester, frames: 10);
    expect((await stored(a))!['position'], 2);
    expect((await stored(b))!['position'], 0);
    expect((await stored(a))!['notes'], 'keep');
    expect(tester.getTopLeft(find.text('Alpha')).dy > tester.getTopLeft(find.text('Gamma')).dy, isTrue);
  });

  testWidgets('add next action from card, reject empty, then accept with waiting', (tester) async {
    final id = await service.add(WorkItem(title: 'P'));
    await pump(tester);
    await tester.tap(find.byKey(Key('add-action-$id')));
    await settle(tester);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Next action is required'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('next-action-text')), 'Get numbers');
    await tester.enterText(find.byKey(const Key('next-action-waiting')), 'Finance');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Get numbers'), findsOneWidget);
    expect(find.text('Waiting on Finance'), findsOneWidget);
    final stored0 = ((await stored(id))!['nextActions'] as List).single;
    expect(stored0['waitingOn'], 'Finance');
    expect(stored0['completedAt'], isNull);
  });

  testWidgets('edit next action clears waiting', (tester) async {
    await service.add(WorkItem(title: 'P', nextActions: [act('w', 'Numbers', waiting: 'Sam')]));
    await pump(tester);
    await tester.tap(find.text('Numbers'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('next-action-waiting')), '');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.byKey(const Key('waiting-glyph')), findsNothing);
    expect(find.byKey(const Key('complete-w')), findsOneWidget);
  });

  testWidgets('archive and delete from overflow', (tester) async {
    final a = await service.add(WorkItem(title: 'Alpha'));
    final b = await service.add(WorkItem(title: 'Beta'));
    await pump(tester);
    await tester.tap(find.byKey(Key('item-menu-$a')));
    await settle(tester);
    await tester.tap(find.text('Archive'));
    await settle(tester);
    expect(find.text('Alpha'), findsNothing);
    expect((await env.col('workArchive').doc(a).get()).exists, isTrue);

    await tester.tap(find.byKey(Key('item-menu-$b')));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Beta'), findsOneWidget);
    await tester.tap(find.byKey(Key('item-menu-$b')));
    await settle(tester);
    await tester.tap(find.text('Delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await settle(tester);
    expect(find.text('Beta'), findsNothing);
    expect(await stored(b), isNull);
  });

  testWidgets('add update from overflow appends to updates', (tester) async {
    final a = await service.add(WorkItem(title: 'Alpha'));
    await pump(tester);
    await tester.tap(find.byKey(Key('item-menu-$a')));
    await settle(tester);
    await tester.tap(find.text('Add update'));
    await settle(tester);
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(find.text('Update is required'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('work-update-text')), 'Shipped it');
    await tester.tap(find.text('Add'));
    await settle(tester);
    expect(((await stored(a))!['updates'] as List).single['text'], 'Shipped it');
  });

  testWidgets('copy all writes board markdown including archived', (tester) async {
    final spy = ClipboardSpy(tester);
    final a = await service.add(WorkItem(title: 'Active one'));
    final b = await service.add(WorkItem(title: 'Old one'));
    await service.archive(b);
    await pump(tester);
    await tester.tap(find.byKey(const Key('work-copy-all')));
    await settle(tester);
    expect(spy.calls, 1);
    expect(spy.text, contains('# Work'));
    expect(spy.text, contains('## Active one'));
    expect(spy.text, contains('# Archived'));
    expect(spy.text, contains('## Old one'));
    expect(find.text('Copied all work as Markdown'), findsOneWidget);
    expect(await stored(a), isNotNull);
  });

  testWidgets('Archived button opens the archive page', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('work-archived')));
    await settle(tester);
    expect(find.text('Archived work'), findsOneWidget);
    expect(find.text('Nothing archived'), findsOneWidget);
  });

  testWidgets('tapping a title opens the detail page', (tester) async {
    await service.add(WorkItem(title: 'Alpha', notes: 'ctx'));
    await pump(tester);
    await tester.tap(find.text('Alpha'));
    await settle(tester);
    expect(find.text('Work item'), findsOneWidget);
    expect(find.text('TIMELINE'), findsOneWidget);
  });

  testWidgets('notes preview and links render on the card', (tester) async {
    await service.add(WorkItem(title: 'Alpha', notes: 'See https://jira.test/ABC-1 soon'));
    await pump(tester);
    expect(find.byWidgetPredicate((w) => w is Text && (w.textSpan?.toPlainText().contains('jira.test') ?? false)), findsOneWidget);
  });
}
