// import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:rxdart/rxdart.dart';

final WEB_CLIENT_ID = dotenv.env['WEB_CLIENT_ID'];

class AuthService {
  AuthService._internal();
  static final _instance = AuthService._internal();
  final user = FirebaseAuth.instance.currentUser;
  final userStream = FirebaseAuth.instance.authStateChanges();

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

  Future<void> googleLogin() async {
    try {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('https://www.googleapis.com/auth/contacts.readonly');
      googleProvider.setCustomParameters({'login_hint': 'user@example.com'});
      await FirebaseAuth.instance.signInWithPopup(googleProvider);

      // final googleUser = await GoogleSignIn(clientId: WEB_CLIENT_ID).signIn();
      // if (googleUser == null) return;

      // final googleAuth = await googleUser.authentication;

      // final authCredentials = GoogleAuthProvider.credential(
      //     accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);

      // await FirebaseAuth.instance.signInWithCredential(authCredentials);
    } on FirebaseAuthException catch (e) {
      print('Unknown exception: $e');
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }
}
