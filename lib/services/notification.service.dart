import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/models.dart';

/// Reads the notification records written by Cloud Functions whenever an FCM
/// message is sent (see functions/src/index.ts `recordNotification`). Stored at
/// `todos/{uid}/notifications/{id}` — covered by the existing owner rule.
class NotificationService {
  // `late` so merely constructing the service doesn't touch Firebase, which
  // isn't initialized under `flutter test`.
  late FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  @visibleForTesting
  set db(FirebaseFirestore db) => _db = db;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) => _db.collection('todos').doc(uid);

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('todos').doc(uid).collection('notifications');

  Stream<List<AppNotification>> streamNotifications() {
    final user = _auth.user;
    if (user == null) return Stream.value(const []);
    return _col(user.uid)
        .orderBy('sentAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => AppNotification.fromJson({...doc.data(), 'id': doc.id}))
            .toList());
  }

  Stream<int> unreadCount() {
    final user = _auth.user;
    if (user == null) return Stream.value(0);
    return _col(user.uid).where('read', isEqualTo: false).snapshots().map((snap) => snap.size);
  }

  /// Records a notification the client drew itself.
  ///
  /// Cloud Functions record the ones they send, but notifications raised on the
  /// device — parking outcomes, and the parking service's own pushes, which
  /// bypass our backend entirely — would otherwise never reach this inbox.
  /// Best-effort: an inbox write must never break the notification itself, and
  /// this also runs in background isolates.
  Future<void> record({
    required String title,
    required String body,
    String? type,
    Map<String, dynamic> data = const {},
  }) async {
    try {
      final user = _auth.user;
      if (user == null) return;
      await _col(user.uid).add({
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'sentAt': DateTime.now().millisecondsSinceEpoch,
        'read': false,
      });
    } catch (e) {
      // Swallowed deliberately; the user still gets the notification.
      // ignore: avoid_print
      print('NotificationService.record failed: $e');
    }
  }

  Future<void> markRead(String id) => _col(_auth.user!.uid).doc(id).update({'read': true});

  Future<void> markAllRead() async {
    final uid = _auth.user!.uid;
    final snap = await _col(uid).where('read', isEqualTo: false).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _col(_auth.user!.uid).doc(id).delete();

  /// How often the goal reminders (see functions/src/index.ts
  /// `goalReminder5pm` / `goalReminder9pm`) should arrive.
  ///
  /// The preference lives on the user doc rather than on the device because the
  /// sender is a scheduled Cloud Function, which can only see Firestore. Absent
  /// means [GoalReminderSchedule.both]: that is what every existing user already
  /// receives, and a read that fails or races the first write must not silently
  /// mute them.
  Stream<GoalReminderSchedule> watchGoalReminders(String userId) {
    return _userDoc(userId)
        .snapshots()
        .map((snap) => GoalReminderSchedule.fromWire(snap.data()?['goalReminderSchedule']));
  }

  Future<void> setGoalReminders(String userId, GoalReminderSchedule schedule) {
    // Merged, not updated: the user doc predates this field, and `update` on a
    // doc that somehow doesn't exist yet would throw.
    return _userDoc(userId).set({'goalReminderSchedule': schedule.wire}, SetOptions(merge: true));
  }

  Future<void> clearAll() async {
    final uid = _auth.user!.uid;
    final snap = await _col(uid).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}

/// Which of the two daily goal reminders a user wants.
///
/// The two nudges are separate scheduled functions, so muting just the late one
/// is a real option — and the common complaint is volume, not the feature.
enum GoalReminderSchedule {
  off('off'),
  eveningOnly('5pm'),
  both('both');

  const GoalReminderSchedule(this.wire);

  /// Stored on the user doc, and read by the Cloud Functions that send these —
  /// so the string, not the enum index, is the contract. Never renumber these.
  final String wire;

  /// Anything unrecognised — absent, null, or a value written by a newer build
  /// — falls back to [both], the behaviour from before the setting existed.
  static GoalReminderSchedule fromWire(Object? raw) {
    return GoalReminderSchedule.values.firstWhere(
      (v) => v.wire == raw,
      orElse: () => GoalReminderSchedule.both,
    );
  }
}
