import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/models.dart';

class AccomplishmentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  Stream<List<Accomplishment>> getAccomplishments() {
    var user = _auth.user;
    if (user == null) {
      return Stream.value([]);
    }
    var ref = _db.collection('users').doc(user.uid).collection('accomplishments');
    return ref.snapshots().map((list) =>
        list.docs.map((doc) {
          var data = doc.data();
          data['id'] = doc.id;
          return Accomplishment.fromJson(data);
        }).toList());
  }

  Future<void> addAccomplishment(Accomplishment accomplishment) {
    var user = _auth.user;
    if (user == null) {
      throw Exception('User is not authenticated');
    }
    var ref = _db.collection('users').doc(user.uid).collection('accomplishments');
    return ref.add(accomplishment.toJson());
  }

  Future<void> updateAccomplishment(Accomplishment accomplishment) {
    var user = _auth.user;
    if (user == null) {
      throw Exception('User is not authenticated');
    }
    var ref = _db.collection('users').doc(user.uid).collection('accomplishments').doc(accomplishment.id);
    return ref.update(accomplishment.toJson());
  }

  Future<void> deleteAccomplishment(String accomplishmentId) {
    var user = _auth.user;
    if (user == null) {
      throw Exception('User is not authenticated');
    }
    var ref = _db.collection('users').doc(user.uid).collection('accomplishments').doc(accomplishmentId);
    return ref.delete();
  }
}
