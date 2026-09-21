import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/design/motion.dart';
import 'package:taskr/shared/design/tokens.dart';

void main() {
  group('reduceMotion', () {
    testWidgets('is false without a MediaQuery', (tester) async {
      late bool result;
      await tester.pumpWidget(Builder(builder: (context) {
        result = reduceMotion(context);
        return const SizedBox();
      }));
      expect(result, isFalse);
    });

    testWidgets('honours disableAnimations and accessibleNavigation', (tester) async {
      Future<bool> probe(MediaQueryData data) async {
        late bool result;
        await tester.pumpWidget(MediaQuery(
          data: data,
          child: Builder(builder: (context) {
            result = reduceMotion(context);
            return const SizedBox();
          }),
        ));
        return result;
      }

      expect(await probe(const MediaQueryData()), isFalse);
      expect(await probe(const MediaQueryData(disableAnimations: true)), isTrue);
      expect(await probe(const MediaQueryData(accessibleNavigation: true)), isTrue);
    });
  });

  group('AppReveal', () {
    testWidgets('animates its child into place', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppReveal(child: Text('hi'))));
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0);
      await tester.pump(Motion.slow);
      await tester.pump();
      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
      expect(find.text('hi'), findsOneWidget);
    });

    testWidgets('renders instantly under reduced motion', (tester) async {
      await tester.pumpWidget(const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(textDirection: TextDirection.ltr, child: AppReveal(child: Text('hi'))),
      ));
      expect(find.byType(Opacity), findsNothing);
      expect(find.text('hi'), findsOneWidget);
    });
  });

  test('staggerDelay grows with the index and is capped', () {
    expect(staggerDelay(0), Duration.zero);
    expect(staggerDelay(4), Motion.fast * 0.5);
    expect(staggerDelay(8), Motion.fast);
    expect(staggerDelay(50), Motion.fast);
  });

  group('fadeThroughRoute', () {
    testWidgets('pushes with a fade and carries settings', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, home: const Scaffold(body: Text('home'))));
      final route = fadeThroughRoute<void>((_) => const Text('next'), settings: const RouteSettings(name: '/next'));
      expect(route.settings.name, '/next');
      key.currentState!.push(route);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.ancestor(of: find.text('next'), matching: find.byType(FadeTransition)), findsWidgets);
      await tester.pump(Motion.base);
      expect(find.text('next'), findsOneWidget);
      key.currentState!.pop();
      await tester.pump();
      await tester.pump(Motion.fast);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('is an instant push under reduced motion', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(navigatorKey: key, home: const Scaffold(body: Text('home'))),
      ));
      key.currentState!.push(fadeThroughRoute<void>((_) => const Text('next')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('next'), findsOneWidget);
      expect(find.ancestor(of: find.text('next'), matching: find.byType(FadeTransition)), findsNothing);
    });
  });
}
