import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/goals/habit_form.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  // Calendar-day arithmetic: adding a Duration crosses the DST change an hour short.
  String day(int offset) {
    final now = DateTime.now();
    return DateService().getString(DateTime(now.year, now.month, now.day + offset));
  }

  Future<List<Map<String, dynamic>>> habits() async =>
      (await env.col('habits').get()).docs.map((d) => {...d.data(), 'id': d.id}).toList();

  Future<int> instanceCount(String habitId) async {
    var n = 0;
    for (final d in (await env.col('tasks').get()).docs) {
      n += (await env.col('tasks').doc(d.id).collection('items').where('habitId', isEqualTo: habitId).get()).size;
    }
    return n;
  }

  /// Pushes the form from a host page so its `pop()` has somewhere to land.
  Future<void> openForm(WidgetTester tester, {Habit? habit}) async {
    await pumpApp(
      tester,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => HabitForm(habit: habit))),
            child: const Text('open'),
          ),
        ),
      ),
      wrapInScaffold: true,
      size: const Size(400, 1400),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> chooseCadence(WidgetTester tester, String next) async {
    await tester.tap(find.byType(DropdownButton<String>));
    await settle(tester);
    await tester.tap(find.text(next).last);
    await settle(tester);
  }

  Finder titleField() => find.widgetWithText(TextFormField, 'Habit');

  testWidgets('requires a title', (tester) async {
    await openForm(tester);
    expect(find.text('New Habit'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Enter a habit name'), findsOneWidget);
    expect(await habits(), isEmpty);
    expect(find.text('New Habit'), findsOneWidget);
  });

  testWidgets('creates a daily habit with the chosen effort and materializes its instances', (tester) async {
    await openForm(tester);
    await tester.enterText(titleField(), '  Stretch ');
    bool chipSelected(String label) =>
        tester.widget<ChoiceChip>(find.ancestor(of: find.text(label), matching: find.byType(ChoiceChip))).selected;
    expect(chipSelected('Low'), isTrue, reason: 'default effort');
    expect(chipSelected('High'), isFalse);
    await tester.tap(find.text('High'));
    await settle(tester);
    expect(chipSelected('High'), isTrue);
    expect(chipSelected('Low'), isFalse);
    expect(chipSelected('Medium'), isFalse);
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Save')).onPressed, isNull,
        reason: 'Save is disabled while the habit is being written');
    await settle(tester, frames: 12);

    expect(find.text('New Habit'), findsNothing, reason: 'popped after save');
    final h = (await habits()).single;
    expect(h['title'], 'Stretch');
    expect(h['effort'], 'high');
    expect(h['recurrenceType'], 'Daily');
    expect(h['frequency'], 1);
    expect(h['status'], 'active');
    expect(h['startDate'], day(0));
    expect(h.containsKey('daysOfWeek'), isFalse);
    expect(h.containsKey('dayOfMonth'), isFalse);
    // Inclusive horizon, matching the recurring series: today through today+60.
    expect(h['lastMaterializedDate'], day(60));
    expect(await instanceCount(h['id'] as String), 61);
  });

  testWidgets('a weekly habit needs at least one day, then stores the chosen days', (tester) async {
    await openForm(tester);
    await tester.enterText(titleField(), 'Gym');
    await chooseCadence(tester, 'Weekly');
    expect(find.text('Every'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Please select at least one day for weekly recurrence.'), findsOneWidget);
    expect(await habits(), isEmpty);

    final mo = find.ancestor(of: find.text('Mo'), matching: find.byType(Column)).first;
    await tester.tap(find.descendant(of: mo, matching: find.byType(Checkbox)));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);

    final h = (await habits()).single;
    expect(h['recurrenceType'], 'Weekly');
    expect(h['daysOfWeek']['Mo'], isTrue);
    expect(h['daysOfWeek']['Tu'], isFalse);
    expect(h.containsKey('dayOfMonth'), isFalse);
    expect(await instanceCount(h['id'] as String), inInclusiveRange(8, 9));
  });

  testWidgets('a monthly habit stores its day of month', (tester) async {
    await openForm(tester);
    await tester.enterText(titleField(), 'Pay rent');
    await tester.tap(find.text('Medium'));
    await chooseCadence(tester, 'Monthly');
    await tester.enterText(find.widgetWithText(TextFormField, 'Day of Month'), '15');
    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);

    final h = (await habits()).single;
    expect(h['effort'], 'medium');
    expect(h['recurrenceType'], 'Monthly');
    expect(h['dayOfMonth'], 15);
    expect(h.containsKey('daysOfWeek'), isFalse);
  });

  testWidgets('editing prefills the form and updates the habit in place', (tester) async {
    final svc = HabitService();
    final id = await svc.addHabit(Habit(
      title: 'Read',
      effort: Effort.medium,
      recurrenceType: 'Weekly',
      daysOfWeek: const {'Su': false, 'Mo': false, 'Tu': true, 'We': false, 'Th': false, 'Fr': false, 'Sa': false},
      startDate: day(0),
    ));
    final habit = (await svc.getHabit(id))!;
    await openForm(tester, habit: habit);

    expect(find.text('Edit Habit'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Read'), findsOneWidget);
    expect(find.text('Every'), findsOneWidget, reason: 'weekly cadence restored');
    final tu = find.ancestor(of: find.text('Tu'), matching: find.byType(Column)).first;
    expect(tester.widget<Checkbox>(find.descendant(of: tu, matching: find.byType(Checkbox))).value, isTrue);

    await tester.enterText(titleField(), 'Read a chapter');
    await tester.tap(find.text('Low'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);

    expect(find.text('Edit Habit'), findsNothing);
    final h = (await habits()).single;
    expect(h['id'], id);
    expect(h['title'], 'Read a chapter');
    expect(h['effort'], 'low');
    expect(h['recurrenceType'], 'Weekly');
    expect(h['daysOfWeek']['Tu'], isTrue);
    expect(h['createdAt'], habit.createdAt, reason: 'createdAt is not rewritten');
  });

  testWidgets('a save failure is reported and the form stays open', (tester) async {
    await openForm(tester);
    await tester.enterText(titleField(), 'Meditate');
    AuthService().user = null;

    await tester.tap(find.text('Save'));
    await settle(tester, frames: 12);

    expect(find.textContaining('Could not save habit:'), findsOneWidget);
    expect(find.text('New Habit'), findsOneWidget);
    expect(await habits(), isEmpty);
  });
}
