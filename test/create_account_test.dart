import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/login/create_account.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/auth.service.dart';
import 'package:taskr/services/firebase_refs.dart';

import 'helpers/harness.dart';

/// Rejects the credential exchange the way a network failure would.
class _FailingAuth extends MockFirebaseAuth {
  _FailingAuth(this.error);
  final Object error;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential? credential) => throw error;
}

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create(signedIn: false));
  tearDown(() => env.dispose());

  Future<void> pumpPage(WidgetTester tester) => pumpApp(tester, const CreateAccount());

  testWidgets('offers Google as the only way to sign up', (tester) async {
    await pumpPage(tester);
    expect(find.text('Create your taskr account'), findsOneWidget);
    expect(find.text('Sign up with Google'), findsOneWidget);
    expect(find.text('Already have an account? Log in'), findsOneWidget);
  });

  testWidgets('creates the account and provisions the user doc', (tester) async {
    await pumpPage(tester);
    expect(env.auth.currentUser, isNull);

    await tester.tap(find.text('Sign up with Google'));
    await settle(tester);

    expect(env.google.log, ['signIn:login']);
    expect(env.auth.currentUser?.uid, env.uid);
    expect((await env.userDoc())?['currentScore'], 0);
    expect((await env.userDoc())?['email'], 'test@example.com');
  });

  testWidgets('tells a returning user they already had an account', (tester) async {
    // A user doc already on file is what makes this account pre-existing.
    await env.db.collection('todos').doc(env.uid).set({'currentScore': 42});
    // Pushed rather than mounted alone: the page pops itself on success, and a
    // snackbar needs a Scaffold left underneath to render into — in the app
    // that is whatever the auth gate swaps in.
    await pumpApp(tester, const LoginScreen(), routes: {createAccountRoute: (_) => const CreateAccount()});
    await tester.tap(find.text('New here? Create an account'));
    await settle(tester);

    await tester.tap(find.text('Sign up with Google'));
    await settle(tester);

    expect(find.text('You already had an account — signed you in.'), findsOneWidget);
    // The existing score survives: sign-up must not re-provision the doc.
    expect((await env.userDoc())?['currentScore'], 42);
  });

  testWidgets('a dismissed picker leaves the page usable, with no error', (tester) async {
    env.google.interactive[GoogleSignInProfile.login] = null;
    await pumpPage(tester);

    await tester.tap(find.text('Sign up with Google'));
    await settle(tester);

    expect(env.auth.currentUser, isNull);
    expect(find.text('Sign up with Google'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows the reason a failed sign-up failed', (tester) async {
    FirebaseRefs.override(auth: _FailingAuth(FirebaseAuthException(code: 'network-request-failed')));
    await pumpPage(tester);

    await tester.tap(find.text('Sign up with Google'));
    await settle(tester);

    expect(find.textContaining('network-request-failed'), findsOneWidget);
    // Still offered, so the user can retry once they are back online.
    expect(find.byType(LoginButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('the login screen links here', (tester) async {
    await pumpApp(
      tester,
      const LoginScreen(),
      routes: {createAccountRoute: (_) => const CreateAccount()},
    );

    await tester.tap(find.text('New here? Create an account'));
    await settle(tester);

    expect(find.byType(CreateAccount), findsOneWidget);
  });

  testWidgets('a signed-up user pops back to the auth gate underneath', (tester) async {
    await pumpApp(
      tester,
      const LoginScreen(),
      routes: {createAccountRoute: (_) => const CreateAccount()},
    );
    await tester.tap(find.text('New here? Create an account'));
    await settle(tester);

    await tester.tap(find.text('Sign up with Google'));
    await settle(tester);

    expect(find.byType(CreateAccount), findsNothing);
    expect(env.auth.currentUser?.uid, env.uid);
  });
}
