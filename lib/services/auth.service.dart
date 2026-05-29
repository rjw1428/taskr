import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rxdart/rxdart.dart';

// ignore: non_constant_identifier_names
final WEB_CLIENT_ID = dotenv.env['WEB_CLIENT_ID'];
// ignore: non_constant_identifier_names
final CALENDAR_WEB_CLIENT_ID = dotenv.env['CALENDAR_WEB_CLIENT_ID'];

const _calendarScope = 'https://www.googleapis.com/auth/calendar';

class AuthService {
  AuthService._internal();
  static final _instance = AuthService._internal();
  final userStream = FirebaseAuth.instance.authStateChanges().shareReplay(maxSize: 1);
  User? user = FirebaseAuth.instance.currentUser;

  GoogleSignIn? _calendarSignIn;
  GoogleSignIn _getCalendarSignIn() {
    return _calendarSignIn ??= GoogleSignIn(
      serverClientId: CALENDAR_WEB_CLIENT_ID,
      scopes: [_calendarScope],
    );
  }

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
    try {
      if (kIsWeb) {
        final googleProvider = GoogleAuthProvider();
        googleProvider.addScope('https://www.googleapis.com/auth/contacts.readonly');
        googleProvider.setCustomParameters({'login_hint': 'user@example.com'});
        await FirebaseAuth.instance.signInWithPopup(googleProvider);
      } else {
        final googleUser = await GoogleSignIn(serverClientId: WEB_CLIENT_ID).signIn();
        if (googleUser == null) return;
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
      user = FirebaseAuth.instance.currentUser;
    } catch (e) {
      debugPrint('Google sign-in error: $e');
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

  Future<CalendarConsent?> requestCalendarConsent() async {
    if (kIsWeb) {
      throw UnsupportedError('Calendar connection is not supported on web yet');
    }
    final signIn = _getCalendarSignIn();
    final account = await signIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    final serverAuthCode = account.serverAuthCode;
    if (serverAuthCode == null || auth.accessToken == null) {
      throw Exception('Google did not return a server auth code; check OAuth client configuration');
    }
    return CalendarConsent(
      accessToken: auth.accessToken!,
      serverAuthCode: serverAuthCode,
      email: account.email,
    );
  }

  Future<String?> getCalendarAccessToken({bool silent = true}) async {
    if (kIsWeb) return null;
    final signIn = _getCalendarSignIn();
    GoogleSignInAccount? account = silent ? await signIn.signInSilently() : await signIn.signIn();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.accessToken;
  }

  Future<void> revokeCalendarConsent() async {
    if (kIsWeb) return;
    final signIn = _getCalendarSignIn();
    try {
      await signIn.disconnect();
    } catch (_) {
      try {
        await signIn.signOut();
      } catch (_) {}
    }
  }
}

class CalendarConsent {
  final String accessToken;
  final String serverAuthCode;
  final String email;

  CalendarConsent({
    required this.accessToken,
    required this.serverAuthCode,
    required this.email,
  });
}
