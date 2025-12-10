import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/models.dart';

class TagProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  List<Tag> _tags = [];
  List<Tag> get tags => _tags;

  late StreamSubscription<List<Tag>> _tagsSubscription;

  TagProvider() {
    _auth.userStream.listen((user) {
      if (user != null) {
        _tagsSubscription = _streamTags(user.uid).listen((tags) {
          _tags = tags;
          notifyListeners();
        });
      } else {
        _tags = [];
        _tagsSubscription.cancel();
        notifyListeners();
      }
    });
  }

  CollectionReference<Map<String, dynamic>> _tagCollection(String userId) {
    return _db.collection('todos').doc(userId).collection('tags');
  }

  Stream<List<Tag>> _streamTags(String userId) {
    return _tagCollection(userId)
        .where('deleted', isEqualTo: false)
        .orderBy("label")
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Tag.fromJson({'id': doc.id, ...doc.data()}))
            .where((tag) => tag.label != "Other")
            .toList());
  }

  Future<void> addTag(String label) async {
    var user = _auth.user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    await _tagCollection(user.uid)
        .add({'label': label, 'deleted': false, 'archived': false});
  }

  Future<void> deleteTag(String id) async {
    var user = _auth.user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    await _tagCollection(user.uid).doc(id).update({'deleted': true});
  }

  Future<void> updateTag(String id, String label) async {
    var user = _auth.user;
    if (user == null) {
      throw "No user logged in when adding task";
    }
    await _tagCollection(user.uid).doc(id).update({'label': label});
  }

  @override
  void dispose() {
    _tagsSubscription.cancel();
    super.dispose();
  }
}
