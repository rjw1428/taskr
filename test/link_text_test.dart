import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/link_text.dart';

import 'helpers/harness.dart';

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() {
    LinkText.debugLauncher = null;
    env.dispose();
  });

  Finder richWith(String text) => find.byWidgetPredicate(
      (w) => w is Text && w.textSpan != null && w.textSpan!.toPlainText().contains(text));

  testWidgets('plain text renders as a normal Text with no spans', (tester) async {
    await pumpApp(tester, const LinkText('just words'), wrapInScaffold: true);
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'just words');
    expect(text.textSpan, isNull);
  });

  testWidgets('link span is tappable and invokes the launcher', (tester) async {
    Uri? opened;
    await pumpApp(
      tester,
      LinkText('see https://example.test/a for it', launcher: (u) async {
        opened = u;
        return true;
      }),
      wrapInScaffold: true,
    );
    final text = tester.widget<Text>(richWith('example.test'));
    final span = (text.textSpan as TextSpan).children!.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    expect(span.text, 'https://example.test/a');
    expect(span.style?.decoration, TextDecoration.underline);
    (span.recognizer as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(opened, Uri.parse('https://example.test/a'));
    expect(find.text('Could not open link'), findsNothing);
  });

  testWidgets('launcher failure shows a snackbar', (tester) async {
    await pumpApp(tester, LinkText('www.x.test', launcher: (_) async => false), wrapInScaffold: true);
    final text = tester.widget<Text>(richWith('www.x.test'));
    final span = (text.textSpan as TextSpan).children!.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    (span.recognizer as TapGestureRecognizer).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not open link'), findsOneWidget);
  });

  testWidgets('launcher exception is non-fatal and uses debugLauncher', (tester) async {
    LinkText.debugLauncher = (_) async => throw StateError('boom');
    await pumpApp(tester, const LinkText('https://y.test'), wrapInScaffold: true);
    final text = tester.widget<Text>(richWith('y.test'));
    final span = (text.textSpan as TextSpan).children!.whereType<TextSpan>().firstWhere((s) => s.recognizer != null);
    (span.recognizer as TapGestureRecognizer).onTap!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Could not open link'), findsOneWidget);
  });

  testWidgets('rebuild disposes and recreates recognizers', (tester) async {
    await pumpApp(tester, const LinkText('a https://one.test'), wrapInScaffold: true);
    await pumpApp(tester, const LinkText('b https://two.test'), wrapInScaffold: true);
    expect(richWith('two.test'), findsOneWidget);
  });

  testWidgets('linkStyleFor uses the accent color', (tester) async {
    late TextStyle s;
    await pumpApp(
      tester,
      Builder(builder: (c) {
        s = linkStyleFor(c, const TextStyle());
        return const SizedBox();
      }),
      wrapInScaffold: true,
    );
    expect(s.decoration, TextDecoration.underline);
    expect(s.color, isNotNull);
  });
}
