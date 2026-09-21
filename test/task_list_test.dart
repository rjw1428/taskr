import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/shared/error_reporting.dart';
import 'package:taskr/task_list/health_page.dart';
import 'package:taskr/task_list/journal_modal.dart';
import 'package:taskr/task_list/subtask_group.dart';
import 'package:taskr/task_list/task_item.dart';
import 'package:taskr/task_list/task_list.dart';
import 'package:taskr/theme.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  // The list opens on the wall-clock day, so seed against it; the selected
  // date is pinned so anything reading DateService does not drift.
  final today = DateService().getString(DateTime.now());
  final tomorrow = DateService().incrementDate(DateTime.now());
  final yesterday = DateService().decrementDate(DateTime.now());

  setUp(() async {
    env = await TestEnv.create();
    // Pinned far from today so the day navigation tests can tell whether the
    // screen actually pushed the day it shows into DateService.
    DateService().setSelectedDate(DateTime(2000, 1, 1));
  });
  tearDown(() {
    TaskListState.searchOverride = null;
    env.dispose();
  });

  Future<String> seed(String title, {String? date, Effort priority = Effort.low, Task? task}) =>
      TaskService().addTask(task ?? Task(added: 1, title: title, dueDate: date, priority: priority));

  Future<List<String>> order(String date) async =>
      List<String>.from((await env.col('tasks').doc(date).get()).data()?['taskOrder'] ?? const []);

  Future<Map<String, dynamic>?> item(String date, String id) async =>
      (await env.col('tasks').doc(date).collection('items').doc(id).get()).data();

  Future<void> pumpList(WidgetTester tester, {bool isBacklog = false}) async {
    await pumpApp(tester, TaskListScreen(isBacklog: isBacklog), wrapInScaffold: true);
    await settle(tester, frames: 8);
  }

  group('day view', () {
    testWidgets('shows a loading screen until the first snapshot arrives', (tester) async {
      await seed('Buy milk', date: today);
      // A single frame, before the fake stream has delivered anything (pumpApp
      // pumps twice, which is already past that point).
      await tester.pumpWidget(ChangeNotifierProvider<TagProvider>(
        create: (_) => TagProvider(),
        child: MaterialApp(theme: lightTheme, home: const Scaffold(body: TaskListScreen())),
      ));
      expect(find.text('Loading Tasks...'), findsOneWidget);
      expect(find.text('You have nothing scheduled 🎉'), findsNothing);
      await settle(tester, frames: 8);
      expect(find.text('Loading Tasks...'), findsNothing);
      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('shows the seeded tasks in order', (tester) async {
      await seed('Buy milk', date: today);
      await seed('Walk dog', date: today);
      await pumpList(tester);

      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.text('Walk dog'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Buy milk')).dy, lessThan(tester.getTopLeft(find.text('Walk dog')).dy));
      expect(find.text(today), findsOneWidget);
      expect(find.text(DateService().getDayOfWeek(DateTime.now())), findsOneWidget);
      expect(find.text('You have nothing scheduled 🎉'), findsNothing);
    });

    testWidgets('an empty day shows the nothing-scheduled message', (tester) async {
      await pumpList(tester);
      expect(find.text('You have nothing scheduled 🎉'), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.backwardStep), findsNothing);
      expect(find.byIcon(FontAwesomeIcons.forwardStep), findsNothing);
    });

    testWidgets('completing a task writes completed and moves it to the end of the order', (tester) async {
      final a = await seed('First', date: today, priority: Effort.high);
      final b = await seed('Second', date: today);
      await pumpList(tester);

      await tester.tap(find.byType(Checkbox).first);
      await settle(tester, frames: 8);

      expect((await item(today, a))!['completed'], true);
      expect(await order(today), [b, a]);
      expect((await env.userDoc())!['currentScore'], 3);
    });

    testWidgets('dragging a row by its handle reorders the persisted order', (tester) async {
      final a = await seed('First', date: today);
      final b = await seed('Second', date: today);
      final c = await seed('Third', date: today);
      await pumpList(tester);

      final handle = find.byIcon(FontAwesomeIcons.gripLines).first;
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await settle(tester, frames: 8);

      // Dragged well past the last row, so the first task lands at the end.
      expect(await order(today), [b, c, a]);
    });

    testWidgets('a horizontal swipe changes the day in either direction', (tester) async {
      await pumpList(tester);

      await tester.drag(find.byType(ReorderableListView), const Offset(-120, 0));
      await settle(tester);
      expect(find.text(tomorrow), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.backwardStep), findsOneWidget);
      // The shared selected day (used by the add-task form) follows the swipe.
      expect(DateService().getString(DateService().getSelectedDate()), tomorrow);

      await tester.drag(find.byType(ReorderableListView), const Offset(120, 0));
      await settle(tester);
      expect(find.text(today), findsOneWidget);
      expect(DateService().getString(DateService().getSelectedDate()), today);

      // A short jitter is ignored.
      await tester.drag(find.byType(ReorderableListView), const Offset(4, 0));
      await settle(tester);
      expect(find.text(today), findsOneWidget);
    });

    testWidgets('the caret and jump-to-today buttons navigate days', (tester) async {
      await seed('Yesterday task', date: yesterday);
      await pumpList(tester);

      String selected() => DateService().getString(DateService().getSelectedDate());

      await tester.tap(find.byIcon(FontAwesomeIcons.caretLeft));
      await settle(tester, frames: 8);
      expect(find.text(yesterday), findsOneWidget);
      expect(find.text('Yesterday task'), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.forwardStep), findsOneWidget);
      expect(selected(), yesterday);

      await tester.tap(find.byIcon(FontAwesomeIcons.forwardStep));
      await settle(tester);
      expect(find.text(today), findsOneWidget);
      expect(selected(), today);

      await tester.tap(find.byIcon(FontAwesomeIcons.caretRight));
      await settle(tester);
      expect(find.text(tomorrow), findsOneWidget);
      expect(selected(), tomorrow);

      await tester.tap(find.byIcon(FontAwesomeIcons.backwardStep));
      await settle(tester);
      expect(find.text(today), findsOneWidget);
      expect(selected(), today);
    });

    testWidgets('a habit instance shows its live streak', (tester) async {
      await env.col('habits').doc('h1').set({'title': 'Run', 'startDate': today, 'currentStreak': 4});
      await seed('', task: Task(added: 1, title: 'Run', dueDate: today, habitId: 'h1'));
      await pumpList(tester);
      expect(find.text('4 day streak'), findsOneWidget);
    });

    testWidgets('a container parent is hidden on the day view', (tester) async {
      await seed('', task: Task(added: 1, title: 'Parent', dueDate: today, childCount: 2));
      await pumpList(tester);
      expect(find.text('Parent'), findsNothing);
    });
  });

  group('countdown chips', () {
    testWidgets('upcoming countdowns render as chips and jump to their day', (tester) async {
      await seed('', task: Task(added: 1, title: 'Launch', dueDate: tomorrow, countdown: true, countdownLabel: 'Go'));
      await seed('', task: Task(added: 1, title: 'Old', dueDate: yesterday, countdown: true));
      await pumpList(tester);

      expect(find.text('Go'), findsOneWidget);
      expect(find.text(' · 1d'), findsOneWidget);
      expect(find.text('Old'), findsNothing);

      await tester.tap(find.text('Go'));
      await settle(tester, frames: 8);
      expect(find.text(tomorrow), findsOneWidget);
      expect(find.text('Launch'), findsOneWidget);
      expect(DateService().getString(DateService().getSelectedDate()), tomorrow);
      // Viewed from its own day the countdown is no longer upcoming.
      expect(find.text('Go'), findsNothing);
    });
  });

  group('search', () {
    testWidgets('a query with no hits shows the empty result, and closing search restores the list', (tester) async {
      await seed('Buy milk', date: today);
      await pumpList(tester);

      await tester.tap(find.byIcon(FontAwesomeIcons.magnifyingGlass));
      await settle(tester);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Buy milk'), findsNothing);

      // Too short to search.
      await tester.enterText(find.byType(TextField), 'm');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('No results found'), findsNothing);

      await tester.enterText(find.byType(TextField), 'milk');
      await tester.pump(const Duration(milliseconds: 350));
      // Debounce fired; the (credential-less) search resolves to no hits.
      await settle(tester);
      expect(find.text('No results found'), findsOneWidget);

      // Shortening the query below the threshold drops the stale result.
      await tester.enterText(find.byType(TextField), 'm');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('No results found'), findsNothing);
      expect(find.text('Buy milk'), findsNothing);

      await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
      await settle(tester);
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a hit shows a spinner while loading, then jumps to its day when tapped', (tester) async {
      await seed('Dentist', date: tomorrow);
      TaskListState.searchOverride = (q) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return [
          Task(id: 'x', added: 0, title: 'Dentist', dueDate: tomorrow, completed: true, priority: Effort.high),
          Task(id: 'y', added: 0, title: 'Undated', completed: false),
        ];
      };
      await pumpList(tester);

      await tester.tap(find.byIcon(FontAwesomeIcons.magnifyingGlass));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'den');
      await tester.pump(const Duration(milliseconds: 320));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await settle(tester);

      expect(find.text('Dentist'), findsOneWidget);
      expect(find.text('Undated'), findsOneWidget);
      expect(find.byIcon(FontAwesomeIcons.check), findsOneWidget);

      // An undated hit is inert.
      await tester.tap(find.text('Undated'));
      await settle(tester);
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Dentist'));
      await settle(tester, frames: 8);
      expect(find.byType(TextField), findsNothing);
      expect(find.text(tomorrow), findsOneWidget);
      expect(find.text('Dentist'), findsOneWidget);
      expect(DateService().getString(DateService().getSelectedDate()), tomorrow);
    });
  });

  /// A failed side write (see the reminder test) can queue its error snackbar
  /// ahead of the undo one; drop anything in front of the undo action.
  Future<void> revealUndo(WidgetTester tester) async {
    for (var i = 0; i < 3 && find.text('Undo').evaluate().isEmpty; i++) {
      scaffoldMessengerKey.currentState?.removeCurrentSnackBar();
      await settle(tester);
    }
  }

  /// The undo snackbar hides itself on a 3s timer that must fire before the
  /// test ends.
  Future<void> flushSnackTimer(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await settle(tester);
  }

  group('delete with undo', () {
    testWidgets('removing a task shows an undo snackbar that restores it', (tester) async {
      final id = await seed('Doomed', date: today);
      await pumpList(tester);

      await tester.tap(find.byWidgetPredicate((w) => w is PopupMenuButton));
      await settle(tester);
      await tester.tap(find.text('Remove'));
      await settle(tester, frames: 8);

      expect(find.text('Task removed'), findsOneWidget);
      expect(await item(today, id), isNull);
      expect(find.text('Doomed'), findsNothing);
      expect(env.functionCalls.map((c) => c.name), isNot(contains('cancelReminder')));

      // The snackbar stays until the list's own 3s timer; it does not dismiss itself.
      await tester.pump(const Duration(seconds: 1));
      await settle(tester);
      expect(find.text('Task removed'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester, frames: 8);
      expect((await item(today, id))!['title'], 'Doomed');
      expect(await order(today), [id]);
      expect(find.text('Doomed'), findsOneWidget);

      // The snackbar auto-hides after three seconds.
      await flushSnackTimer(tester);
      expect(find.text('Task removed'), findsNothing);
    });

    testWidgets('a task with a reminder cancels it on delete and reschedules it on undo', (tester) async {
      env.functions['scheduleReminder'] = (_) => {'reminderTaskName': 'projects/x/tasks/new'};
      final when = DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String();
      final id = await seed('',
          task: Task(added: 1, title: 'Ping', dueDate: today, reminderTime: when, reminderTaskName: 'old'));
      await pumpList(tester);

      final state = tester.state<TaskListState>(find.byType(TaskListScreen));
      state.deleteTaskWithUndo(Task(id: id, added: 1, title: 'Ping', dueDate: today, reminderTime: when, reminderTaskName: 'old'));
      await settle(tester, frames: 8);
      expect(env.functionCalls.where((c) => c.name == 'cancelReminder'), hasLength(1));
      await revealUndo(tester);
      expect(find.text('Task removed'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await settle(tester, frames: 8);
      expect(env.functionCalls.map((c) => c.name), contains('scheduleReminder'));
      expect((await item(today, id))!['reminderTaskName'], 'projects/x/tasks/new');
      await flushSnackTimer(tester);
    });

    testWidgets('a delete failure reports the error instead of claiming success', (tester) async {
      await pumpList(tester);
      final state = tester.state<TaskListState>(find.byType(TaskListScreen));
      // No id: the service throws before touching Firestore.
      state.deleteTaskWithUndo(Task(added: 1, title: 'Ghost', dueDate: today));
      await settle(tester);
      expect(find.textContaining('Could not remove task'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a divider row can be deleted and undone', (tester) async {
      final id = await TaskService().addDivider('Morning', today);
      await seed('Under the line', date: today);
      await pumpList(tester);
      expect(find.text('Morning'), findsOneWidget);

      await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
      await settle(tester, frames: 8);
      expect(find.text('Divider removed'), findsOneWidget);
      expect(find.text('Morning'), findsNothing);

      await tester.tap(find.text('Undo'));
      await settle(tester, frames: 8);
      expect(find.text('Morning'), findsOneWidget);
      expect(await order(today), contains(id));
      await flushSnackTimer(tester);
    });
  });

  // The subtask stream's collection-group query (`parentId != null`) is not
  // supported by fake_cloud_firestore, so it errors and self-retries every 3s;
  // the retry timer has to be drained after the tree is gone.
  Future<void> drainSubtaskRetry(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  }

  group('backlog', () {
    testWidgets('renders parents as group cards and hides subtasks at the top level', (tester) async {
      final parentId = await seed('', task: Task(added: 1, title: 'Plan trip', childCount: 2, childCompletedCount: 1));
      await seed('', task: Task(added: 1, title: 'Book flights', parentId: parentId, parentTitle: 'Plan trip'));
      await seed('Loose end');
      await pumpList(tester, isBacklog: true);

      expect(find.text('Backlog'), findsOneWidget);
      expect(find.byType(SubtaskGroupCard), findsOneWidget);
      expect(find.text('Plan trip'), findsOneWidget);
      expect(find.byType(TaskItem), findsOneWidget);
      expect(find.text('Loose end'), findsOneWidget);
      // The subtask lives only inside its parent's card, never as its own row.
      expect(find.text('Book flights'), findsNothing);
      // No day chrome in the backlog.
      expect(find.byIcon(FontAwesomeIcons.magnifyingGlass), findsNothing);
      expect(find.byIcon(FontAwesomeIcons.caretLeft), findsNothing);
      await drainSubtaskRetry(tester);
    });

    testWidgets('completing a backlog task persists to the unassigned partition', (tester) async {
      final a = await seed('One');
      final b = await seed('Two');
      await pumpList(tester, isBacklog: true);

      await tester.tap(find.byType(Checkbox).first);
      await settle(tester, frames: 8);
      expect((await item('unassigned', a))!['completed'], true);
      expect(await order('unassigned'), [b, a]);
      await drainSubtaskRetry(tester);
    });
  });

  group('owner footer', () {
    testWidgets('the journal and health buttons open their pages when entries exist', (tester) async {
      env.dispose();
      env = await TestEnv.create(email: ownerEmail);
      await env.col('journal').doc(today).set({'date': today, 'thinking': 'deep'});
      await env.col('health').doc(today).set({'date': today, 'steps': 1200});
      await seed('Owner task', date: today);
      await pumpList(tester);

      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('Health'), findsOneWidget);

      await tester.tap(find.text('Health'));
      await settle(tester, frames: 8);
      expect(find.byType(HealthPage), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await settle(tester, frames: 8);
      expect(find.byType(HealthPage), findsNothing);

      await tester.tap(find.text('Journal'));
      await settle(tester, frames: 8);
      expect(find.byType(JournalModal), findsOneWidget);
    });

    testWidgets('the health button is hidden without an entry and the footer is absent for other users',
        (tester) async {
      env.dispose();
      env = await TestEnv.create(email: ownerEmail);
      await pumpList(tester);
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('Health'), findsNothing);

      env.dispose();
      env = await TestEnv.create();
      await pumpList(tester);
      expect(find.text('Journal'), findsNothing);
    });
  });

  group('FCM token', () {
    testWidgets('a fresh token is persisted and later rotations are too', (tester) async {
      await pumpList(tester);
      expect((await env.userDoc())!['fcmToken'], 'fcm-token');

      env.push.onTokenRefreshController.add('rotated');
      await settle(tester);
      expect((await env.userDoc())!['fcmToken'], 'rotated');
    });

    testWidgets('an unchanged token is not rewritten', (tester) async {
      await env.db.collection('todos').doc(env.uid).update({'fcmToken': 'fcm-token'});
      await pumpList(tester);
      expect(env.push.permissionRequests, 1);
      expect((await env.userDoc())!['fcmToken'], 'fcm-token');
    });

    testWidgets('a missing profile skips the token dance', (tester) async {
      await env.db.collection('todos').doc(env.uid).delete();
      await pumpList(tester);
      expect(env.push.permissionRequests, 0);
    });
  });
}
