import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/task_list/subtask_group.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  final today = DateService().getString(DateTime.now());

  setUp(() async {
    env = await TestEnv.create();
    DateService().setSelectedDate(DateTime(2026, 9, 19));
  });
  tearDown(() => env.dispose());

  Future<Map<String, dynamic>?> item(String date, String id) async =>
      (await env.col('tasks').doc(date).collection('items').doc(id).get()).data();

  Future<void> mount(WidgetTester tester, Task parent, List<Task> children) async {
    await pumpApp(
      tester,
      Column(children: [
        SubtaskGroupCard(parent: parent, childTasks: children, index: 0, taskService: TaskService()),
      ]),
      wrapInScaffold: true,
    );
    await settle(tester);
  }

  /// A parent with two children (one dated and done, one undated), all stored.
  Future<(Task, List<Task>)> seedFamily() async {
    final parent = Task(added: 1, title: 'Plan trip', childCount: 2, childCompletedCount: 1);
    parent.id = await TaskService().addTask(parent);
    final book = Task(added: 1, title: 'Book flights', parentId: parent.id, parentTitle: parent.title);
    book.id = await TaskService().addTask(book);
    final pack = Task(added: 1, title: 'Pack', parentId: parent.id, parentTitle: parent.title, dueDate: today, completed: true);
    pack.id = await TaskService().addTask(pack);
    return (parent, [pack, book]);
  }

  testWidgets('shows the parent, progress and sorted children with a date chip, and collapses on tap',
      (tester) async {
    final (parent, children) = await seedFamily();
    await mount(tester, parent, children);

    expect(find.text('Plan trip'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Book flights'), findsOneWidget);
    expect(find.text('Pack'), findsOneWidget);
    expect(find.text('No steps yet — add one.'), findsNothing);
    // Incomplete first, then the completed dated one.
    expect(tester.getTopLeft(find.text('Book flights')).dy, lessThan(tester.getTopLeft(find.text('Pack')).dy));
    expect(find.text(DateService().getShortDay(DateTime.now()).replaceAll(RegExp(r'.*'), '')), findsNothing);
    expect(find.byIcon(FontAwesomeIcons.chevronDown), findsOneWidget);

    await tester.tap(find.text('Plan trip'));
    await settle(tester);
    expect(find.byIcon(FontAwesomeIcons.chevronRight), findsOneWidget);
    expect(find.text('Book flights'), findsNothing);
    expect(find.text('No steps yet — add one.'), findsNothing);

    await tester.tap(find.text('Plan trip'));
    await settle(tester);
    expect(find.text('Book flights'), findsOneWidget);
  });

  testWidgets('a completed parent with no steps shows the empty hint', (tester) async {
    await mount(tester, Task(id: 'p', added: 1, title: 'Empty', completed: true), const []);
    expect(find.text('No steps yet — add one.'), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
  });

  testWidgets('children are ordered by completion, then date, then title', (tester) async {
    final parent = Task(id: 'p', added: 1, title: 'P');
    await mount(tester, parent, [
      Task(id: 'c', added: 1, title: 'zeta', parentId: 'p', dueDate: '2026-10-02'),
      Task(id: 'b', added: 1, title: 'beta', parentId: 'p', dueDate: '2026-10-01'),
      Task(id: 'a', added: 1, title: 'alpha', parentId: 'p'),
      Task(id: 'd', added: 1, title: 'delta', parentId: 'p'),
      Task(id: 'e', added: 1, title: 'done', parentId: 'p', completed: true, dueDate: 'not-a-date'),
    ]);
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('beta'), lessThan(y('zeta')));
    expect(y('zeta'), lessThan(y('alpha')));
    expect(y('alpha'), lessThan(y('delta')));
    expect(y('delta'), lessThan(y('done')));
    // An unparseable date falls back to the raw string.
    expect(find.text('not-a-date'), findsOneWidget);
    expect(find.text('Oct 1'), findsOneWidget);
  });

  testWidgets('ticking a child updates it and the parent counter', (tester) async {
    final (parent, children) = await seedFamily();
    await mount(tester, parent, children);

    // Rows are sorted, so the first checkbox is the incomplete "Book flights".
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester);

    final book = children.firstWhere((c) => c.title == 'Book flights');
    expect((await item('unassigned', book.id!))!['completed'], true);
    final stored = await item('unassigned', parent.id!);
    expect(stored!['childCompletedCount'], 2);
    expect(stored['completed'], true);
  });

  group('child menu', () {
    Future<void> openChildMenu(WidgetTester tester, String title) async {
      final row = find.ancestor(of: find.text(title), matching: find.byType(Row)).first;
      await tester.tap(find.descendant(of: row, matching: find.byType(PopupMenuButton<String>)));
      await settle(tester);
    }

    testWidgets('set date schedules the child onto the picked day', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openChildMenu(tester, 'Book flights');
      expect(find.text('Move to backlog'), findsNothing);
      await tester.tap(find.text('Set date'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester, frames: 8);

      final book = children.firstWhere((c) => c.title == 'Book flights');
      expect(await item('unassigned', book.id!), isNull);
      expect((await item(today, book.id!))!['parentId'], parent.id);
    });

    testWidgets('set date on an already-dated child opens the picker on that date', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openChildMenu(tester, 'Pack');
      await tester.tap(find.text('Set date'));
      await settle(tester);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await settle(tester, frames: 8);
      final pack = children.firstWhere((c) => c.title == 'Pack');
      expect((await item(today, pack.id!))!['parentId'], parent.id);
    });

    testWidgets('cancelling the date picker changes nothing', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openChildMenu(tester, 'Book flights');
      await tester.tap(find.text('Set date'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      final book = children.firstWhere((c) => c.title == 'Book flights');
      expect(await item('unassigned', book.id!), isNotNull);
    });

    testWidgets('move to backlog unschedules a dated child', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openChildMenu(tester, 'Pack');
      await tester.tap(find.text('Move to backlog'));
      await settle(tester, frames: 8);
      final pack = children.firstWhere((c) => c.title == 'Pack');
      expect(await item(today, pack.id!), isNull);
      expect(await item('unassigned', pack.id!), isNotNull);
    });

    testWidgets('delete removes the child', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openChildMenu(tester, 'Pack');
      await tester.tap(find.text('Delete'));
      await settle(tester, frames: 8);
      final pack = children.firstWhere((c) => c.title == 'Pack');
      expect(await item(today, pack.id!), isNull);
    });
  });

  group('parent menu', () {
    Future<void> openParentMenu(WidgetTester tester) async {
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await settle(tester);
    }

    testWidgets('edit opens the task form for the parent', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openParentMenu(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester, frames: 8);
      expect(find.byType(AddTaskScreen), findsOneWidget);
    });

    testWidgets('schedule all steps cascades the picked date onto undated incomplete children', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openParentMenu(tester);
      await tester.tap(find.text('Schedule all steps…'));
      await settle(tester);
      await tester.tap(find.text('OK'));
      await settle(tester, frames: 8);

      final book = children.firstWhere((c) => c.title == 'Book flights');
      expect((await item(today, book.id!)), isNotNull);
    });

    testWidgets('schedule all steps can be cancelled', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openParentMenu(tester);
      await tester.tap(find.text('Schedule all steps…'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      final book = children.firstWhere((c) => c.title == 'Book flights');
      expect(await item('unassigned', book.id!), isNotNull);
    });

    testWidgets('delete offers keep-steps and delete-all, and cancel does nothing', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);

      await openParentMenu(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('Delete "Plan trip"?'), findsOneWidget);
      expect(find.textContaining('This has 2 steps'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(await item('unassigned', parent.id!), isNotNull);

      await openParentMenu(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.text('Keep steps'));
      await settle(tester, frames: 8);
      expect(await item('unassigned', parent.id!), isNull);
      final book = children.firstWhere((c) => c.title == 'Book flights');
      final orphan = await item('unassigned', book.id!);
      expect(orphan, isNotNull);
      expect(orphan!.containsKey('parentId'), isFalse);
    });

    testWidgets('delete all removes the parent and its children', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await openParentMenu(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      await tester.tap(find.text('Delete all'));
      await settle(tester, frames: 8);
      expect(await item('unassigned', parent.id!), isNull);
      for (final c in children) {
        expect(await item(c.dueDate ?? 'unassigned', c.id!), isNull);
      }
    });

    testWidgets('deleting a childless parent uses the simple wording, and a failure is reported', (tester) async {
      // No id: the service throws before touching Firestore.
      await mount(tester, Task(added: 1, title: 'Lonely'), const []);
      await openParentMenu(tester);
      await tester.tap(find.text('Delete'));
      await settle(tester);
      expect(find.text('This will be removed.'), findsOneWidget);
      expect(find.text('Keep steps'), findsNothing);
      await tester.tap(find.text('Delete').last);
      await settle(tester, frames: 8);
      expect(find.textContaining('Could not delete'), findsOneWidget);
    });
  });

  group('add subtask', () {
    testWidgets('cancel and a blank title do nothing; a title adds a child', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);

      await tester.tap(find.byTooltip('Add subtask'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      await tester.tap(find.byTooltip('Add subtask'));
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect((await item('unassigned', parent.id!))!['childCount'], 2);

      await tester.tap(find.byTooltip('Add subtask'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Rent car');
      await tester.tap(find.text('Add'));
      await settle(tester, frames: 8);
      expect((await item('unassigned', parent.id!))!['childCount'], 3);
      final added = await env.col('tasks').doc('unassigned').collection('items').where('title', isEqualTo: 'Rent car').get();
      expect(added.docs.single.data()['parentId'], parent.id);
    });

    testWidgets('submitting the field with the keyboard adds the child', (tester) async {
      final (parent, children) = await seedFamily();
      await mount(tester, parent, children);
      await tester.tap(find.byTooltip('Add subtask'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Via keyboard');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, frames: 8);
      expect((await item('unassigned', parent.id!))!['childCount'], 3);
    });

    testWidgets('a parent that cannot take subtasks reports the error', (tester) async {
      await mount(tester, Task(id: 'p', added: 1, title: 'Series', recurringTemplateId: 'r1'), const []);
      await tester.tap(find.byTooltip('Add subtask'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Nope');
      await tester.tap(find.text('Add'));
      await settle(tester, frames: 8);
      expect(find.textContaining('Could not add subtask'), findsOneWidget);
    });
  });
}
