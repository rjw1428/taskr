import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/firebase_refs.dart';
import 'package:taskr/services/services.dart';
import 'package:taskr/shared/constants.dart';

import 'helpers/harness.dart';

/// A MockFirebaseAuth whose auth-state stream reports the current user on
/// every subscription, the way the real SDK does. The shared mock only pushes
/// changes as they happen, so a listener attached after sign-up sees nothing.
class _ReplayingAuth extends MockFirebaseAuth {
  @override
  Stream<User?> authStateChanges() => Stream<User?>.multi((c) => c.add(currentUser));
}

/// A MockFirebaseAuth whose sign-in and sign-up calls fail, for the catch paths.
class _FailingAuth extends MockFirebaseAuth {
  _FailingAuth(this.error);
  final Object error;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) => throw error;

  @override
  Future<UserCredential> createUserWithEmailAndPassword({required String email, required String password}) =>
      throw error;

  @override
  Future<UserCredential> signInAnonymously() => throw error;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;

  setUp(() async => env = await TestEnv.create(signedIn: false));
  tearDown(() => env.dispose());

  group('ensureUserDoc', () {
    setUp(() => AuthService().user = MockUser(uid: 'newbie', email: 'n@example.com'));

    test('provisions a new user with currentScore 0', () async {
      await AuthService().ensureUserDoc();
      final doc = await env.db.collection('todos').doc('newbie').get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['currentScore'], 0);
      expect(doc.data()!['email'], 'n@example.com');
    });

    test('never overwrites an existing user (no score reset)', () async {
      await env.db.collection('todos').doc('newbie').set({'currentScore': 42});
      await AuthService().ensureUserDoc();
      final doc = await env.db.collection('todos').doc('newbie').get();
      expect(doc.data()!['currentScore'], 42);
    });

    test('is a no-op with no signed-in user', () async {
      AuthService().user = null;
      await AuthService().ensureUserDoc();
      final snap = await env.db.collection('todos').get();
      expect(snap.docs, isEmpty);
    });
  });

  group('googleLogin', () {
    test('signs in with the Google credential and provisions the user doc', () async {
      await AuthService().googleLogin();
      expect(env.google.log, ['signIn:login']);
      expect(AuthService().user, isNotNull);
      expect(env.auth.currentUser, isNotNull);
      expect((await env.db.collection('todos').doc(env.auth.currentUser!.uid).get()).exists, isTrue);
    });

    test('a dismissed picker leaves the session signed out', () async {
      env.google.interactive[GoogleSignInProfile.login] = null;
      await AuthService().googleLogin();
      expect(env.auth.currentUser, isNull);
      expect(AuthService().user, isNull);
    });

    test('a failing credential exchange is swallowed', () async {
      FirebaseRefs.override(auth: _FailingAuth(FirebaseAuthException(code: 'network-request-failed')));
      await AuthService().googleLogin();
      expect(AuthService().user, isNull);
    });
  });

  group('createUser', () {
    test('creates the account and picks the user up from the auth stream', () async {
      FirebaseRefs.override(auth: _ReplayingAuth());
      await AuthService().createUser('new@example.com', 'hunter22');
      expect(AuthService().user?.email, 'new@example.com');
    });

    test('weak-password and email-already-in-use are reported quietly', () async {
      FirebaseRefs.override(auth: _FailingAuth(FirebaseAuthException(code: 'weak-password')));
      await AuthService().createUser('a@b.c', '1');
      FirebaseRefs.override(auth: _FailingAuth(FirebaseAuthException(code: 'email-already-in-use')));
      await AuthService().createUser('a@b.c', '1');
      FirebaseRefs.override(auth: _FailingAuth(FirebaseAuthException(code: 'other')));
      await AuthService().createUser('a@b.c', '1');
      FirebaseRefs.override(auth: _FailingAuth(StateError('boom')));
      await AuthService().createUser('a@b.c', '1');
      expect(AuthService().user, isNull);
    });
  });

  group('anonLogin', () {
    test('signs in anonymously', () async {
      // The shared mock carries a named user, which the anonymous path rejects.
      FirebaseRefs.override(auth: MockFirebaseAuth());
      await AuthService().anonLogin();
      expect(FirebaseRefs.auth.currentUser?.isAnonymous, isTrue);
    });

    test('an auth failure is swallowed', () async {
      FirebaseRefs.override(auth: _FailingAuth(FirebaseAuthException(code: 'operation-not-allowed')));
      await AuthService().anonLogin();
    });
  });

  test('user and userStream resolve lazily from the auth handle', () async {
    expect(AuthService().user, isNull);
    expect(AuthService().userStream, isNotNull);
  });

  group('production Google gateway', () {
    const channels = ['plugins.flutter.io/google_sign_in', 'plugins.flutter.io/google_sign_in_ios'];

    setUp(() {
      GoogleSignInGateway.override = null;
      for (final name in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(name), (call) async {
          switch (call.method) {
            case 'signIn':
            case 'signInSilently':
              return {'email': 'g@example.com', 'id': 'gid', 'displayName': 'G', 'serverAuthCode': 'srv'};
            case 'getTokens':
              return {'idToken': 'it', 'accessToken': 'at'};
            case 'disconnect':
              throw PlatformException(code: 'network_error');
            default:
              return null;
          }
        });
      }
    });
    tearDown(() {
      for (final name in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(name), null);
      }
    });

    test('drives the login and calendar clients through the plugin', () async {
      final consent = await AuthService().requestCalendarConsent();
      expect(consent!.serverAuthCode, 'srv');
      expect(consent.accessToken, 'at');
      expect(consent.email, 'g@example.com');
      expect(await AuthService().getCalendarAccessToken(), 'at');
      await AuthService().googleLogin();
      expect(AuthService().user, isNotNull);
      await AuthService().signOut();
      await AuthService().revokeCalendarConsent();
      expect(env.auth.currentUser, isNull);
    });
  });

  group('profile', () {
    test('getUserProfile reads the user doc and updateFcmToken writes to it', () async {
      await env.db.collection('todos').doc('p1').set({'email': 'p@example.com'});
      expect((await AuthService().getUserProfile('p1'))!['email'], 'p@example.com');
      await AuthService().updateFcmToken('p1', 'tok-1');
      expect((await AuthService().getUserProfile('p1'))!['fcmToken'], 'tok-1');
      expect(await AuthService().getUserProfile('nobody'), isNull);
    });

    test('isOwner matches the owner email only', () {
      AuthService().user = MockUser(uid: 'o', email: ownerEmail);
      expect(AuthService().isOwner, isTrue);
      AuthService().user = MockUser(uid: 'x', email: 'x@example.com');
      expect(AuthService().isOwner, isFalse);
      AuthService().user = null;
      expect(AuthService().isOwner, isFalse);
    });
  });

  group('signOut', () {
    test('disconnects Google and signs out of Firebase', () async {
      await AuthService().googleLogin();
      await AuthService().signOut();
      expect(env.google.log, contains('disconnect:login'));
      expect(env.google.log, isNot(contains('signOut:login')));
      expect(env.auth.currentUser, isNull);
    });

    test('falls back to a plain Google signOut when disconnect fails', () async {
      env.google.throwOnDisconnect = Exception('no network');
      await AuthService().signOut();
      expect(env.google.log, ['disconnect:login', 'signOut:login']);
    });

    test('still signs out of Firebase when both Google calls fail', () async {
      await AuthService().googleLogin();
      env.google.throwOnDisconnect = Exception('a');
      env.google.throwOnSignOut = Exception('b');
      await AuthService().signOut();
      expect(env.auth.currentUser, isNull);
    });
  });

  group('calendar consent', () {
    test('requestCalendarConsent returns the server auth code', () async {
      final consent = await AuthService().requestCalendarConsent();
      expect(consent!.serverAuthCode, 'code');
      expect(consent.accessToken, 'cal-at');
      expect(consent.email, 'test@example.com');
      expect(env.google.log, ['signIn:calendar']);
    });

    test('a dismissed picker yields null', () async {
      env.google.interactive[GoogleSignInProfile.calendar] = null;
      expect(await AuthService().requestCalendarConsent(), isNull);
    });

    test('a missing server auth code or access token is an error', () async {
      env.google.interactive[GoogleSignInProfile.calendar] =
          const GoogleAuthResult(accessToken: 'x', email: 'e');
      expect(() => AuthService().requestCalendarConsent(), throwsA(isA<Exception>()));
      env.google.interactive[GoogleSignInProfile.calendar] =
          const GoogleAuthResult(serverAuthCode: 'c', email: 'e');
      expect(() => AuthService().requestCalendarConsent(), throwsA(isA<Exception>()));
    });

    test('getCalendarAccessToken uses the silent or interactive session', () async {
      expect(await AuthService().getCalendarAccessToken(), isNull);
      env.google.silent[GoogleSignInProfile.calendar] = const GoogleAuthResult(accessToken: 's', email: 'e');
      expect(await AuthService().getCalendarAccessToken(), 's');
      expect(await AuthService().getCalendarAccessToken(silent: false), 'cal-at');
      expect(env.google.log, ['silent:calendar', 'silent:calendar', 'signIn:calendar']);
    });

    test('revokeCalendarConsent disconnects, falling back to signOut, and never throws', () async {
      await AuthService().revokeCalendarConsent();
      expect(env.google.log, ['disconnect:calendar']);

      env.google.log.clear();
      env.google.throwOnDisconnect = Exception('a');
      await AuthService().revokeCalendarConsent();
      expect(env.google.log, ['disconnect:calendar', 'signOut:calendar']);

      env.google.throwOnSignOut = Exception('b');
      await AuthService().revokeCalendarConsent();
    });
  });
}
