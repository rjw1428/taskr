import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/shared.dart';

class JournalService {
  JournalService._internal();
  static final _instance = JournalService._internal();
  factory JournalService() => _instance;

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _journalCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('journal');
  }

  Future<JournalEntry?> getEntry(String date) async {
    final user = AuthService().user;
    if (user == null) return null;
    final doc = await _journalCollection(user.uid).doc(date).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    data['id'] = doc.id;
    return JournalEntry.fromJson(data);
  }

  Stream<JournalEntry?> streamEntry(String date) {
    final user = AuthService().user;
    if (user == null) return Stream.value(null);
    return _journalCollection(user.uid).doc(date).snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data()!;
      data['id'] = doc.id;
      return JournalEntry.fromJson(data);
    });
  }

  Future<void> saveEntry(JournalEntry entry) async {
    final user = AuthService().user;
    if (user == null) throw Exception('No user logged in');
    final data = removeNulls(entry.toJson());
    data.remove('id');
    await _journalCollection(user.uid).doc(entry.date).set(data);
  }
}
