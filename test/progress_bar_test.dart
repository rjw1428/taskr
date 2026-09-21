import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/progress_bar.dart';
import 'package:taskr/theme.dart';

Widget _wrap(Widget child) => MaterialApp(theme: lightTheme, home: Scaffold(body: SizedBox(width: 300, child: child)));

void main() {
  group('AnimatedProgressbar', () {
    testWidgets('fills to the given fraction of the width', (tester) async {
      await tester.pumpWidget(_wrap(const AnimatedProgressbar(value: 0.5)));
      await tester.pump(const Duration(seconds: 1));
      final fill = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(fill.constraints?.maxWidth, closeTo(150, 0.01));
    });

    testWidgets('clamps negative values to an empty bar', (tester) async {
      await tester.pumpWidget(_wrap(const AnimatedProgressbar(value: -0.3, height: 6)));
      await tester.pump(const Duration(seconds: 1));
      final fill = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
      expect(fill.constraints?.maxWidth, 0);
      expect(fill.constraints?.maxHeight, 6);
    });
  });

  group('DailyProgress', () {
    testWidgets('shows the count and the percent', (tester) async {
      await tester.pumpWidget(_wrap(const DailyProgress(numerator: 3, denominator: 4)));
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.byType(AnimatedProgressbar), findsOneWidget);
    });

    testWidgets('a zero denominator is 0%', (tester) async {
      await tester.pumpWidget(_wrap(const DailyProgress(numerator: 0, denominator: 0)));
      expect(find.text('0 of 0'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
    });
  });
}
