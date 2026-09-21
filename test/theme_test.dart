import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:taskr/shared/design/tokens.dart';
import 'package:taskr/theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('light theme is built from the light tokens', (tester) async {
    expect(lightTheme.brightness, Brightness.light);
    expect(lightTheme.useMaterial3, isTrue);
    expect(lightTheme.colorScheme.primary, Brand.accentLight);
    expect(lightTheme.colorScheme.onPrimary, Brand.accentLightInk);
    expect(lightTheme.scaffoldBackgroundColor, Brand.lGround);
    expect(lightTheme.appTokens, same(AppTokens.light));
    expect(lightTheme.textTheme.bodySmall?.color, Brand.lMuted);
    expect(lightTheme.textTheme.titleLarge?.fontSize, 19);
  });

  testWidgets('dark theme is built from the dark tokens', (tester) async {
    expect(darkTheme.brightness, Brightness.dark);
    expect(darkTheme.colorScheme.primary, Brand.accentDark);
    expect(darkTheme.colorScheme.surface, Brand.dSurface);
    expect(darkTheme.appTokens, same(AppTokens.dark));
    expect(darkTheme.bottomNavigationBarTheme.unselectedItemColor, Brand.dFaint);
    expect(darkTheme.appBarTheme.backgroundColor, Brand.dGround);
  });

  testWidgets('the deprecated alias resolves to the dark theme', (tester) async {
    expect(appTheme, same(darkTheme));
  });

  testWidgets('component themes apply to widgets', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: lightTheme,
      home: Scaffold(
        appBar: AppBar(title: const Text('t')),
        body: Column(children: [
          const Card(child: Text('c')),
          const TextField(decoration: InputDecoration(labelText: 'l', hintText: 'h')),
          FilledButton(onPressed: () {}, child: const Text('f')),
          TextButton(onPressed: () {}, child: const Text('tb')),
          const Chip(label: Text('chip')),
          Checkbox(value: true, onChanged: (_) {}),
        ]),
        floatingActionButton: FloatingActionButton(onPressed: () {}, child: const Icon(Icons.add)),
        bottomNavigationBar: BottomNavigationBar(items: const [
          BottomNavigationBarItem(icon: Icon(Icons.add), label: 'a'),
          BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'b'),
        ]),
      ),
    ));
    expect(find.text('t'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });
}
