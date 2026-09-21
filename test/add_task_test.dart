import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/services/tag.provider.dart';
import 'package:taskr/task_list/add_task.dart';
import 'package:taskr/task_list/recurring_task_form.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  // The form's reminder and series paths compare against the clock, so pin it
  // to the day the fixtures are built around instead of the real date.
  final anchor = DateTime(2026, 9, 19, 9);
  setUp(() async {
    env = await TestEnv.create();
    ReminderService().clock = () => anchor;
    RecurringSeriesService().clock = () => anchor;
    DateService().clock = () => anchor;
  });
  tearDown(() => env.dispose());

  const today = '2026-09-19';

  /// Mounts the form on its own route (as the bottom sheet does in production)
  /// so Save/Cancel have something to pop, and so the TagProvider has loaded
  /// before the form reads it in initState.
  Future<void> mount(WidgetTester tester, {Task? task, bool isBacklog = false}) async {
    DateService().setSelectedDate(DateTime(2026, 9, 19));
    await pumpApp(
      tester,
      Builder(
        builder: (context) {
          // Production screens consume the provider long before the form opens;
          // reading it here starts its tag stream the same way.
          context.read<TagProvider>();
          return TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => Scaffold(body: AddTaskScreen(task: task, isBacklog: isBacklog)),
            )),
            child: const Text('open'),
          );
        },
      ),
      wrapInScaffold: true,
      size: const Size(600, 1400),
    );
    await settle(tester, frames: 10);
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f);
    await tester.tap(f);
    await settle(tester);
  }

  /// Taps a picker field's label (they render upper-cased).
  Future<void> tapField(WidgetTester tester, String label) => tapText(tester, label.toUpperCase());

  /// In an open Material date picker: pick [day] and confirm.
  Future<void> pickDay(WidgetTester tester, String day) async {
    await tester.tap(find.text(day));
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  /// Dismisses an open picker; the form has its own Cancel underneath.
  Future<void> cancelDialog(WidgetTester tester) async {
    await tester.tap(find.text('Cancel').last);
    await settle(tester);
  }

  Future<void> okTime(WidgetTester tester) async {
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  /// The clear (x) control of the picker field whose label is [label].
  Finder clearOf(String label) => find.descendant(
        of: find.ancestor(of: find.text(label.toUpperCase()), matching: find.byType(InkWell)).first,
        matching: find.byIcon(FontAwesomeIcons.xmark),
      );

  Future<void> save(WidgetTester tester, [String label = 'Save']) => tapText(tester, label);

  Future<List<Map<String, dynamic>>> items(String date) async =>
      (await env.col('tasks').doc(date).collection('items').get()).docs.map((d) => {...d.data(), 'id': d.id}).toList();

  Future<Map<String, dynamic>> seedTask(String id, Map<String, dynamic> fields) async {
    final date = fields['dueDate'] ?? 'unassigned';
    final data = {
      'title': 'Seeded', 'completed': false, 'priority': 'low', 'added': 1, 'tags': [], 'userId': env.uid,
      'type': 'task', 'modified': '', 'pushCount': 0, 'countdown': false, 'childCount': 0, 'childCompletedCount': 0,
      ...fields,
    };
    await env.col('tasks').doc(date).collection('items').doc(id).set(data);
    await env.col('tasks').doc(date).set({'taskOrder': [id]});
    return {'id': id, ...data};
  }

  String inDays(int days) => DateTime.now().toUtc().add(Duration(days: days)).toIso8601String();

  group('new task', () {
    testWidgets('saves a task on the selected day with effort and description', (tester) async {
      await mount(tester);
      expect(find.text('Add Task'), findsOneWidget);
      expect(find.text(today), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), ' Buy milk ');
      await tester.enterText(find.widgetWithText(TextFormField, 'Description'), 'two litres');
      expect(find.text('This will be scheduled on the selected date.'), findsNothing);
      bool chip(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;
      expect(chip('Low'), isTrue);
      expect(chip('High'), isFalse);
      await tapText(tester, 'High');
      expect(chip('High'), isTrue);
      expect(chip('Low'), isFalse);
      await save(tester);

      final saved = await items(today);
      expect(saved.single['title'], 'Buy milk');
      expect(saved.single['description'], 'two litres');
      expect(saved.single['priority'], 'high');
      expect(saved.single['dueDate'], today);
      expect((await env.col('tasks').doc(today).get()).data()!['taskOrder'], [saved.single['id']]);
      expect(find.text('Task added'), findsOneWidget);
      expect(find.text('Add Task'), findsNothing);
    });

    testWidgets('an empty title fails validation and nothing is written', (tester) async {
      await mount(tester);
      await save(tester);
      expect(find.text('Please enter the title'), findsOneWidget);
      expect(await items(today), isEmpty);
      expect(find.text('Add Task'), findsOneWidget);
    });

    testWidgets('cancel closes the form without saving', (tester) async {
      await mount(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Dropped');
      await tapText(tester, 'Cancel');
      expect(find.text('Add Task'), findsNothing);
      expect(await items(today), isEmpty);
    });

    testWidgets('the due date picker changes the day, cancelling keeps it, clearing sends it to the backlog',
        (tester) async {
      await mount(tester);
      await tapField(tester, 'Due date');
      await cancelDialog(tester);
      expect(find.text(today), findsOneWidget);

      await tapField(tester, 'Due date');
      await pickDay(tester, '20');
      expect(find.text('2026-09-20'), findsOneWidget);

      await tester.tap(clearOf('Due date'));
      await settle(tester);
      expect(find.text('Set a due date'), findsOneWidget);
      expect(find.text('No due date — this goes to your backlog.'), findsOneWidget);
      expect(find.text('START TIME'), findsNothing);

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Someday');
      await save(tester);
      expect((await items('unassigned')).single['title'], 'Someday');
      expect((await env.col('tasks').doc('unassigned').get()).data()!['taskOrder'], isNotEmpty);
    });

    testWidgets('on the backlog the date is optional and picking one schedules the task', (tester) async {
      await mount(tester, isBacklog: true);
      expect(find.text('Set a due date'), findsOneWidget);
      expect(find.text('No due date — this goes to your backlog.'), findsNothing);
      expect(find.text('This will be scheduled on the selected date.'), findsNothing);
      // With no due date the reminder picker still opens (on today).
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Reminder');
      await tapField(tester, 'Remind me at');
      expect(find.text('OK'), findsOneWidget);
      await cancelDialog(tester);
      await tapText(tester, 'Reminder');
      await tapField(tester, 'Due date');
      await pickDay(tester, '21');
      expect(find.text('This will be scheduled on the selected date.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Scheduled');
      await save(tester);
      expect((await items('2026-09-21')).single['title'], 'Scheduled');
    });

    testWidgets('start and end time pickers set, re-open and clear', (tester) async {
      await mount(tester);
      expect(find.text('END TIME'), findsNothing);
      await tapField(tester, 'Start time');
      await cancelDialog(tester);
      expect(find.text('Set a start time'), findsOneWidget);

      await tapField(tester, 'Start time');
      await okTime(tester);
      expect(find.text('Set a start time'), findsNothing);
      expect(find.text('END TIME'), findsOneWidget);

      // Re-open with an existing value so the picker starts from it.
      await tapField(tester, 'Start time');
      await okTime(tester);

      await tapField(tester, 'End time');
      await cancelDialog(tester);
      expect(find.text('Set an end time'), findsOneWidget);
      await tapField(tester, 'End time');
      await okTime(tester);
      expect(find.text('Set an end time'), findsNothing);
      await tapField(tester, 'End time');
      await okTime(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Timed');
      await save(tester);
      final saved = (await items(today)).single;
      expect(saved['startTime'], matches(RegExp(r'^\d{2}:\d{2}$')));
      expect(saved['endTime'], matches(RegExp(r'^\d{2}:\d{2}$')));
    });

    testWidgets('clearing the end time, then the start time, drops both', (tester) async {
      await mount(tester);
      await tapField(tester, 'Start time');
      await okTime(tester);
      await tapField(tester, 'End time');
      await okTime(tester);
      await tester.tap(clearOf('End time'));
      await settle(tester);
      expect(find.text('Set an end time'), findsOneWidget);
      await tester.tap(clearOf('Start time'));
      await settle(tester);
      expect(find.text('Set a start time'), findsOneWidget);
      expect(find.text('END TIME'), findsNothing);
    });

    testWidgets('countdown toggle stores the flag and its optional label', (tester) async {
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Countdown');
      final label = find.widgetWithText(TextFormField, 'Countdown label (optional)');
      expect(label, findsOneWidget);
      await tester.enterText(label, ' Launch ');
      // Off clears the label; on again leaves it blank so the chip uses the title.
      await tapText(tester, 'Countdown');
      expect(label, findsNothing);
      await tapText(tester, 'Countdown');
      expect(tester.widget<TextFormField>(label).controller!.text, '');
      await tester.enterText(label, 'Launch');

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Rocket');
      await save(tester);
      final saved = (await items(today)).single;
      expect(saved['countdown'], true);
      expect(saved['countdownLabel'], 'Launch');
      expect((await env.col('countdowns').get()).docs.map((d) => d.id), [saved['id']]);
    });

    testWidgets('tags can be chosen when the user has some', (tester) async {
      final work = await env.col('tags').add({'label': 'Work', 'deleted': false, 'archived': false});
      await env.col('tags').add({'label': 'Home', 'deleted': false, 'archived': false});
      await env.col('tags').add({'label': 'Gone', 'deleted': true, 'archived': false});
      await mount(tester);
      expect(find.text('TAGS'), findsOneWidget);
      await tapText(tester, 'Add tags');
      expect(find.text('Gone'), findsNothing);
      await tester.tap(find.text('Work'));
      await tester.pump();
      await tester.tap(find.text('OK'));
      await settle(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Tagged');
      await save(tester);
      expect((await items(today)).single['tags'], [work.id]);
    });

    testWidgets('no tags section when the user has none', (tester) async {
      await mount(tester);
      expect(find.text('TAGS'), findsNothing);
      expect(find.text('Add tags'), findsNothing);
    });
  });

  group('multi-day', () {
    testWidgets('creates one task per day with start/middle/end positions', (tester) async {
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Multi-day');
      expect(find.text('END DATE'), findsOneWidget);
      expect(find.text('Recurring'), findsNothing);

      // A day that is not after the start is rejected.
      await tapField(tester, 'End date');
      await pickDay(tester, '19');
      expect(find.text('Set end date'), findsOneWidget);
      await tapField(tester, 'End date');
      await cancelDialog(tester);
      expect(find.text('Set end date'), findsOneWidget);

      await tapField(tester, 'End date');
      await pickDay(tester, '21');
      expect(find.text('2026-09-21'), findsOneWidget);
      // Re-open starting from the chosen end, then clear and choose again.
      await tapField(tester, 'End date');
      await pickDay(tester, '21');
      await tester.tap(clearOf('End date'));
      await settle(tester);
      expect(find.text('Set end date'), findsOneWidget);
      await tapField(tester, 'End date');
      await pickDay(tester, '21');

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Conference');
      await save(tester);

      final d19 = (await items(today)).single;
      final d20 = (await items('2026-09-20')).single;
      final d21 = (await items('2026-09-21')).single;
      expect([d19['multiDayPosition'], d20['multiDayPosition'], d21['multiDayPosition']], ['start', 'middle', 'end']);
      expect({d19['multiDayGroupId'], d20['multiDayGroupId'], d21['multiDayGroupId']}.length, 1);
      expect(find.text('Multi-day task added (3 days)'), findsOneWidget);
      expect(find.text('Add Task'), findsNothing);
    });

    testWidgets('toggling multi-day off saves an ordinary task', (tester) async {
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Multi-day');
      await tapField(tester, 'End date');
      await pickDay(tester, '21');
      await tapText(tester, 'Multi-day');
      expect(find.text('END DATE'), findsNothing);
      expect(find.text('Recurring'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Single');
      await save(tester);
      expect((await items(today)).single['multiDayGroupId'], isNull);
      expect(await items('2026-09-21'), isEmpty);
    });

    testWidgets('a multi-day task without an end date saves as a single task', (tester) async {
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Multi-day');
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Lonely');
      await save(tester);
      expect((await items(today)).single['title'], 'Lonely');
    });

    testWidgets('a start date moved past the end date is rejected and the form stays usable', (tester) async {
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Multi-day');
      await tapField(tester, 'End date');
      await pickDay(tester, '21');
      await tapField(tester, 'Due date');
      await pickDay(tester, '25');
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Backwards');
      await save(tester);

      expect(find.text('Add Task'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
      expect(await items('2026-09-25'), isEmpty);
      expect(await items('2026-09-21'), isEmpty);
    });

    testWidgets('editing a multi-day task whose group is gone opens without an end date', (tester) async {
      final task = Task.fromJson({
        'id': 'gone', 'title': 'Orphan', 'dueDate': today, 'multiDayGroupId': 'missing', 'multiDayPosition': 'start',
        'added': 1,
      });
      await mount(tester, task: task);
      await settle(tester, frames: 10);
      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Set end date'), findsOneWidget);
    });

    testWidgets('editing extends the group and rewrites every day', (tester) async {
      await seedTask('m1', {'dueDate': today, 'multiDayGroupId': 'g1', 'multiDayPosition': 'start', 'title': 'Trip'});
      await seedTask('m2', {'dueDate': '2026-09-20', 'multiDayGroupId': 'g1', 'multiDayPosition': 'end', 'title': 'Trip'});
      final task = Task.fromJson({
        'id': 'm1', 'title': 'Trip', 'dueDate': today, 'multiDayGroupId': 'g1', 'multiDayPosition': 'start', 'added': 1,
      });
      await mount(tester, task: task);
      expect(find.text('Edit Task'), findsOneWidget);
      // Advanced opens by itself; the toggle is locked and the end date is loaded.
      expect(find.text('2026-09-20'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Multi-day')).onChanged, isNull);
      expect(clearOf('End date'), findsNothing);

      await tapField(tester, 'End date');
      await pickDay(tester, '21');
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Long trip');
      await save(tester, 'Update');

      for (final date in [today, '2026-09-20', '2026-09-21']) {
        final day = (await items(date)).single;
        expect(day['title'], 'Long trip', reason: date);
        expect(day['multiDayGroupId'], 'g1');
      }
      expect((await items('2026-09-21')).single['multiDayPosition'], 'end');
      expect((await items('2026-09-20')).single['multiDayPosition'], 'middle');
      expect(find.text('Multi-day task updated'), findsOneWidget);
      expect(find.text('Edit Task'), findsNothing);
    });
  });

  group('recurring', () {
    testWidgets('a series is not saved until its form validates; then template and occurrences are written',
        (tester) async {
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Recurring');
      expect(find.text('Multi-day'), findsNothing);
      expect(find.text('Reminder'), findsNothing);
      expect(find.text('End Date'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Standup');
      await save(tester);
      expect(find.text('End date is required'), findsOneWidget);
      expect(find.text('Add Task'), findsOneWidget);
      expect((await env.col('recurring').get()).docs, isEmpty);

      // Weekly on Mondays until the 30th.
      await tester.tap(find.byType(DropdownButton<String>));
      await settle(tester);
      await tester.tap(find.text('Weekly').last);
      await settle(tester);
      await tester.ensureVisible(find.byType(Checkbox).at(1));
      await tester.tap(find.byType(Checkbox).at(1));
      await settle(tester);
      final endDate = find.widgetWithText(TextFormField, 'End Date');
      await tester.ensureVisible(endDate);
      await tester.tap(endDate);
      await settle(tester);
      await pickDay(tester, '30');
      await save(tester);

      final template = (await env.col('recurring').get()).docs.single.data();
      expect(template['recurrenceType'], 'Weekly');
      expect(template['daysOfWeek'], {'Su': false, 'Mo': true, 'Tu': false, 'We': false, 'Th': false, 'Fr': false, 'Sa': false});
      expect(template['dayOfMonth'], isNull);
      expect(template['startDate'], startsWith('2026-09-19'));
      final mon21 = (await items('2026-09-21')).single;
      expect(mon21['title'], 'Standup');
      expect(mon21['recurringTemplateId'], isNotNull);
      expect((await items('2026-09-28')).single['title'], 'Standup');
      expect(await items(today), isEmpty);
      expect(find.text('Add Task'), findsNothing);
    });

    testWidgets('a daily series with a reminder enqueues reminders after closing and reports the overflow',
        (tester) async {
      env.functions['scheduleReminder'] = (p) => {'reminderTaskName': 'q/${p['taskId']}'};
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Recurring');
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Meds');
      await tapText(tester, 'Set a time');
      await okTime(tester);
      final endDate = find.widgetWithText(TextFormField, 'End Date');
      await tester.ensureVisible(endDate);
      await tester.tap(endDate);
      await settle(tester);
      await pickDay(tester, '30');
      await save(tester);
      await settle(tester, frames: 20);

      expect(find.text('Add Task'), findsNothing);
      final calls = env.functionCalls.where((c) => c.name == 'scheduleReminder').toList();
      // 12 occurrences carry an in-window reminder; the per-pass cap is 10.
      expect(calls.length, 10);
      expect(find.text('Reminders for this series are still being scheduled.'), findsOneWidget);
      final first = (await items(today)).single;
      expect(first['reminderTime'], isNotNull);
      expect(first['reminderTaskName'], 'q/${first['id']}');
    });

    testWidgets('clearing the due date after enabling recurring saves a plain backlog task', (tester) async {
      await mount(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Was recurring');
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Recurring');
      expect(find.byType(RecurringTaskForm), findsOneWidget);
      // Clearing the date hides the recurring section; its stale state must not
      // hijack the save.
      await tester.tap(clearOf('Due date'));
      await settle(tester);
      expect(find.byType(RecurringTaskForm), findsNothing);
      await save(tester);

      expect(find.text('Failed to save task'), findsNothing);
      expect((await items('unassigned')).single['title'], 'Was recurring');
      expect((await env.col('recurring').get()).docs, isEmpty);
    });

    testWidgets('turning recurring back off saves a one-off task, not a series', (tester) async {
      await mount(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Once');
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Recurring');
      expect(find.byType(RecurringTaskForm), findsOneWidget);
      await tapText(tester, 'Recurring');
      expect(find.byType(RecurringTaskForm), findsNothing);
      await save(tester);

      expect((await items(today)).single['title'], 'Once');
      expect((await items(today)).single.containsKey('recurringTemplateId'), isFalse);
      expect((await env.col('recurring').get()).docs, isEmpty);
    });

    testWidgets('an occurrence of a series cannot be turned into another series', (tester) async {
      final task = Task.fromJson({'id': 'r1', 'title': 'Occ', 'dueDate': today, 'recurringTemplateId': 't1', 'added': 1});
      await seedTask('r1', {'dueDate': today, 'recurringTemplateId': 't1'});
      await mount(tester, task: task);
      await tapText(tester, 'Advanced');
      expect(find.text('Recurring'), findsNothing);
      expect(find.text('Multi-day'), findsNothing);
      expect(find.text('Reminder'), findsOneWidget);
    });
  });

  group('reminders', () {
    testWidgets('the save button shows a spinner and is disabled while the write is in flight', (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      env.functions['scheduleReminder'] = (_) => gate.future;
      await mount(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Slow');
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Reminder');
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await okTime(tester);
      await tester.tap(find.text('Save'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save'), findsNothing);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);

      gate.complete({'reminderTaskName': 'n'});
      await settle(tester);
      expect(find.text('Add Task'), findsNothing);
    });

    testWidgets('a new task with a reminder schedules it through the callable', (tester) async {
      env.functions['scheduleReminder'] = (p) {
        expect(p['taskDate'], today);
        expect(p['title'], 'Call mum');
        return {'reminderTaskName': 'queues/r/tasks/1'};
      };
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Reminder');
      expect(find.text('Set date & time'), findsOneWidget);

      // Backing out of either picker leaves it unset.
      await tapField(tester, 'Remind me at');
      await cancelDialog(tester);
      expect(find.text('Set date & time'), findsOneWidget);
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await cancelDialog(tester);
      expect(find.text('Set date & time'), findsOneWidget);

      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await okTime(tester);
      expect(find.textContaining('09/20 '), findsOneWidget);

      // Re-open from the stored instant, then clear, then set again.
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await okTime(tester);
      await tester.tap(clearOf('Remind me at'));
      await settle(tester);
      expect(find.text('Set date & time'), findsOneWidget);
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await okTime(tester);

      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Call mum');
      await save(tester);

      final saved = (await items(today)).single;
      expect(saved['reminderTime'], endsWith('Z'));
      expect(saved['reminderTaskName'], 'queues/r/tasks/1');
      expect(env.functionCalls.single.name, 'scheduleReminder');
      expect(env.functionCalls.single.payload['taskId'], saved['id']);
    });

    testWidgets('turning the reminder toggle off drops the time', (tester) async {
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Reminder');
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await okTime(tester);
      await tapText(tester, 'Reminder');
      expect(find.text('REMIND ME AT'), findsNothing);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Quiet');
      await save(tester);
      expect((await items(today)).single['reminderTime'], isNull);
      expect(env.functionCalls, isEmpty);
    });

    testWidgets('a failing scheduler surfaces as a save error and leaves the form open', (tester) async {
      env.functions['scheduleReminder'] = (_) => throw Exception('cloud tasks down');
      await mount(tester);
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Reminder');
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await okTime(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Fragile');
      await save(tester);
      expect(find.textContaining('Failed to save task'), findsOneWidget);
      expect(find.text('Add Task'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });
  });

  group('editing', () {
    testWidgets('same-day edit updates in place without touching reminders', (tester) async {
      final data = await seedTask('e1', {'dueDate': today, 'title': 'Old', 'description': 'd', 'priority': 'medium'});
      await mount(tester, task: Task.fromJson(data));
      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Old'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'New');
      await save(tester, 'Update');
      final saved = (await items(today)).single;
      expect(saved['id'], 'e1');
      expect(saved['title'], 'New');
      expect(saved['priority'], 'medium');
      expect(env.functionCalls, isEmpty);
      expect(find.text('Task updated'), findsOneWidget);
    });

    testWidgets('a same-day edit leaves an unchanged reminder alone', (tester) async {
      final data = await seedTask('e1r', {
        'dueDate': today, 'title': 'Timed', 'reminderTime': inDays(1), 'reminderTaskName': 'n1',
      });
      await mount(tester, task: Task.fromJson(data));
      await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Timed still');
      await save(tester, 'Update');
      final saved = (await items(today)).single;
      expect(saved['title'], 'Timed still');
      expect(saved['reminderTime'], data['reminderTime']);
      expect(saved['reminderTaskName'], 'n1');
      expect(env.functionCalls, isEmpty);
    });

    testWidgets('adding a reminder to an existing task schedules it', (tester) async {
      env.functions['scheduleReminder'] = (_) => {'reminderTaskName': 'n1'};
      final data = await seedTask('e2', {'dueDate': today, 'title': 'Plain'});
      await mount(tester, task: Task.fromJson(data));
      await tapText(tester, 'Advanced');
      await tapText(tester, 'Reminder');
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '20');
      await okTime(tester);
      await save(tester, 'Update');
      expect(env.functionCalls.map((c) => c.name), ['scheduleReminder']);
      expect((await items(today)).single['reminderTaskName'], 'n1');
    });

    testWidgets('changing an existing reminder cancels the old one and schedules the new', (tester) async {
      env.functions['scheduleReminder'] = (_) => {'reminderTaskName': 'n2'};
      final data = await seedTask('e3', {
        'dueDate': today, 'title': 'Timed', 'reminderTime': inDays(1), 'reminderTaskName': 'n1',
      });
      await mount(tester, task: Task.fromJson(data));
      // Advanced is open because a reminder is set.
      expect(find.text('REMIND ME AT'), findsOneWidget);
      await tapField(tester, 'Remind me at');
      await pickDay(tester, '22');
      await okTime(tester);
      await save(tester, 'Update');
      expect(env.functionCalls.map((c) => c.name), ['cancelReminder', 'scheduleReminder']);
      expect(env.functionCalls.first.payload, {'reminderTaskName': 'n1'});
      expect((await items(today)).single['reminderTaskName'], 'n2');
    });

    testWidgets('clearing an existing reminder cancels it', (tester) async {
      final data = await seedTask('e4', {
        'dueDate': today, 'title': 'Timed', 'reminderTime': inDays(1), 'reminderTaskName': 'n1',
      });
      await mount(tester, task: Task.fromJson(data));
      await tapText(tester, 'Reminder');
      await save(tester, 'Update');
      expect(env.functionCalls.map((c) => c.name), ['cancelReminder']);
      final saved = (await items(today)).single;
      expect(saved['reminderTime'], isNull);
      expect(saved['reminderTaskName'], isNull);
    });

    testWidgets('moving a task to another day cancels, deletes and re-adds it with its reminder', (tester) async {
      env.functions['scheduleReminder'] = (_) => {'reminderTaskName': 'n2'};
      final data = await seedTask('e5', {
        'dueDate': today, 'title': 'Move me', 'reminderTime': inDays(1), 'reminderTaskName': 'n1', 'countdown': true,
      });
      await mount(tester, task: Task.fromJson(data));
      await tapField(tester, 'Due date');
      await pickDay(tester, '21');
      await save(tester, 'Update');

      expect(await items(today), isEmpty);
      final moved = (await items('2026-09-21')).single;
      expect(moved['title'], 'Move me');
      expect(moved['id'], isNot('e5'));
      expect(moved['reminderTime'], data['reminderTime']);
      // The form cancels once and hands deleteTask a copy without the task
      // name, so the old reminder is cancelled exactly once, then rescheduled.
      final names = env.functionCalls.map((c) => c.name).toList();
      expect(names, ['cancelReminder', 'scheduleReminder']);
      expect(env.functionCalls.first.payload, {'reminderTaskName': 'n1'});
      // The reminder is scheduled against the re-added doc's fresh id, so the
      // new task name lands on the moved doc.
      expect(env.functionCalls.last.payload['taskId'], moved['id']);
      expect(moved['reminderTaskName'], 'n2');
      expect((await env.col('tasks').doc(today).get()).data()!['taskOrder'], isEmpty);
    });

    testWidgets('moving a task without a reminder makes no callable calls', (tester) async {
      final data = await seedTask('e6', {'dueDate': today, 'title': 'Move me'});
      await mount(tester, task: Task.fromJson(data));
      await tapField(tester, 'Due date');
      await pickDay(tester, '21');
      await save(tester, 'Update');
      expect(await items(today), isEmpty);
      expect((await items('2026-09-21')).single['title'], 'Move me');
      expect(env.functionCalls, isEmpty);
    });

    testWidgets('a backlog task opens with no date and can be given one', (tester) async {
      final data = await seedTask('b1', {'title': 'Later', 'countdown': true, 'countdownLabel': 'L'});
      await mount(tester, task: Task.fromJson(data), isBacklog: true);
      expect(find.text('Set a due date'), findsOneWidget);
      await tapField(tester, 'Due date');
      await pickDay(tester, '25');
      await save(tester, 'Update');
      expect(await items('unassigned'), isEmpty);
      expect((await items('2026-09-25')).single['title'], 'Later');
    });
  });
}
