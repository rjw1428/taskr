import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/login/create_account.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/auth.service.dart';

import 'helpers/harness.dart';

/// A Google picker that stays open until the test closes it.
class _SlowGoogle extends FakeGoogleSignIn {
  final gate = Completer<void>();
  @override
  Future<GoogleAuthResult?> signIn(GoogleSignInProfile profile) async {
    log.add('signIn:${profile.name}');
    await gate.future;
    return interactive[profile];
  }
}

/// Firestore whose user-doc read fails, as with a rules rejection.
class _DeniedFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create(signedIn: false));
  tearDown(() => env.dispose());

  group('signUpWithGoogle outcomes', () {
    test('created for a first visit', () async {
      final r = await AuthService().signUpWithGoogle();
      expect(r.outcome, SignUpOutcome.created);
      expect(r.error, isNull);
    });
    test('alreadyExisted when the user doc is on file', () async {
      await env.db.collection('todos').doc(env.uid).set({'currentScore': 7});
      final r = await AuthService().signUpWithGoogle();
      expect(r.outcome, SignUpOutcome.alreadyExisted);
      expect((await env.userDoc())?['currentScore'], 7);
    });
    test('cancelled when the picker is dismissed', () async {
      env.google.interactive[GoogleSignInProfile.login] = null;
      final r = await AuthService().signUpWithGoogle();
      expect(r.outcome, SignUpOutcome.cancelled);
    });
    test('ensureUserDoc reports true only the first time', () async {
      await env.auth.signInWithCredential(null);
      AuthService().user = env.auth.currentUser;
      expect(await AuthService().ensureUserDoc(), isTrue);
      expect(await AuthService().ensureUserDoc(), isFalse);
    });
  });

  testWidgets('while the picker is open the button and back link are disabled', (tester) async {
    final slow = _SlowGoogle();
    GoogleSignInGateway.override = slow;
    await pumpApp(tester, const CreateAccount());

    await tester.tap(find.text('Sign up with Google'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // A second tap must not open a second picker.
    await tester.tap(find.text('Sign up with Google'), warnIfMissed: false);
    await tester.pump();
    expect(slow.log, ['signIn:login']);
    final back = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Already have an account? Log in'));
    expect(back.onPressed, isNull);

    slow.gate.complete();
    await settle(tester);
  });

  testWidgets('a Firestore failure after Google auth surfaces an error', (tester) async {
    await pumpApp(tester, const CreateAccount());
    AuthService().db = _DeniedFirestore();
    await tester.tap(find.text('Sign up with Google'));
    await settle(tester);
    expect(find.textContaining('permission-denied'), findsOneWidget);
    // Note: Firebase auth already succeeded, so the user is signed in here.
    expect(env.auth.currentUser, isNotNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('fits a 320x568 screen without overflow ($mode)', (tester) async {
      await pumpApp(tester, const CreateAccount(), size: const Size(320, 568), themeMode: mode);
      expect(tester.takeException(), isNull);
      expect(find.text('Sign up with Google'), findsOneWidget);
    });
  }

  testWidgets('the back link returns to the login screen', (tester) async {
    await pumpApp(tester, const LoginScreen(), routes: {createAccountRoute: (_) => const CreateAccount()});
    await tester.tap(find.text('New here? Create an account'));
    await settle(tester);
    await tester.tap(find.text('Already have an account? Log in'));
    await settle(tester);
    expect(find.byType(CreateAccount), findsNothing);
    expect(find.text('Login with Google'), findsOneWidget);
  });
}
