import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore fake;
  late NotificationService notifications;
  const uid = 'u1';

  setUp(() {
    fake = FakeFirebaseFirestore();
    AuthService().user = MockUser(uid: uid);
    notifications = NotificationService()..db = fake;
  });

  group('default', () {
    test('a user doc without the field keeps both reminders', () async {
      await fake.collection('todos').doc(uid).set({'email': 'a@b.c'});
      expect(await notifications.watchGoalReminders(uid).first, GoalReminderSchedule.both);
    });

    test('a missing user doc keeps both reminders', () async {
      expect(await notifications.watchGoalReminders(uid).first, GoalReminderSchedule.both);
    });

    test('an unrecognised value falls back to both', () async {
      await fake.collection('todos').doc(uid).set({'goalReminderSchedule': 'weekly'});
      expect(await notifications.watchGoalReminders(uid).first, GoalReminderSchedule.both);
    });
  });

  group('round trip', () {
    for (final schedule in GoalReminderSchedule.values) {
      test('${schedule.name} is readable back', () async {
        await notifications.setGoalReminders(uid, schedule);
        expect(await notifications.watchGoalReminders(uid).first, schedule);
      });
    }

    test('writing the preference leaves the rest of the user doc alone', () async {
      await fake.collection('todos').doc(uid).set({'email': 'a@b.c', 'currentScore': 7});
      await notifications.setGoalReminders(uid, GoalReminderSchedule.off);
      final data = (await fake.collection('todos').doc(uid).get()).data()!;
      expect(data['email'], 'a@b.c');
      expect(data['currentScore'], 7);
      expect(data['goalReminderSchedule'], 'off');
    });
  });

  group('wire values', () {
    // The Cloud Functions match on these strings, so a rename here silently
    // stops the sender honouring the setting.
    test('are the contract the functions read', () {
      expect(GoalReminderSchedule.off.wire, 'off');
      expect(GoalReminderSchedule.eveningOnly.wire, '5pm');
      expect(GoalReminderSchedule.both.wire, 'both');
    });
  });
}
