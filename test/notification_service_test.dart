import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/services.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<String> seed({required String title, bool read = false, int sentAt = 1000, String? type}) async {
    final ref = await env.col('notifications').add({
      'title': title,
      'body': 'body of $title',
      'type': type,
      'data': <String, dynamic>{},
      'sentAt': sentAt,
      'read': read,
    });
    return ref.id;
  }

  group('signed in', () {
    test('streamNotifications is newest first with ids', () async {
      await seed(title: 'old', sentAt: 1);
      await seed(title: 'new', sentAt: 2);
      final items = await NotificationService().streamNotifications().first;
      expect(items.map((n) => n.title), ['new', 'old']);
      expect(items.first.id, isNotNull);
      expect(items.first.body, 'body of new');
    });

    test('unreadCount counts only unread rows', () async {
      await seed(title: 'a');
      await seed(title: 'b', read: true);
      await seed(title: 'c');
      expect(await NotificationService().unreadCount().first, 2);
    });

    test('record writes an unread row stamped with the current time', () async {
      await NotificationService().record(title: 'Parking', body: 'Paid', type: 'parking_result', data: {'k': 'v'});
      final rows = (await env.col('notifications').get()).docs;
      expect(rows, hasLength(1));
      final data = rows.single.data();
      expect(data['title'], 'Parking');
      expect(data['read'], isFalse);
      expect(data['type'], 'parking_result');
      expect(data['data'], {'k': 'v'});
      expect(data['sentAt'], isA<int>());
    });

    test('markRead and delete address a single row', () async {
      final a = await seed(title: 'a');
      final b = await seed(title: 'b');
      final service = NotificationService();
      await service.markRead(a);
      expect((await env.col('notifications').doc(a).get()).data()?['read'], isTrue);
      await service.delete(b);
      expect((await env.col('notifications').doc(b).get()).exists, isFalse);
    });

    test('markAllRead flips every unread row and is a no-op when none', () async {
      final service = NotificationService();
      await service.markAllRead();
      await seed(title: 'a');
      await seed(title: 'b');
      await seed(title: 'c', read: true);
      await service.markAllRead();
      final rows = (await env.col('notifications').get()).docs;
      expect(rows.every((d) => d.data()['read'] == true), isTrue);
      expect(await service.unreadCount().first, 0);
    });

    test('clearAll removes every row and is a no-op when none', () async {
      final service = NotificationService();
      await service.clearAll();
      await seed(title: 'a');
      await seed(title: 'b');
      await service.clearAll();
      expect((await env.col('notifications').get()).docs, isEmpty);
    });

    test('goal reminder preference round-trips through the user doc', () async {
      final service = NotificationService();
      expect(await service.watchGoalReminders(env.uid).first, GoalReminderSchedule.both);
      await service.setGoalReminders(env.uid, GoalReminderSchedule.eveningOnly);
      expect(await service.watchGoalReminders(env.uid).first, GoalReminderSchedule.eveningOnly);
      expect((await env.userDoc())?['email'], 'test@example.com');
    });
  });

  group('signed out', () {
    setUp(() async {
      env.dispose();
      env = await TestEnv.create(signedIn: false);
    });

    test('streams are empty and record is a no-op', () async {
      final service = NotificationService();
      expect(await service.streamNotifications().first, isEmpty);
      expect(await service.unreadCount().first, 0);
      await service.record(title: 't', body: 'b');
      expect((await env.col('notifications').get()).docs, isEmpty);
    });
  });

  test('GoalReminderSchedule.fromWire tolerates junk', () {
    expect(GoalReminderSchedule.fromWire('5pm'), GoalReminderSchedule.eveningOnly);
    expect(GoalReminderSchedule.fromWire('off'), GoalReminderSchedule.off);
    expect(GoalReminderSchedule.fromWire(null), GoalReminderSchedule.both);
    expect(GoalReminderSchedule.fromWire(42), GoalReminderSchedule.both);
  });
}
