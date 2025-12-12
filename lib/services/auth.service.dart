// import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rxdart/rxdart.dart';

// ignore: non_constant_identifier_names
final WEB_CLIENT_ID = dotenv.env['WEB_CLIENT_ID'];

class AuthService {
  AuthService._internal();
  static final _instance = AuthService._internal();
  final userStream = FirebaseAuth.instance.authStateChanges().shareReplay(maxSize: 1);
  User? user = FirebaseAuth.instance.currentUser;
  factory AuthService() {
    return _instance;
  }

  Future<void> anonLogin() async {
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } on FirebaseAuthException {
      // handle error
    }
  }

  Future<void> createUser(String email, String password) async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      user = await userStream.first;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        debugPrint('The password provided is too weak.');
      } else if (e.code == 'email-already-in-use') {
        debugPrint('The account already exists for that email.');
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> googleLogin() async {
    if (bool.parse(dotenv.env['DEV_MODE'] ?? 'true')) {
      try {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('https://www.googleapis.com/auth/contacts.readonly');
        googleProvider.setCustomParameters({'login_hint': 'user@example.com'});
        await FirebaseAuth.instance.signInWithPopup(googleProvider);
        user = FirebaseAuth.instance.currentUser;
      } on FirebaseAuthException catch (e) {
        debugPrint('Unknown exception: $e');
      }
    } else {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: "rjw1428@gmail.com", password: "123456");
        user = await userStream.first;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          debugPrint('No user found for that email.');
        } else if (e.code == 'wrong-password') {
          debugPrint('Wrong password provided for that user.');
        }
      }
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(userId) async {
    final docRef = FirebaseFirestore.instance.collection('todos').doc(userId);
    final doc = await docRef.get();
    return doc.data();
  }

  Future<void> updateFcmToken(String userId, String fcmToken) async {
    final userDoc = FirebaseFirestore.instance.collection('todos').doc(userId);
    await userDoc.update({'fcmToken': fcmToken});
    debugPrint('FCM token updated for user $userId');
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }
}
