import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:taskr/notifications/notification_center.dart';
import 'package:taskr/services/parking_notifications.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<String> seed({required String title, String body = '', bool read = false, int sentAt = 1, String? type}) async {
    final ref = await env.col('notifications').add({
      'title': title, 'body': body, 'type': type, 'data': <String, dynamic>{}, 'sentAt': sentAt, 'read': read,
    });
    return ref.id;
  }

  Future<void> mount(WidgetTester tester) async {
    await pumpApp(tester, const NotificationCenterPage());
    await settle(tester);
  }

  testWidgets('shows the empty state without a menu', (tester) async {
    await pumpApp(tester, const NotificationCenterPage());
    await settle(tester);
    expect(find.text('No notifications'), findsOneWidget);
    expect(find.byIcon(FontAwesomeIcons.ellipsisVertical), findsNothing);
  });

  testWidgets('lists notifications newest first and marks one read on tap', (tester) async {
    final unreadId = await seed(title: 'Unread one', body: 'details', sentAt: 2);
    await seed(title: 'Read one', read: true, sentAt: 1);
    await mount(tester);

    expect(find.text('Unread one'), findsOneWidget);
    expect(find.text('details'), findsOneWidget);
    expect(find.text('Read one'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Unread one')).dy, lessThan(tester.getTopLeft(find.text('Read one')).dy));

    await tester.tap(find.text('Unread one'));
    await settle(tester);
    expect((await env.col('notifications').doc(unreadId).get()).data()?['read'], isTrue);

    // Tapping an already-read row is a no-op.
    await tester.tap(find.text('Read one'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a parking prompt can be answered from the inbox', (tester) async {
    await seed(title: 'Pay for parking?', type: parkingPromptType, read: true);
    await mount(tester);
    await tester.tap(find.text('Pay for parking?'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('No'));
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('swiping a row deletes it', (tester) async {
    final id = await seed(title: 'Swipe me');
    await mount(tester);
    await tester.drag(find.text('Swipe me'), const Offset(-500, 0));
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    expect((await env.col('notifications').doc(id).get()).exists, isFalse);
  });

  testWidgets('the menu marks all read and clears all', (tester) async {
    await seed(title: 'a');
    await seed(title: 'b');
    await mount(tester);

    await tester.tap(find.byIcon(FontAwesomeIcons.ellipsisVertical));
    await settle(tester);
    await tester.tap(find.text('Mark all read'));
    await settle(tester);
    var rows = (await env.col('notifications').get()).docs;
    expect(rows.every((d) => d.data()['read'] == true), isTrue);

    await tester.tap(find.byIcon(FontAwesomeIcons.ellipsisVertical));
    await settle(tester);
    await tester.tap(find.text('Clear all'));
    await settle(tester);
    rows = (await env.col('notifications').get()).docs;
    expect(rows, isEmpty);
    expect(find.text('No notifications'), findsOneWidget);
  });
}
