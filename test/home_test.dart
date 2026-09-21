import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/about/about.dart';
import 'package:taskr/accomplishments/accomplishment_form.dart';
import 'package:taskr/app.dart';
import 'package:taskr/goals/goal_form.dart';
import 'package:taskr/goals/habit_form.dart';
import 'package:taskr/home/home.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/notifications/notification_center.dart';
import 'package:taskr/people/people_list.dart';
import 'package:taskr/performance/performance_page.dart';
import 'package:taskr/goals/goal_list.dart';
import 'package:taskr/task_list/task_list.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/settings/settings.dart';
import 'package:taskr/task_list/add_task.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async {
    env = await TestEnv.create();
    DateService().setSelectedDate(DateTime(2026, 9, 19));
  });
  tearDown(() => env.dispose());

  Future<void> mount(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MyApp());
    await settle(tester);
  }

  Finder tab(String label) => find.descendant(of: find.byType(BottomNavigationBar), matching: find.text(label));

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(FontAwesomeIcons.bars));
    await settle(tester);
  }

  testWidgets('shows the login screen when signed out', (tester) async {
    env.dispose();
    env = await TestEnv.create(signedIn: false);
    await pumpApp(tester, const HomeScreen());
    await settle(tester);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('switches between every tab and ignores a re-tap', (tester) async {
    await mount(tester);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('List')), findsOneWidget);
    // The inner navigator starts on the list tab, not an unknown route.
    expect(find.text('Unknown sub route'), findsNothing);
    expect(tester.widget<TaskListScreen>(find.byType(TaskListScreen)).isBacklog, isFalse);

    // Each tab must show its own page, not just retitle the app bar.
    final pages = <String, bool Function()>{
      'Performance': () => find.byType(PerformancePage).evaluate().isNotEmpty,
      'Goals': () => find.byType(GoalListPage).evaluate().isNotEmpty,
      'Backlog': () => tester.widget<TaskListScreen>(find.byType(TaskListScreen)).isBacklog,
      'People': () => find.byType(PeopleListPage).evaluate().isNotEmpty,
      'List': () => !tester.widget<TaskListScreen>(find.byType(TaskListScreen)).isBacklog,
    };
    for (final label in pages.keys) {
      await tester.tap(tab(label));
      await settle(tester);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text(label)), findsOneWidget);
      expect(pages[label]!(), isTrue, reason: '$label tab should show its page');
    }
    await tester.tap(tab('List'));
    await settle(tester);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('List')), findsOneWidget);
  });

  testWidgets('the list FAB opens the task form and a long press adds a divider', (tester) async {
    await mount(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.byType(AddTaskScreen), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);
    expect(find.byType(AddTaskScreen), findsNothing);

    await tester.longPress(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('Add Divider'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect((await env.col('tasks').doc('2026-09-19').collection('items').get()).docs, isEmpty);

    await tester.longPress(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Morning');
    await tester.tap(find.text('Add'));
    await settle(tester);
    final items = (await env.col('tasks').doc('2026-09-19').collection('items').get()).docs;
    expect(items.single.data()['type'], 'divider');
    expect(items.single.data()['title'], 'Morning');

    await tester.longPress(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect((await env.col('tasks').doc('2026-09-19').collection('items').get()).docs, hasLength(2));
  });

  testWidgets('the backlog FAB long press adds an unassigned divider', (tester) async {
    await mount(tester);
    await tester.tap(tab('Backlog'));
    await settle(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.byType(AddTaskScreen), findsOneWidget);
    expect(tester.widget<AddTaskScreen>(find.byType(AddTaskScreen)).isBacklog, isTrue);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);

    await tester.longPress(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Later');
    await tester.tap(find.text('Add'));
    await settle(tester);
    final items = (await env.col('tasks').doc('unassigned').collection('items').get()).docs;
    expect(items.single.data()['title'], 'Later');
  });

  testWidgets('the performance FAB opens the accomplishment form', (tester) async {
    await mount(tester);
    await tester.tap(tab('Performance'));
    await settle(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.byType(AccomplishmentForm), findsOneWidget);
  });

  testWidgets('the goals FAB offers a goal or a habit', (tester) async {
    await mount(tester);
    await tester.tap(tab('Goals'));
    await settle(tester);
    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    expect(find.text('New Goal'), findsOneWidget);
    expect(find.text('AI-generated tasks toward a target'), findsOneWidget);
    await tester.tap(find.text('New Goal'));
    await settle(tester);
    expect(find.byType(GoalForm), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await settle(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await settle(tester);
    await tester.tap(find.text('New Habit'));
    await settle(tester);
    expect(find.byType(HabitForm), findsOneWidget);

    // The chooser sheet was closed before the form opened, so backing out of
    // the form lands on the goals tab, not on the sheet.
    navigatorKey.currentState!.pop();
    await settle(tester);
    expect(find.byType(HabitForm), findsNothing);
    expect(find.text('New Habit'), findsNothing);
    expect(find.byType(GoalListPage), findsOneWidget);
  });

  testWidgets('the menu navigates to notifications, settings and about', (tester) async {
    await mount(tester);
    await openMenu(tester);
    await tester.tap(find.text('Notifications'));
    await settle(tester);
    expect(find.byType(NotificationCenterPage), findsOneWidget);
    navigatorKey.currentState!.pop();
    await settle(tester);

    await openMenu(tester);
    await tester.tap(find.text('Settings'));
    await settle(tester);
    expect(find.byType(SettingsPage), findsOneWidget);
    navigatorKey.currentState!.pop();
    await settle(tester);

    await openMenu(tester);
    await tester.tap(find.text('About'));
    await settle(tester);
    expect(find.byType(AboutPage), findsOneWidget);
  });

  testWidgets('logout signs the user out and shows the login screen', (tester) async {
    await mount(tester);
    await openMenu(tester);
    await tester.tap(find.text('Logout'));
    await settle(tester);
    expect(env.auth.currentUser, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('the menu badge shows the unread notification count', (tester) async {
    for (final read in [false, false, true]) {
      await env.col('notifications').add({
        'title': 't', 'body': 'b', 'type': null, 'data': <String, dynamic>{}, 'sentAt': 1, 'read': read,
      });
    }
    await mount(tester);
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
    expect(find.descendant(of: find.byType(Badge), matching: find.text('2')), findsOneWidget);
  });
}
