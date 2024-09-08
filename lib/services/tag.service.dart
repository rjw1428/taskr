import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/services/auth.service.dart';
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

  Stream<Map<String, dynamic>> streamTags(String userId) {
    return tagCollection(userId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return {doc.id: data};
            }).reduce((acc, cur) => {...acc, ...cur}))
        .handleError((error) {
      print("TAG WARNING: $error");
      return {};
    }).shareReplay(maxSize: 1);
  }

  Stream<List<Tag>> streamTagsArray(String userId) {
    return tagCollection(userId)
        .where('deleted', isEqualTo: false)
        .orderBy("label")
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Tag.fromJson({'id': doc.id, ...doc.data()}))
            .where((tag) => tag.label != "Other")
            .toList())
        .handleError((error) => print(error))
        .shareReplay(maxSize: 1);
  }

  Future addTag(String label) {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    return tagCollection(user.uid).add({'label': label, 'deleted': false, 'archived': false});
  }

  Future deleteTag(String id) {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    return tagCollection(user.uid).doc(id).update({'deleted': true});
  }

  Future updateTag(String id, String label) {
    var user = AuthService().user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    return tagCollection(user.uid).doc(id).update({'label': label});
  }
}
