import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/services/models.dart';

class TagService {
  TagService._internal();

  final _db = FirebaseFirestore.instance;
  static final TagService _instance = TagService._internal();

  factory TagService() {
    return _instance;
  }

  CollectionReference<Map<String, dynamic>> tagCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('tags');
  }

  Stream<Map<String, Tag>> streamTags(String userId) {
    return tagCollection(userId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {doc.id: Tag.fromJson(doc.data())})
            .reduce((acc, cur) => {...acc, ...cur}))
        .handleError((error) {
      print("TAG WARNING: $error");
      return {};
    }).shareReplay(maxSize: 1);
  }

  Stream<List<Tag>> streamTagsArray(String userId) {
    return tagCollection(userId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Tag.fromJson({'id': doc.id, ...doc.data()})).toList())
        .handleError((error) => print(error))
        .shareReplay(maxSize: 1);
  }
}
