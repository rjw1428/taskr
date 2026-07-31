import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/models.dart';

/// Reads the notification records written by Cloud Functions whenever an FCM
/// message is sent (see functions/src/index.ts `recordNotification`). Stored at
/// `todos/{uid}/notifications/{id}` — covered by the existing owner rule.
class NotificationService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

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
