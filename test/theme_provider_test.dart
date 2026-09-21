import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/services/theme.provider.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('defaults to system and follows the stored preference', () async {
    await env.col('settings').doc('preferences').set({'themeMode': 'dark'});
    final provider = ThemeProvider();
    expect(provider.mode, ThemeMode.system);
    await flush();
    expect(provider.mode, ThemeMode.dark);
    provider.dispose();
  });

  test('an unknown stored value falls back to system', () async {
    await env.col('settings').doc('preferences').set({'themeMode': 'sepia'});
    final provider = ThemeProvider();
    await flush();
    expect(provider.mode, ThemeMode.system);
    provider.dispose();
  });

  test('setMode applies immediately, persists, and notifies once per change', () async {
    final provider = ThemeProvider();
    await flush();
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.setMode(ThemeMode.light);
    expect(provider.mode, ThemeMode.light);
    expect((await env.col('settings').doc('preferences').get()).data()?['themeMode'], 'light');
    await flush();
    await provider.setMode(ThemeMode.light);
    expect(notified, 1);
    provider.dispose();
  });

  test('reverts to system on sign out and re-reads on sign in', () async {
    await env.col('settings').doc('preferences').set({'themeMode': 'dark'});
    final provider = ThemeProvider();
    await flush();
    expect(provider.mode, ThemeMode.dark);

    await env.auth.signOut();
    await flush();
    expect(provider.mode, ThemeMode.system);

    // Choosing a mode while signed out is kept in memory but not written.
    await provider.setMode(ThemeMode.light);
    expect(provider.mode, ThemeMode.light);
    expect((await env.col('settings').doc('preferences').get()).data()?['themeMode'], 'dark');

    await env.auth.signInWithEmailAndPassword(email: 'test@example.com', password: 'x');
    await flush();
    await flush();
    expect(provider.mode, ThemeMode.dark);
    provider.dispose();
  });

  test('starts as system when signed out', () async {
    env.dispose();
    env = await TestEnv.create(signedIn: false);
    final provider = ThemeProvider();
    await flush();
    expect(provider.mode, ThemeMode.system);
    provider.dispose();
  });
}
