import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/login/login.dart';
import 'package:taskr/services/auth.service.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create(signedIn: false));
  tearDown(() => env.dispose());

  testWidgets('signs in with Google and provisions the user doc', (tester) async {
    await pumpApp(tester, const LoginScreen());
    expect(find.text('Login'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(env.auth.currentUser, isNull);

    await tester.tap(find.text('Login with Google'));
    await settle(tester);

    expect(env.google.log, ['signIn:login']);
    expect(env.auth.currentUser?.uid, env.uid);
    expect((await env.userDoc())?['currentScore'], 0);
  });

  testWidgets('a cancelled picker leaves the user signed out', (tester) async {
    env.google.interactive[GoogleSignInProfile.login] = null;
    await pumpApp(tester, const LoginScreen());
    await tester.tap(find.text('Login with Google'));
    await settle(tester);
    expect(env.auth.currentUser, isNull);
  });

  testWidgets('LoginButton calls its login method', (tester) async {
    var calls = 0;
    await pumpApp(
      tester,
      LoginButton(text: 'Go', icon: Icons.login, color: Colors.red, loginMethod: () => calls++),
      wrapInScaffold: true,
    );
    await tester.tap(find.text('Go'));
    expect(calls, 1);
  });
}
