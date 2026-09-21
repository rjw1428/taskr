import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:rxdart/rxdart.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/services/firebase_refs.dart';

const _calendarScope = 'https://www.googleapis.com/auth/calendar';

/// Which Google OAuth client a sign-in goes through: the plain login client, or
/// the calendar client that also asks for calendar scope and a server code.
enum GoogleSignInProfile { login, calendar }

/// What a Google sign-in yields, independent of the plugin's own types so the
/// auth flows can be driven from a test.
class GoogleAuthResult {
  final String? accessToken;
  final String? idToken;
  final String? serverAuthCode;
  final String email;
  const GoogleAuthResult({this.accessToken, this.idToken, this.serverAuthCode, required this.email});
}

/// The Google sign-in plugin behind an interface. [instance] resolves to the
/// real plugin unless a test installs a fake.
abstract class GoogleSignInGateway {
  static GoogleSignInGateway? _override;
  static GoogleSignInGateway get instance => _override ?? _PluginGoogleSignIn.shared;

  @visibleForTesting
  static set override(GoogleSignInGateway? gateway) => _override = gateway;

  /// Interactive sign-in; null when the user dismissed the picker.
  Future<GoogleAuthResult?> signIn(GoogleSignInProfile profile);

  /// Reuses a previous session without UI; null when there is none.
  Future<GoogleAuthResult?> signInSilently(GoogleSignInProfile profile);

  Future<void> signOut(GoogleSignInProfile profile);
  Future<void> disconnect(GoogleSignInProfile profile);
}

class _PluginGoogleSignIn implements GoogleSignInGateway {
  _PluginGoogleSignIn._();
  static final shared = _PluginGoogleSignIn._();

  final Map<GoogleSignInProfile, GoogleSignIn> _clients = {};

  GoogleSignIn _client(GoogleSignInProfile profile) => _clients.putIfAbsent(profile, () {
        switch (profile) {
          case GoogleSignInProfile.login:
            return GoogleSignIn(serverClientId: dotenv.env['WEB_CLIENT_ID']);
          case GoogleSignInProfile.calendar:
            return GoogleSignIn(
              serverClientId: dotenv.env['CALENDAR_WEB_CLIENT_ID'],
              scopes: [_calendarScope],
            );
        }
      });

  Future<GoogleAuthResult?> _result(GoogleSignInAccount? account) async {
    if (account == null) return null;
    final auth = await account.authentication;
    return GoogleAuthResult(
      accessToken: auth.accessToken,
      idToken: auth.idToken,
      serverAuthCode: account.serverAuthCode,
      email: account.email,
    );
  }

  @override
  Future<GoogleAuthResult?> signIn(GoogleSignInProfile profile) async => _result(await _client(profile).signIn());

  @override
  Future<GoogleAuthResult?> signInSilently(GoogleSignInProfile profile) async =>
      _result(await _client(profile).signInSilently());

  @override
  Future<void> signOut(GoogleSignInProfile profile) => _client(profile).signOut();

  @override
  Future<void> disconnect(GoogleSignInProfile profile) => _client(profile).disconnect();
}

class AuthService {
  AuthService._internal();
  static AuthService _instance = AuthService._internal();

  /// Drops all state so the next `AuthService()` starts fresh.
  @visibleForTesting
  static void resetInstance() => _instance = AuthService._internal();
  // `late` so tests can inject fakes (via [user]/[db] setters) before these
  // initializers run — reading them otherwise touches real Firebase, which
  // isn't initialized under `flutter test`.
  late final userStream = FirebaseRefs.auth.authStateChanges().shareReplay(maxSize: 1);
  late User? user = FirebaseRefs.auth.currentUser;

  late FirebaseFirestore _db = FirebaseRefs.firestore;

  @visibleForTesting
  set db(FirebaseFirestore db) => _db = db;

  GoogleSignInGateway get _google => GoogleSignInGateway.instance;

  factory AuthService() {
    return _instance;
  }

  Future<void> anonLogin() async {
    try {
      await FirebaseRefs.auth.signInAnonymously();
    } on FirebaseAuthException {
      // handle error
    }
  }

  Future<void> createUser(String email, String password) async {
    try {
      await FirebaseRefs.auth.createUserWithEmailAndPassword(
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
        await FirebaseRefs.auth.signInWithPopup(googleProvider);
      } else {
        final googleUser = await _google.signIn(GoogleSignInProfile.login);
        if (googleUser == null) return;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleUser.accessToken,
          idToken: googleUser.idToken,
        );
        await FirebaseRefs.auth.signInWithCredential(credential);
      }
      user = FirebaseRefs.auth.currentUser;
      await ensureUserDoc();
    } catch (e) {
      debugPrint('Google sign-in error: $e');
    }
  }

  /// Whether the signed-in user is the app owner. Features backed by the
  /// owner's personal integrations (Garmin health sync, journaling) are
  /// gated to this account.
  bool get isOwner => user?.email == ownerEmail;

  /// Provision a first-time user's root document. New accounts have no
  /// `todos/{uid}` doc, which breaks score updates (`.update()` throws
  /// `not-found`) and FCM-token storage. Create it once, without touching an
  /// existing user's data.
  Future<void> ensureUserDoc() async {
    final uid = user?.uid;
    if (uid == null) return;
    final ref = _db.collection('todos').doc(uid);
    final snap = await ref.get();
    if (snap.exists) return;
    await ref.set({
      'currentScore': 0,
      'email': user?.email,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getUserProfile(userId) async {
    final docRef = _db.collection('todos').doc(userId);
    final doc = await docRef.get();
    return doc.data();
  }

  Future<void> updateFcmToken(String userId, String fcmToken) async {
    final userDoc = _db.collection('todos').doc(userId);
    await userDoc.update({'fcmToken': fcmToken});
    debugPrint('FCM token updated for user $userId');
  }

  Future<void> signOut() async {
    // Clear the cached Google session too, otherwise the next login silently
    // reuses the same account instead of showing the account picker.
    if (!kIsWeb) {
      try {
        await _google.disconnect(GoogleSignInProfile.login);
      } catch (_) {
        try {
          await _google.signOut(GoogleSignInProfile.login);
        } catch (_) {}
      }
    }
    await FirebaseRefs.auth.signOut();
  }

  Future<CalendarConsent?> requestCalendarConsent() async {
    if (kIsWeb) {
      throw UnsupportedError('Calendar connection is not supported on web yet');
    }
    final account = await _google.signIn(GoogleSignInProfile.calendar);
    if (account == null) return null;
    final serverAuthCode = account.serverAuthCode;
    if (serverAuthCode == null || account.accessToken == null) {
      throw Exception('Google did not return a server auth code; check OAuth client configuration');
    }
    return CalendarConsent(
      accessToken: account.accessToken!,
      serverAuthCode: serverAuthCode,
      email: account.email,
    );
  }

  Future<String?> getCalendarAccessToken({bool silent = true}) async {
    if (kIsWeb) return null;
    final account = silent
        ? await _google.signInSilently(GoogleSignInProfile.calendar)
        : await _google.signIn(GoogleSignInProfile.calendar);
    return account?.accessToken;
  }

  Future<void> revokeCalendarConsent() async {
    if (kIsWeb) return;
    try {
      await _google.disconnect(GoogleSignInProfile.calendar);
    } catch (_) {
      try {
        await _google.signOut(GoogleSignInProfile.calendar);
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
