import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/recurring_series.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/error_reporting.dart';
import 'package:taskr/shared/constants.dart';

/// The deferral notice is deliberately asymmetric: shown at creation, where the
/// user has context for it, and silent during the launch-time top-up, where an
/// unexplained notice is something they can neither expect nor act on.
///
/// The add-task form itself needs a live Firebase app to mount, so these cover
/// the mechanism and the silence — the two halves that can actually regress.
/// Which occurrences count as deferred is covered in recurring_reminders_test.
void main() {
  late FakeFirebaseFirestore fake;
  late TaskService tasks;
  late RecurringSeriesService series;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    PerformanceService().db = fake;
    tasks = TaskService()..db = fake;
    series = RecurringSeriesService()..db = fake;
    RecurringSeriesService.resetPassGuard();
    resetErrorSnackDedupe();
  });

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: scaffoldMessengerKey,
      home: const Scaffold(body: SizedBox()),
    ));
  }

  testWidgets('the notice surfaces through the global messenger', (tester) async {
    await pumpHost(tester);
    showNoticeSnack('Reminders for this series are still being scheduled.');
    await tester.pump();
    expect(find.text('Reminders for this series are still being scheduled.'), findsOneWidget);
  });

  testWidgets('the launch-time top-up shows no notice, even when it defers', (tester) async {
    await pumpHost(tester);

    // A daily series with a reminder every day: far more in-window reminders
    // than one pass will enqueue, so the pass definitely defers work.
    await tasks.createRecurringSeries(
      RecurringTask(
        recurrenceType: 'Daily',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 365)),
        reminderTimeOfDay: '08:30',
      ),
      Task(added: 1, title: 'standup', priority: Effort.medium, completed: false, tags: const []),
    );

    await series.runLaunchPass();
    await tester.pump();

    expect(find.text('Reminders for this series are still being scheduled.'), findsNothing);
    // Scheduling genuinely fails here (no Firebase app), and the background pass
    // must swallow that too rather than raising an error snackbar at launch.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a series with no reminders defers nothing', (tester) async {
    await pumpHost(tester);

    final written = await tasks.createRecurringSeries(
      RecurringTask(
        recurrenceType: 'Daily',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 5)),
      ),
      Task(added: 1, title: 'standup', priority: Effort.medium, completed: false, tags: const []),
    );

    // What the creation path branches on: nothing deferred, so no notice.
    expect(await ReminderService().enqueueDueReminders(written.occurrences), 0);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a long reminder-bearing series does defer, which is what the notice reports',
      (tester) async {
    await pumpHost(tester);

    final written = await tasks.createRecurringSeries(
      RecurringTask(
        recurrenceType: 'Daily',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 365)),
        reminderTimeOfDay: '08:30',
      ),
      Task(added: 1, title: 'standup', priority: Effort.medium, completed: false, tags: const []),
    );

    final deferred = await ReminderService().enqueueDueReminders(written.occurrences);
    expect(deferred, greaterThan(0));
    // Everything in range beyond the cap.
    expect(deferred, lessThanOrEqualTo(RecurringSeries.reminderEnqueueWindowDays));
  });
}
