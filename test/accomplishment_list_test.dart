import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/accomplishments/accomplishment_detail_page.dart';
import 'package:taskr/accomplishments/accomplishment_list.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> seed(String id, String date, {String? title, int score = 5}) => env.col('accomplishments').doc(id).set({
        'title': title ?? id,
        'description': 'about $id',
        'date': date,
        'difficultyScore': score,
      });

  Future<void> mount(WidgetTester tester) async {
    await pumpApp(tester, const AccomplishmentListPage());
    await settle(tester);
  }

  testWidgets('shows the empty state when nothing has been logged', (tester) async {
    await mount(tester);
    expect(find.text('No accomplishments yet'), findsOneWidget);
    expect(find.text('Log a win from the Performance tab and it will show up here.'), findsOneWidget);
  });

  testWidgets('groups entries under month headings newest-first and formats the date', (tester) async {
    await seed('a', '2026-08-14T10:00:00.000', title: 'Shipped v2', score: 9);
    await seed('b', '2026-08-02T10:00:00.000', title: 'Fixed the build', score: 3);
    await seed('c', '2026-06-21T10:00:00.000', title: 'Ran a 10k', score: 6);
    await seed('d', 'not-a-date', title: 'Undated thing');

    await mount(tester);

    expect(find.text('Accomplishments'), findsOneWidget);
    expect(find.text('August 2026'), findsOneWidget);
    expect(find.text('June 2026'), findsOneWidget);
    expect(find.text('Undated'), findsOneWidget);
    expect(find.text('Shipped v2'), findsOneWidget);
    expect(find.text('08/14'), findsOneWidget);
    expect(find.text('08/02'), findsOneWidget);
    expect(find.text('06/21'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Order: August heading precedes June heading.
    final aug = tester.getTopLeft(find.text('August 2026')).dy;
    final jun = tester.getTopLeft(find.text('June 2026')).dy;
    expect(aug, lessThan(jun));

    // A short first page means the end of history: no loading footer.
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tapping a row opens its detail page', (tester) async {
    await seed('a', '2026-08-14T10:00:00.000', title: 'Shipped v2', score: 9);
    await mount(tester);

    await tester.tap(find.text('Shipped v2'));
    await settle(tester);

    expect(find.byType(AccomplishmentDetailPage), findsOneWidget);
    expect(find.text('Date: 2026-08-14T10:00:00.000'), findsOneWidget);
    expect(find.text('about a'), findsOneWidget);
  });

  testWidgets('scrolling to the bottom loads the next page and hides the footer at the end', (tester) async {
    // 40 entries: the first page of 20 is "full", so scrolling near the bottom
    // widens the query to 40 — also full, so the footer stays. The next widen
    // (60) comes back short, which ends pagination and hides the footer.
    for (var i = 0; i < 40; i++) {
      final month = (i % 12 + 1).toString().padLeft(2, '0');
      final day = (i % 28 + 1).toString().padLeft(2, '0');
      await seed('e$i', '2025-$month-${day}T10:00:00.000', title: 'Entry $i');
    }
    await mount(tester);

    // The oldest entry (January, day 1) is not on the first page.
    expect(find.text('Entry 0', skipOffstage: false), findsNothing);

    final list = find.byType(ListView);
    // Each drag lands at the bottom of whatever is loaded, which requests the
    // next page; the oldest entry only appears once the second page is in.
    for (var i = 0; i < 3; i++) {
      await tester.drag(list, const Offset(0, -6000));
      await settle(tester, frames: 10);
    }

    expect(find.text('Entry 0'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('edits made elsewhere propagate into the loaded list', (tester) async {
    await seed('a', '2026-08-14T10:00:00.000', title: 'Before');
    await mount(tester);
    expect(find.text('Before'), findsOneWidget);

    await env.col('accomplishments').doc('a').update({'title': 'After'});
    await settle(tester);

    expect(find.text('Before'), findsNothing);
    expect(find.text('After'), findsOneWidget);
  });
}
