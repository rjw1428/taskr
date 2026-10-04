import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/about/about.dart';
import 'package:taskr/app.dart';
import 'package:taskr/goals/goal_form.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/notifications/notification_center.dart';
import 'package:taskr/performance/performance_page.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/settings/settings.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/theme.dart';
import 'package:taskr/work/work_item_form.dart';
import 'package:taskr/work/work_page.dart';

import 'helpers/harness.dart';

/// The phone layout is covered by home_test.dart at 400px. These tests pin the
/// wide-screen (web/desktop) layout and the breakpoints that select it.

/// Sizes the test window itself (not just the paint surface) so MediaQuery,
/// which the layout reads, reports [size].
Future<void> setWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  late TestEnv env;
  setUp(() async {
    env = await TestEnv.create();
    DateService().setSelectedDate(DateTime(2026, 9, 19));
  });
  tearDown(() => env.dispose());

  Future<void> mount(WidgetTester tester, Size size) async {
    await setWindow(tester, size);
    await tester.pumpWidget(const MyApp());
    await settle(tester);
  }

  Finder railTab(String label) =>
      find.descendant(of: find.byType(NavigationRail), matching: find.text(label));

  group('LayoutSize', () {
    // A widget test like its siblings: the shared setUp builds the harness and
    // must run under the widget binding.
    testWidgets('maps window widths to the three layouts', (tester) async {
      expect(LayoutSize.fromWidth(0), LayoutSize.compact);
      expect(LayoutSize.fromWidth(839), LayoutSize.compact);
      expect(LayoutSize.fromWidth(840), LayoutSize.medium);
      expect(LayoutSize.fromWidth(1199), LayoutSize.medium);
      expect(LayoutSize.fromWidth(1200), LayoutSize.expanded);
      expect(LayoutSize.compact.isCompact, isTrue);
      expect(LayoutSize.compact.isWide, isFalse);
      expect(LayoutSize.medium.isWide, isTrue);
      expect(LayoutSize.expanded.isWide, isTrue);
    });
  });

  group('ContentColumn', () {
    Widget wrap(Widget child) => MaterialApp(theme: lightTheme, home: child);

    testWidgets('is transparent on a phone', (tester) async {
      await setWindow(tester, const Size(400, 800));
      await tester.pumpWidget(wrap(const ContentColumn(child: SizedBox.expand(key: Key('body')))));
      expect(tester.getSize(find.byKey(const Key('body'))).width, 400);
      expect(find.ancestor(of: find.byKey(const Key('body')), matching: find.byType(ConstrainedBox)), findsNothing);
    });

    testWidgets('caps and centers its child on a wide screen', (tester) async {
      await setWindow(tester, const Size(1600, 900));
      await tester.pumpWidget(wrap(const ContentColumn(child: SizedBox.expand(key: Key('body')))));
      final body = tester.getRect(find.byKey(const Key('body')));
      expect(body.width, ContentWidths.reading);
      expect(body.height, 900);
      expect(body.center.dx, 800);
      expect(find.ancestor(of: find.byKey(const Key('body')), matching: find.byType(ConstrainedBox)), findsOneWidget);
    });

    testWidgets('honors a custom width and gutter', (tester) async {
      await setWindow(tester, const Size(1000, 600));
      await tester.pumpWidget(wrap(const ContentColumn(
        maxWidth: 2000,
        gutter: 50,
        child: SizedBox.expand(key: Key('body')),
      )));
      // Wider than the window: the gutter is what is left.
      expect(tester.getRect(find.byKey(const Key('body'))), const Rect.fromLTRB(50, 0, 950, 600));
    });
  });

  group('showAppSheet', () {
    Future<void> host(WidgetTester tester, double width, {bool scrollControlled = true}) async {
      await setWindow(tester, Size(width, 800));
      await tester.pumpWidget(MaterialApp(
        theme: lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAppSheet<String>(
                context,
                isScrollControlled: scrollControlled,
                builder: (_) => const AppBottomSheet(title: 'Form', child: Text('body')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('is a bottom sheet with a grab handle on a phone', (tester) async {
      await host(tester, 400, scrollControlled: false);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('body'), findsOneWidget);
      // The handle is the 40x4 bar above the title.
      expect(
        find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 40 && w.constraints?.maxHeight == 4),
        findsOneWidget,
      );
    });

    testWidgets('is a centered dialog without a grab handle on a wide screen', (tester) async {
      await host(tester, 1400);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('body'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 40 && w.constraints?.maxHeight == 4),
        findsNothing,
      );
      final sheet = tester.getRect(find.byType(AppBottomSheet));
      expect(sheet.width, ContentWidths.dialog);
      expect(sheet.center.dx, 700);
      // Tapping the barrier dismisses it like a sheet would.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  });

  group('home shell on a wide screen', () {
    testWidgets('swaps the tab bar for an extended rail and keeps every tab reachable', (tester) async {
      await mount(tester, const Size(1400, 900));
      expect(find.byType(BottomNavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isTrue);
      expect(rail.destinations.map((d) => (d.label as Text).data).toList(),
          ['List', 'Work', 'Performance', 'Goals', 'Backlog', 'People']);
      expect(find.text('Taskr'), findsOneWidget);

      await tester.tap(railTab('Work'));
      await settle(tester);
      expect(find.byType(WorkPage), findsOneWidget);
      expect(find.descendant(of: find.byType(AppBar), matching: find.text('Work')), findsOneWidget);
      expect(tester.widget<NavigationRail>(find.byType(NavigationRail)).selectedIndex, 1);
    });

    testWidgets('a medium window gets a compact rail with labels', (tester) async {
      await mount(tester, const Size(1000, 800));
      expect(find.byType(BottomNavigationBar), findsNothing);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.extended, isFalse);
      expect(rail.labelType, NavigationRailLabelType.all);
      expect(find.text('Taskr'), findsNothing);
      expect(railTab('Backlog'), findsOneWidget);
    });

    testWidgets('a phone-sized window keeps the tab bar', (tester) async {
      await mount(tester, const Size(700, 900));
      expect(find.byType(BottomNavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('centers the page in a reading column with the FAB inside it', (tester) async {
      await mount(tester, const Size(1600, 900));
      final bar = tester.getRect(find.byType(AppBar));
      expect(bar.width, ContentWidths.reading);
      // The column is centered in the space right of the rail, not the window.
      final rail = tester.getRect(find.byType(NavigationRail));
      final area = Rect.fromLTRB(rail.right + 1, 0, 1600, 900);
      expect(bar.center.dx, closeTo(area.center.dx, 1));
      final fab = tester.getRect(find.byType(FloatingActionButton));
      expect(fab.right, lessThanOrEqualTo(bar.right));
      expect(fab.left, greaterThanOrEqualTo(bar.left));
    });

    testWidgets('the performance tab gets the wider dashboard column', (tester) async {
      await mount(tester, const Size(1600, 900));
      await tester.tap(railTab('Performance'));
      await settle(tester);
      expect(find.byType(PerformancePage), findsOneWidget);
      expect(tester.getRect(find.byType(AppBar)).width, ContentWidths.dashboard);
    });

    testWidgets('the FAB opens the task form as a dialog', (tester) async {
      await mount(tester, const Size(1400, 900));
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(find.byType(AddTaskScreen), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await settle(tester);
      expect(find.byType(AddTaskScreen), findsNothing);

      await tester.tap(railTab('Work'));
      await settle(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(find.byType(WorkItemForm), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('the goals chooser is a dialog that leads to the goal form', (tester) async {
      await mount(tester, const Size(1400, 900));
      await tester.tap(railTab('Goals'));
      await settle(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      expect(find.text('New Goal'), findsOneWidget);
      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.text('New Goal'));
      await settle(tester);
      expect(find.byType(GoalForm), findsOneWidget);
      expect(find.text('New Goal'), findsOneWidget); // the form's own title
      expect(find.text('New Habit'), findsNothing); // chooser closed first
    });

    testWidgets('the app bar exposes notifications and settings directly', (tester) async {
      for (final read in [false, true]) {
        await env.col('notifications').add({
          'title': 't', 'body': 'b', 'type': null, 'data': <String, dynamic>{}, 'sentAt': 1, 'read': read,
        });
      }
      await mount(tester, const Size(1400, 900));
      final badge = tester.widget<Badge>(find.byType(Badge));
      expect(badge.isLabelVisible, isTrue);
      expect(find.descendant(of: find.byType(Badge), matching: find.text('1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-notifications')));
      await settle(tester);
      expect(find.byType(NotificationCenterPage), findsOneWidget);
      // Pushed pages sit in the same centered column.
      final pushedBar = find.descendant(of: find.byType(NotificationCenterPage), matching: find.byType(AppBar));
      expect(tester.getRect(pushedBar).width, ContentWidths.reading);
      navigatorKey.currentState!.pop();
      await settle(tester);

      await tester.tap(find.byKey(const Key('home-settings')));
      await settle(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      navigatorKey.currentState!.pop();
      await settle(tester);

      // The overflow menu no longer repeats what the buttons do.
      await tester.tap(find.byIcon(FontAwesomeIcons.bars));
      await settle(tester);
      expect(find.text('Notifications'), findsNothing);
      expect(find.text('Settings'), findsNothing);
      expect(find.text('About'), findsOneWidget);
      await tester.tap(find.text('About'));
      await settle(tester);
      expect(find.byType(AboutPage), findsOneWidget);
      navigatorKey.currentState!.pop();
      await settle(tester);

      await tester.tap(find.byIcon(FontAwesomeIcons.bars));
      await settle(tester);
      await tester.tap(find.text('Logout'));
      await settle(tester);
      expect(env.auth.currentUser, isNull);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('performance dashboard', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Future<void> seed() => env.col('performance').doc(DateService().getString(today)).set({
          'date': Timestamp.fromDate(today),
          'completed': {'ALL': 5, 'Other': 5},
          'pushed': {'ALL': 1},
        });

    testWidgets('stacks a single column when narrow', (tester) async {
      await seed();
      await setWindow(tester, const Size(700, 2600));
      await pumpApp(tester, const PerformancePage(), wrapInScaffold: true, size: const Size(700, 2600));
      await settle(tester, frames: 10);
      expect(find.byKey(const Key('performance-two-column')), findsNothing);
      expect(find.text('Daily score'), findsOneWidget);
      expect(find.text('Records'), findsOneWidget);
    });

    testWidgets('splits into two columns when wide', (tester) async {
      await seed();
      await setWindow(tester, const Size(1400, 1600));
      await pumpApp(tester, const PerformancePage(), wrapInScaffold: true, size: const Size(1400, 1600));
      await settle(tester, frames: 10);
      expect(find.byKey(const Key('performance-two-column')), findsOneWidget);
      // Every section is still present, and the records sit beside (not below) the score.
      expect(find.text('Daily score'), findsOneWidget);
      expect(find.text('Latest accomplishments'), findsOneWidget);
      final score = tester.getRect(find.text('Daily score'));
      final records = tester.getRect(find.text('Records'));
      expect(records.left, greaterThan(score.right));
    });
  });
}
