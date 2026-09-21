import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/task_list/recurring_task_form.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  late GlobalKey<RecurringTaskFormState> key;
  RecurringTask? last;

  Future<void> mount(
    WidgetTester tester, {
    String? startDate = '2026-09-19',
    RecurringTask? template,
    bool hideEndDate = false,
    bool showReminder = false,
  }) async {
    key = GlobalKey<RecurringTaskFormState>();
    last = null;
    await pumpApp(
      tester,
      RecurringTaskForm(
        key: key,
        startDate: startDate,
        recurringTask: template,
        hideEndDate: hideEndDate,
        showReminder: showReminder,
        onRecurringTaskChanged: (t) => last = t,
      ),
      wrapInScaffold: true,
      size: const Size(600, 1400),
    );
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, String type) async {
    await tester.tap(find.byType(DropdownButton<String>));
    await settle(tester);
    await tester.tap(find.text(type).last);
    await settle(tester);
  }

  Future<void> pickEndDate(WidgetTester tester, String day) async {
    await tester.tap(find.widgetWithText(TextFormField, 'End Date'));
    await settle(tester);
    await tester.tap(find.text(day));
    await tester.tap(find.text('OK'));
    await settle(tester);
  }

  testWidgets('daily by default; requires an end date, which the picker sets and the x clears', (tester) async {
    await mount(tester);
    expect(find.text('Daily'), findsOneWidget);
    expect(key.currentState!.validate(), 'Please fix the errors above.');
    await tester.pump();
    expect(find.text('End date is required'), findsOneWidget);

    await pickEndDate(tester, '25');
    expect(find.text('2026-09-25'), findsOneWidget);
    expect(last!.endDate, DateTime(2026, 9, 25));
    expect(last!.startDate, DateTime(2026, 9, 19));
    expect(last!.recurrenceType, 'Daily');
    expect(key.currentState!.validate(), isNull);

    await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
    await settle(tester);
    expect(find.text('2026-09-25'), findsNothing);
    expect(last!.endDate, isNull);
    expect(key.currentState!.validate(), 'Please fix the errors above.');
  });

  testWidgets('dismissing the date picker keeps the previous value', (tester) async {
    await mount(tester, startDate: null);
    await tester.tap(find.widgetWithText(TextFormField, 'End Date'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(last, isNull);
    expect(find.widgetWithText(TextFormField, 'End Date'), findsOneWidget);
  });

  testWidgets('weekly needs a day and a frequency of at least one', (tester) async {
    await mount(tester);
    await choose(tester, 'Weekly');
    expect(find.text('Every'), findsOneWidget);
    expect(find.text('Weeks'), findsOneWidget);
    await pickEndDate(tester, '30');

    expect(key.currentState!.validate(), 'Please select at least one day for weekly recurrence.');

    await tester.tap(find.byType(Checkbox).at(1)); // Mo
    await settle(tester);
    expect(last!.daysOfWeek!['Mo'], isTrue);
    expect(last!.daysOfWeek!['Su'], isFalse);
    expect(key.currentState!.validate(), isNull);

    final frequency = find.widgetWithText(TextFormField, '1');
    await tester.enterText(frequency, '0');
    await settle(tester);
    expect(key.currentState!.validate(), 'Please fix the errors above.');
    await tester.pump();
    expect(find.text('Invalid'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'x');
    expect(last!.frequency, 1); // unparseable falls back to 1
    await tester.enterText(find.byType(TextFormField).first, '2');
    await settle(tester);
    expect(last!.frequency, 2);
    expect(key.currentState!.validate(), isNull);

    await tester.tap(find.byType(Checkbox).at(1)); // untick Mo again
    await settle(tester);
    expect(last!.daysOfWeek!['Mo'], isFalse);
  });

  testWidgets('monthly takes a day of month between 1 and 31', (tester) async {
    await mount(tester);
    await choose(tester, 'Monthly');
    expect(find.text('Day of Month'), findsOneWidget);
    await pickEndDate(tester, '30');

    final field = find.byType(TextFormField).first;
    await tester.enterText(field, '40');
    await settle(tester);
    expect(key.currentState!.validate(), 'Please fix the errors above.');
    await tester.enterText(field, '0');
    await settle(tester);
    expect(key.currentState!.validate(), 'Please fix the errors above.');
    await tester.enterText(field, 'abc');
    expect(last!.dayOfMonth, 1);
    await tester.enterText(field, '15');
    await settle(tester);
    expect(last!.dayOfMonth, 15);
    expect(last!.recurrenceType, 'Monthly');
    expect(key.currentState!.validate(), isNull);

    await choose(tester, 'Yearly');
    expect(last!.recurrenceType, 'Yearly');
    expect(find.text('Day of Month'), findsNothing);
  });

  testWidgets('hideEndDate drops the end date field and its requirement', (tester) async {
    await mount(tester, hideEndDate: true);
    expect(find.widgetWithText(TextFormField, 'End Date'), findsNothing);
    expect(key.currentState!.validate(), isNull);
  });

  testWidgets('the reminder row sets a time of day and clears it', (tester) async {
    await mount(tester, showReminder: true);
    expect(find.text('Set a time'), findsOneWidget);
    expect(find.text('On each occurrence'), findsOneWidget);

    await tester.tap(find.text('Set a time'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(find.text('Set a time'), findsOneWidget);
    expect(last, isNull);

    await tester.tap(find.text('Set a time'));
    await settle(tester);
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('Set a time'), findsNothing);
    expect(last!.reminderTimeOfDay, matches(RegExp(r'^\d{2}:\d{2}$')));

    await tester.tap(find.byIcon(FontAwesomeIcons.xmark));
    await settle(tester);
    expect(find.text('Set a time'), findsOneWidget);
    expect(last!.reminderTimeOfDay, isNull);
  });

  testWidgets('an existing template pre-fills every field', (tester) async {
    await mount(
      tester,
      showReminder: true,
      template: RecurringTask(
        recurrenceType: 'Weekly',
        frequency: 3,
        daysOfWeek: const {'Mo': true, 'Fr': true},
        endDate: DateTime(2026, 12, 1),
        dayOfMonth: 7,
        reminderTimeOfDay: '08:30',
      ),
    );
    expect(find.text('Weekly'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2026-12-01'), findsOneWidget);
    expect(find.text('8:30 AM'), findsOneWidget);
    final boxes = find.byType(Checkbox).evaluate().map((e) => (e.widget as Checkbox).value).toList();
    expect(boxes, [false, true, false, false, false, true, false]);
    expect(key.currentState!.validate(), isNull);

    await choose(tester, 'Monthly');
    expect(find.text('7'), findsOneWidget);
    expect(last!.dayOfMonth, 7);
    expect(last!.reminderTimeOfDay, '08:30');
  });

  testWidgets('a template with null frequency, days and a malformed reminder falls back to defaults', (tester) async {
    await mount(
      tester,
      showReminder: true,
      template: RecurringTask(recurrenceType: 'Daily', frequency: null, dayOfMonth: null, reminderTimeOfDay: 'bad'),
    );
    expect(find.text('Set a time'), findsOneWidget);
    expect(key.currentState!.validate(), 'Please fix the errors above.');

    await mount(tester, showReminder: true, template: RecurringTask(recurrenceType: 'Daily', reminderTimeOfDay: '1:x'));
    expect(find.text('Set a time'), findsOneWidget);
  });
}
