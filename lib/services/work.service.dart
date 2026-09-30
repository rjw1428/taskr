import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:taskr/services/firebase_refs.dart';
import 'package:taskr/services/models.dart';
import 'package:taskr/work/work_logic.dart';

/// Persistence for the Work board. Touches only `todos/{uid}/work` and
/// `todos/{uid}/workArchive`; it deliberately has no dependency on the
/// performance or accomplishment services so work can never leak into either.
class WorkService {
  static const activeCollection = 'work';
  static const archiveCollection = 'workArchive';

  // `late` so a test can inject fakes before the real instances are touched.
  late FirebaseFirestore _firestore = FirebaseRefs.firestore;
  late FirebaseAuth _auth = FirebaseRefs.auth;

  /// Clock, overridable so tests can pin timestamps.
  int Function() now = () => DateTime.now().millisecondsSinceEpoch;

  @visibleForTesting
  set db(FirebaseFirestore db) => _firestore = db;

  @visibleForTesting
  set auth(FirebaseAuth auth) => _auth = auth;

  String get _userId => _auth.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _active =>
      _firestore.collection('todos').doc(_userId).collection(activeCollection);

  CollectionReference<Map<String, dynamic>> get _archive =>
      _firestore.collection('todos').doc(_userId).collection(archiveCollection);

  /// A fresh client-side id for embedded next actions and updates.
  String newId() => _active.doc().id;

  static WorkItem _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data() ?? const {});
    data['id'] = doc.id;
    return WorkItem.fromJson(data);
  }

  Stream<List<WorkItem>> streamActive() =>
      _active.orderBy('position').snapshots().map((s) => s.docs.map(_fromDoc).toList());

  Stream<List<WorkItem>> streamArchived() => _archive
      .orderBy('archivedAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map(_fromDoc).toList());

  Future<WorkItem?> getActive(String id) async {
    final doc = await _active.doc(id).get();
    return doc.exists ? _fromDoc(doc) : null;
  }

  Future<WorkItem?> getArchived(String id) async {
    final doc = await _archive.doc(id).get();
    return doc.exists ? _fromDoc(doc) : null;
  }

  Stream<WorkItem?> streamOne(String id, {required bool archived}) =>
      (archived ? _archive : _active).doc(id).snapshots().map((d) => d.exists ? _fromDoc(d) : null);

  /// Creates an item at the bottom of the board and returns its id.
  Future<String> add(WorkItem item) async {
    final t = now();
    final count = (await _active.get()).size;
    final data = item.copyWith(position: count, createdAt: t, lastUpdated: t, archivedAt: null, restoredAt: null).toJson();
    final ref = await _active.add(data);
    return ref.id;
  }

  /// Edits title and notes only; next actions, updates, and position are
  /// owned by their own operations so a stale form can never clobber them.
  Future<void> updateDetails(String id, {required String title, required String notes}) =>
      _active.doc(id).update({'title': title, 'notes': notes, 'lastUpdated': now()});

  Future<void> setNextActions(String id, List<NextAction> actions) => _active.doc(id).update({
        'nextActions': actions.map((a) => a.toJson()).toList(),
        'lastUpdated': now(),
      });

  Future<void> addUpdate(String id, String text) async {
    final item = await getActive(id);
    if (item == null) return;
    final updates = WorkLogic.appendUpdate(item.updates, WorkUpdate(id: newId(), text: text, createdAt: now()));
    await _active.doc(id).update({'updates': updates.map((u) => u.toJson()).toList(), 'lastUpdated': now()});
  }

  /// Rewrites `position` for every listed item in one batch, touching no other
  /// field so a concurrent edit elsewhere survives.
  Future<void> reorder(List<String> orderedIds) async {
    final batch = _firestore.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_active.doc(orderedIds[i]), {'position': i});
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _active.doc(id).delete();

  Future<void> deleteArchived(String id) => _archive.doc(id).delete();

  /// Moves an item to the archive atomically, stamping `archivedAt`.
  Future<void> archive(String id) async {
    final doc = await _active.doc(id).get();
    if (!doc.exists) return;
    final data = Map<String, dynamic>.from(doc.data()!);
    data['archivedAt'] = now();
    final batch = _firestore.batch();
    batch.set(_archive.doc(id), data);
    batch.delete(_active.doc(id));
    await batch.commit();
  }

  /// Moves an archived item back to the bottom of the board atomically.
  Future<void> restore(String id) async {
    final doc = await _archive.doc(id).get();
    if (!doc.exists) return;
    final count = (await _active.get()).size;
    final data = Map<String, dynamic>.from(doc.data()!);
    data['archivedAt'] = null;
    data['restoredAt'] = now();
    data['position'] = count;
    data['lastUpdated'] = now();
    final batch = _firestore.batch();
    batch.set(_active.doc(id), data);
    batch.delete(_archive.doc(id));
    await batch.commit();
  }
}
