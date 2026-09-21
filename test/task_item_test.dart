import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/goals/goal_detail_page.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/shared/design/tokens.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/task_list/copy_task.dart';
import 'package:taskr/task_list/task_item.dart';
import 'package:taskr/task_list/view_series.dart';

import 'helpers/harness.dart';

/// A silent calendar sign-in that takes a while, so a second "send" can be
/// issued while the first is still in flight.
class _SlowGoogleSignIn extends FakeGoogleSignIn {
  @override
  Future<GoogleAuthResult?> signInSilently(GoogleSignInProfile profile) async {
    await Future<void>.delayed(const Duration(seconds: 5));
    return super.signInSilently(profile);
  }
}

void main() {
  late TestEnv env;
  final today = DateService().getString(DateTime.now());
  final tomorrow = DateService().incrementDate(DateTime.now());

  setUp(() async {
    env = await TestEnv.create();
    DateService().setSelectedDate(DateTime(2026, 9, 19));
  });
  tearDown(() => env.dispose());

  Future<Map<String, dynamic>?> item(String date, String id) async =>
      (await env.col('tasks').doc(date).collection('items').doc(id).get()).data();

  /// Seeds [task] through the service and mounts its row. Returns the stored task.
  Future<Task> mount(
    WidgetTester tester,
    Task task, {
    bool isBacklog = false,
    List<int>? completed,
    List<Task>? deleted,
    Map<String, int> streaks = const {},
    bool seedDoc = true,
  }) async {
    if (seedDoc) task.id = await TaskService().addTask(task);
    await pumpApp(
      tester,
      size: const Size(800, 1200),
      Column(children: [
        TaskItem(
          task: task,
          index: 0,
          onComplete: (int i) => completed?.add(i),
          isBacklog: isBacklog,
          taskService: TaskService(),
          onDelete: (t) => deleted?.add(t),
          habitStreaks: streaks,
        ),
      ]),
      wrapInScaffold: true,
    );
    await settle(tester);
    return task;
  }

  /// Some rows overflow by a pixel or two at test sizes (the calendar menu
  /// entry, the card mid-expansion). Those layout warnings are not what these
  /// tests assert on, so drop them and let anything else fail the test.
  void allowOverflow() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
    await settle(tester);
  }

  group('rendering', () {
    testWidgets('shows the title, push count, time frame, parent link and goal badge', (tester) async {
      await mount(
          tester,
          Task(
            added: 1,
            title: 'Write report',
            dueDate: today,
            pushCount: 2,
            startTime: '09:00',
            endTime: '10:30',
            parentId: 'p1',
            parentTitle: 'Quarter close',
            goalId: 'g1',
          ));
      expect(find.text('Write report'), findsOneWidget);
      expect(find.text('(2)'), findsOneWidget);
      expect(find.text('9:00 AM - 10:30 AM'), findsOneWidget);
      expect(find.text('Quarter close'), findsOneWidget);
      expect(find.text('GOAL'), findsOneWidget);
    });

    testWidgets('a habit instance shows its streak and a completed task is struck through', (tester) async {
      await mount(tester, Task(added: 1, title: 'Meditate', dueDate: today, habitId: 'h1', completed: true),
          streaks: {'h1': 7});
      expect(find.text('7 day streak'), findsOneWidget);
      final text = tester.widget<Text>(find.text('Meditate'));
      expect(text.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('tapping an expandable card reveals the description and tags, tapping again hides them',
        (tester) async {
      allowOverflow();
      await mount(
          tester,
          Task(
            added: 1,
            title: 'Groceries',
            dueDate: today,
            description: 'Milk, eggs',
            tags: [Tag(id: 't1', label: 'home')],
          ));
      expect(find.byIcon(FontAwesomeIcons.solidCircle), findsOneWidget);
      expect(find.text('Milk, eggs'), findsNothing);

      await tester.tap(find.text('Groceries'));
      await settle(tester);
      expect(find.text('Milk, eggs'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.solidCircle), findsNothing);

      await tester.tap(find.text('Groceries'));
      await settle(tester);
      expect(find.text('Milk, eggs'), findsNothing);
    });

    testWidgets('a bare task is not expandable', (tester) async {
      await mount(tester, Task(added: 1, title: 'Plain', dueDate: today));
      expect(find.byIcon(FontAwesomeIcons.solidCircle), findsNothing);
      await tester.tap(find.text('Plain'));
      await settle(tester);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.byIcon(FontAwesomeIcons.solidCircle), findsNothing);
    });

    testWidgets('a description alone, or tags alone, makes the card expandable', (tester) async {
      allowOverflow();
      await mount(tester, Task(added: 1, title: 'Notes only', dueDate: today, description: 'Bring ID'));
      expect(find.byIcon(FontAwesomeIcons.solidCircle), findsOneWidget);
      await tester.tap(find.text('Notes only'));
      await settle(tester);
      expect(find.text('Bring ID'), findsOneWidget);
      await tester.tap(find.text('Notes only'));
      await settle(tester);
      expect(find.text('Bring ID'), findsNothing);

      await mount(tester, Task(added: 1, title: 'Tags only', dueDate: today, tags: [Tag(id: 't1', label: 'errand')]));
      expect(find.byIcon(FontAwesomeIcons.solidCircle), findsOneWidget);
      await tester.tap(find.text('Tags only'));
      await settle(tester);
      expect(find.text('errand'), findsOneWidget);
    });

    testWidgets('multi-day segments render with their connected corners', (tester) async {
      const r = Radius.circular(Corners.md);
      const tight = Radius.circular(4);
      BorderRadius cardCorners() {
        final card = tester.widget<AnimatedContainer>(
            find.descendant(of: find.byType(TaskItem), matching: find.byType(AnimatedContainer)).first);
        return (card.decoration as BoxDecoration).borderRadius as BorderRadius;
      }

      final expected = {
        'start': const BorderRadius.horizontal(left: r, right: tight),
        'middle': const BorderRadius.all(tight),
        'end': const BorderRadius.horizontal(left: tight, right: r),
      };
      for (final position in expected.keys) {
        await mount(
            tester,
            Task(added: 1, title: 'Trip $position', dueDate: today, multiDayGroupId: 'g', multiDayPosition: position),
            seedDoc: false);
        expect(find.text('Trip $position'), findsOneWidget);
        expect(cardCorners(), expected[position], reason: position);
      }
      // A single-day task keeps the full-round card.
      await mount(tester, Task(added: 1, title: 'Single'), seedDoc: false);
      expect(cardCorners(), BorderRadius.circular(Corners.md));
    });

    testWidgets('the parent link needs both a parent id and a title', (tester) async {
      await mount(tester, Task(added: 1, title: 'Orphan step', dueDate: today, parentId: 'p1'), seedDoc: false);
      expect(find.byIcon(FontAwesomeIcons.arrowTurnUp), findsNothing);

      await mount(tester, Task(added: 1, title: 'Not a step', dueDate: today, parentTitle: 'Ghost parent'), seedDoc: false);
      expect(find.text('Ghost parent'), findsNothing);
      expect(find.byIcon(FontAwesomeIcons.arrowTurnUp), findsNothing);
    });
  });

  group('checkbox', () {
    testWidgets('completing a plain task writes the completion, scores it and reports the index', (tester) async {
      final completed = <int>[];
      final task = await mount(tester, Task(added: 1, title: 'Done soon', dueDate: today, priority: Effort.medium),
          completed: completed);
      await tester.tap(find.byType(Checkbox));
      await settle(tester);

      expect(completed, [0]);
      final stored = await item(today, task.id!);
      expect(stored!['completed'], true);
      expect(stored['completedTime'], isNotNull);
      expect((await env.userDoc())!['currentScore'], 2);
      // Not a goal task, so no goal bookkeeping (and no error from it).
      expect(find.textContaining("Couldn't update the goal's progress"), findsNothing);
    });

    testWidgets('un-completing a task takes the points back', (tester) async {
      final completed = <int>[];
      final task = await mount(tester, Task(added: 1, title: 'Oops', dueDate: today, completed: true, priority: Effort.high),
          completed: completed);
      await tester.tap(find.byType(Checkbox));
      await settle(tester);

      expect(completed, isEmpty);
      expect((await item(today, task.id!))!['completed'], false);
      expect((await env.userDoc())!['currentScore'], -3);
    });

    testWidgets('completing a subtask rolls the parent counter', (tester) async {
      final parentId = await TaskService().addTask(Task(added: 1, title: 'Parent', childCount: 1));
      await mount(tester, Task(added: 1, title: 'Step', parentId: parentId, parentTitle: 'Parent'), isBacklog: true);
      await tester.tap(find.byType(Checkbox));
      await settle(tester);

      final parent = await item('unassigned', parentId);
      expect(parent!['childCompletedCount'], 1);
      expect(parent['completed'], true);
    });

    testWidgets('completing a habit instance goes through the habit service', (tester) async {
      await env.col('habits').doc('h1').set({'title': 'Run', 'startDate': today, 'currentStreak': 0});
      final task = await mount(tester, Task(added: 1, title: 'Run', dueDate: today, habitId: 'h1'));
      await tester.tap(find.byType(Checkbox));
      await settle(tester, frames: 8);
      expect((await item(today, task.id!))!['completed'], true);
      // The habit service recomputes the streak from its instances.
      expect((await env.col('habits').doc('h1').get()).data()!['currentStreak'], 1);
    });

    testWidgets('completing a goal task marks it complete on its generation', (tester) async {
      final task = Task(added: 1, title: 'Goal step', dueDate: today, goalId: 'g1');
      task.id = await TaskService().addTask(task);
      await env.col('goals').doc('g1').collection('generations').doc('gen1').set({
        'generatedAt': 1,
        'weekStart': today,
        'weekEnd': today,
        'taskIds': [task.id],
        'prompt': '',
        'response': '',
      });
      await mount(tester, task, seedDoc: false);
      await tester.tap(find.byType(Checkbox));
      await settle(tester);

      final gen = (await env.col('goals').doc('g1').collection('generations').doc('gen1').get()).data();
      expect(gen!['completedTaskIds'], [task.id]);
    });

    testWidgets('un-completing a goal task does not touch its generation', (tester) async {
      final task = Task(added: 1, title: 'Goal step', dueDate: today, goalId: 'g1', completed: true);
      task.id = await TaskService().addTask(task);
      await env.col('goals').doc('g1').collection('generations').doc('gen1').set({
        'generatedAt': 1,
        'weekStart': today,
        'weekEnd': today,
        'taskIds': [task.id],
        'prompt': '',
        'response': '',
      });
      await mount(tester, task, seedDoc: false);
      await tester.tap(find.byType(Checkbox));
      await settle(tester, frames: 8);

      expect((await item(today, task.id!))!['completed'], false);
      final gen = (await env.col('goals').doc('g1').collection('generations').doc('gen1').get()).data();
      expect(gen!['completedTaskIds'] ?? const [], isEmpty);
    });

    testWidgets('a broken generation record does not block completing the goal task', (tester) async {
      final task = Task(added: 1, title: 'Goal step', dueDate: today, goalId: 'g1');
      task.id = await TaskService().addTask(task);
      // Missing required fields, so parsing the generation throws.
      await env.col('goals').doc('g1').collection('generations').doc('gen1').set({'taskIds': [task.id]});
      await mount(tester, task, seedDoc: false);
      await tester.tap(find.byType(Checkbox));
      await settle(tester, frames: 8);
      expect((await item(today, task.id!))!['completed'], true);
      expect(find.textContaining("Couldn't update the goal's progress"), findsOneWidget);
    });
  });

  group('menu', () {
    testWidgets('push moves the task to the next day', (tester) async {
      final task = await mount(tester, Task(added: 1, title: 'Later', dueDate: today));
      await openMenu(tester);
      await tester.tap(find.text('Push'));
      await settle(tester, frames: 10);

      expect(await item(today, task.id!), isNull);
      expect((await item(tomorrow, task.id!))!['pushCount'], 1);
    });

    testWidgets('push is hidden for completed tasks, habits and the backlog', (tester) async {
      await mount(tester, Task(added: 1, title: 'Done', dueDate: today, completed: true));
      await openMenu(tester);
      expect(find.text('Push'), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await settle(tester);

      await mount(tester, Task(added: 1, title: 'Backlogged'), isBacklog: true);
      await openMenu(tester);
      expect(find.text('Push'), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('edit opens the task form and copy opens the copy dialog', (tester) async {
      await mount(tester, Task(added: 1, title: 'Editable', dueDate: today));
      await openMenu(tester);
      await tester.tap(find.text('Edit'));
      await settle(tester, frames: 8);
      expect(find.byType(AddTaskScreen), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, frames: 8);

      await openMenu(tester);
      await tester.tap(find.text('Copy'));
      await settle(tester, frames: 8);
      expect(find.byType(CopyTaskScreen), findsOneWidget);
    });

    testWidgets('remove hands the task to the delete callback', (tester) async {
      final deleted = <Task>[];
      await mount(tester, Task(added: 1, title: 'Bye', dueDate: today), deleted: deleted);
      await openMenu(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester);
      expect(deleted.single.title, 'Bye');
    });

    testWidgets('view series opens the series page for a recurring occurrence', (tester) async {
      await mount(tester, Task(added: 1, title: 'Weekly', dueDate: today, recurringTemplateId: 'r1'));
      await openMenu(tester);
      expect(find.text('Add subtask'), findsNothing);
      await tester.tap(find.text('View Series'));
      await settle(tester, frames: 8);
      expect(find.byType(ViewSeries), findsOneWidget);
    });

    testWidgets('view goal opens the goal page', (tester) async {
      await env.col('goals').doc('g1').set({
        'title': 'Read more',
        'timeframe': '1_week',
        'frequency': 'daily',
        'startDate': today,
        'endDate': DateService().getString(DateTime.now().add(const Duration(days: 7))),
        'createdAt': 1,
        'modifiedAt': 1,
      });
      await mount(tester, Task(added: 1, title: 'Goal step', dueDate: today, goalId: 'g1'));
      await openMenu(tester);
      await tester.tap(find.text('View Goal'));
      await settle(tester, frames: 8);
      expect(find.byType(GoalDetailPage), findsOneWidget);
    });

    testWidgets('feedback is saved from the dialog, and cancelling saves nothing', (tester) async {
      final task = await mount(tester, Task(added: 1, title: 'Goal step', dueDate: today, goalId: 'g1'));
      await openMenu(tester);
      // No feedback yet: the comment icon is not highlighted.
      expect(tester.widget<Icon>(find.byIcon(FontAwesomeIcons.comment)).color, isNull);
      await tester.tap(find.text('Feedback'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect((await item(today, task.id!))!['feedback'], isNull);

      await openMenu(tester);
      await tester.tap(find.text('Feedback'));
      await settle(tester);
      await tester.tap(find.text('Too easy'));
      await settle(tester);
      await tester.tap(find.text('Submit'));
      await settle(tester, frames: 8);
      expect(find.text('Feedback saved'), findsOneWidget);
      expect((await item(today, task.id!))!['feedback'], 'too_easy');
    });

    testWidgets('existing feedback relabels the menu entry', (tester) async {
      await mount(tester, Task(added: 1, title: 'Goal step', dueDate: today, goalId: 'g1', feedback: 'too_hard'));
      await openMenu(tester);
      expect(find.text('Update Feedback'), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(FontAwesomeIcons.comment)).color, Colors.orange);
    });

    testWidgets('send to calendar appears once the calendar is connected and reports a failure', (tester) async {
      allowOverflow();
      await env.db.collection('todos').doc(env.uid).update({'calendarConnectedAt': Timestamp.now()});
      env.google.interactive[GoogleSignInProfile.calendar] = null;
      await mount(tester, Task(added: 1, title: 'Meeting', dueDate: today));
      await openMenu(tester);
      expect(find.text('Send to Calendar'), findsOneWidget);
      await tester.tap(find.text('Send to Calendar'));
      await settle(tester, frames: 8);
      expect(find.textContaining('Could not send'), findsOneWidget);
    });

    testWidgets('a second send while one is in flight is ignored', (tester) async {
      allowOverflow();
      await env.db.collection('todos').doc(env.uid).update({'calendarConnectedAt': Timestamp.now()});
      final google = _SlowGoogleSignIn()..interactive[GoogleSignInProfile.calendar] = null;
      GoogleSignInGateway.override = google;
      await mount(tester, Task(added: 1, title: 'Meeting', dueDate: today));

      await openMenu(tester);
      await tester.tap(find.text('Send to Calendar'));
      await tester.pump();
      await openMenu(tester);
      await tester.tap(find.text('Send to Calendar'));
      await tester.pump(const Duration(seconds: 6));
      await settle(tester, frames: 8);

      expect(google.log.where((e) => e == 'silent:calendar'), hasLength(1));
      expect(find.textContaining('Could not send'), findsOneWidget);
    });

    testWidgets('a task already on the calendar offers an update', (tester) async {
      allowOverflow();
      await env.db.collection('todos').doc(env.uid).update({'calendarConnectedAt': Timestamp.now()});
      await mount(tester, Task(added: 1, title: 'Meeting', dueDate: today, calendarEventId: 'evt'));
      await openMenu(tester);
      expect(find.text('Update on Calendar'), findsOneWidget);
    });

    testWidgets('the train status check is offered for today\'s train task and calls the server', (tester) async {
      await mount(tester, Task(added: 1, title: 'Work Train', dueDate: today, startTime: '07:45'));
      await openMenu(tester);
      await tester.tap(find.text('Check Status'));
      await settle(tester);
      expect(env.functionCalls.map((c) => c.name), contains('checkTrainStatus'));
    });

    testWidgets('the train status check is hidden for other titles, completed and backlog tasks', (tester) async {
      await mount(tester, Task(added: 1, title: 'Other', dueDate: today, startTime: '07:45'));
      await openMenu(tester);
      expect(find.text('Check Status'), findsNothing);
      await tester.tapAt(Offset.zero);
      await settle(tester);

      await mount(tester, Task(added: 1, title: 'Work Train', dueDate: today, startTime: '07:45', completed: true));
      await openMenu(tester);
      expect(find.text('Check Status'), findsNothing);
      await tester.tapAt(Offset.zero);
      await settle(tester);

      await mount(tester, Task(added: 1, title: 'Train Home', dueDate: today, startTime: '17:45'), isBacklog: true);
      await openMenu(tester);
      expect(find.text('Check Status'), findsNothing);
    });

    testWidgets('add subtask: cancel and blank do nothing, a title creates the child', (tester) async {
      final task = await mount(tester, Task(added: 1, title: 'Project', dueDate: today));

      await openMenu(tester);
      await tester.tap(find.text('Add subtask'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      await openMenu(tester);
      await tester.tap(find.text('Add subtask'));
      await settle(tester);
      await tester.tap(find.text('Add'));
      await settle(tester);
      expect((await item(today, task.id!))!['childCount'], 0);

      await openMenu(tester);
      await tester.tap(find.text('Add subtask'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'First step');
      await tester.tap(find.text('Add'));
      await settle(tester, frames: 8);

      // The parent became a backlog container and the child took its date.
      expect(await item(today, task.id!), isNull);
      expect((await item('unassigned', task.id!))!['childCount'], 1);
      final children = await env.col('tasks').doc(today).collection('items').where('parentId', isEqualTo: task.id).get();
      expect(children.docs.single.data()['title'], 'First step');
    });

    testWidgets('submitting the subtask field with the keyboard adds it, and a failure is reported', (tester) async {
      final task = await mount(tester, Task(added: 1, title: 'Project', dueDate: today));
      await openMenu(tester);
      await tester.tap(find.text('Add subtask'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Via keyboard');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester, frames: 8);
      expect((await item('unassigned', task.id!))!['childCount'], 1);

      // No stored parent id: converting the parent fails after the child write.
      await mount(tester, Task(added: 1, title: 'Unsaved', dueDate: today), seedDoc: false);
      await openMenu(tester);
      await tester.tap(find.text('Add subtask'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Orphan');
      await tester.tap(find.text('Add'));
      await settle(tester, frames: 8);
      expect(find.textContaining('Could not add subtask'), findsOneWidget);
    });
  });
}
