import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/accomplishments/accomplishment_color.dart';
import 'package:taskr/shared/shared.dart';
import 'package:taskr/theme.dart';

import 'helpers/harness.dart';

/// Colour equality up to float rounding in the lerp fraction.
Matcher closeToColor(Color expected) => predicate<Color>(
      (c) =>
          (c.r - expected.r).abs() < 1e-6 &&
          (c.g - expected.g).abs() < 1e-6 &&
          (c.b - expected.b).abs() < 1e-6 &&
          (c.a - expected.a).abs() < 1e-6,
      'is close to $expected',
    );

void main() {
  late TestEnv env;
  setUp(() async => env = await TestEnv.create());
  tearDown(() => env.dispose());

  for (final name in ['light', 'dark']) {
    ThemeData themeFor() => name == 'light' ? lightTheme : darkTheme;

    testWidgets('[$name] score 1 is the low (green) accent and 10 is the high (red) accent', (tester) async {
      final theme = themeFor();
      final t = theme.appTokens;
      expect(accomplishmentScoreColor(theme, 1), t.of(Effort.low).accent);
      expect(accomplishmentScoreColor(theme, 10), t.of(Effort.high).accent);
    });

    testWidgets('[$name] scores either side of the midpoint lerp toward amber', (tester) async {
      final theme = themeFor();
      final t = theme.appTokens;
      final mid = t.of(Effort.medium).accent;
      // Score 5 sits at 8/9 of the way from green to amber; 6 at 1/9 from amber to red.
      expect(accomplishmentScoreColor(theme, 5), closeToColor(Color.lerp(t.of(Effort.low).accent, mid, 8 / 9)!));
      expect(accomplishmentScoreColor(theme, 6), closeToColor(Color.lerp(mid, t.of(Effort.high).accent, 1 / 9)!));
    });

    testWidgets('[$name] every score from 1 to 10 maps to a distinct colour', (tester) async {
      final theme = themeFor();
      final colours = <Color>{};
      for (var s = 1; s <= 10; s++) {
        colours.add(accomplishmentScoreColor(theme, s));
      }
      expect(colours.length, 10);
    });

    testWidgets('[$name] out-of-range scores clamp to the ends', (tester) async {
      final theme = themeFor();
      expect(accomplishmentScoreColor(theme, 0), accomplishmentScoreColor(theme, 1));
      expect(accomplishmentScoreColor(theme, -7), accomplishmentScoreColor(theme, 1));
      expect(accomplishmentScoreColor(theme, 11), accomplishmentScoreColor(theme, 10));
      expect(accomplishmentScoreColor(theme, 99), accomplishmentScoreColor(theme, 10));
    });
  }
}
