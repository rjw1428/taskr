import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskr/shared/constants.dart';
import 'package:taskr/shared/design/tokens.dart';

void main() {
  group('AppTokens', () {
    test('of() falls back to the info palette for an unknown effort', () {
      const tokens = AppTokens(
        brightness: Brightness.light,
        priority: {Effort.info: PriorityColor(fill: Colors.white, border: Colors.black, ink: Colors.black, accent: Colors.red)},
        surfaceRaised: Colors.white,
        hairline: Colors.black,
        textMuted: Colors.grey,
        textFaint: Colors.grey,
        goal: Colors.amber,
      );
      expect(tokens.of(Effort.high), same(tokens.priority[Effort.info]));
      expect(AppTokens.light.of(Effort.high), same(AppTokens.light.priority[Effort.high]));
    });

    test('raisedShadow is tuned per brightness', () {
      expect(AppTokens.dark.raisedShadow, Shadows.raised(Brightness.dark));
      expect(AppTokens.light.raisedShadow, Shadows.raised(Brightness.light));
      expect(AppTokens.dark.raisedShadow, isNot(equals(AppTokens.light.raisedShadow)));
      // Dark surfaces need a heavier shadow to read as raised at all.
      final darkAlpha = Shadows.raised(Brightness.dark).map((s) => s.color.a).reduce((a, b) => a + b);
      final lightAlpha = Shadows.raised(Brightness.light).map((s) => s.color.a).reduce((a, b) => a + b);
      expect(darkAlpha, greaterThan(lightAlpha));
    });

    test('copyWith overrides only what is given', () {
      final t = AppTokens.light.copyWith(goal: Colors.purple);
      expect(t.goal, Colors.purple);
      expect(t.hairline, AppTokens.light.hairline);
      expect(t.brightness, Brightness.light);
      final same = AppTokens.dark.copyWith();
      expect(same.textMuted, AppTokens.dark.textMuted);
      expect(same.priority, AppTokens.dark.priority);
    });

    test('lerp blends between light and dark and ignores foreign extensions', () {
      final mid = AppTokens.light.lerp(AppTokens.dark, 0.5);
      expect(mid.brightness, Brightness.dark);
      expect(AppTokens.light.lerp(AppTokens.dark, 0.25).brightness, Brightness.light);
      expect(mid.goal, Color.lerp(Brand.lGoal, Brand.dGoal, 0.5));
      expect(mid.of(Effort.high).fill,
          Color.lerp(AppTokens.light.of(Effort.high).fill, AppTokens.dark.of(Effort.high).fill, 0.5));
      expect(AppTokens.light.lerp(null, 0.5), same(AppTokens.light));
      // Direction matters: t=0 is this, t=1 is other, for every blended field.
      final start = AppTokens.light.lerp(AppTokens.dark, 0);
      final end = AppTokens.light.lerp(AppTokens.dark, 1);
      expect(start.goal, AppTokens.light.goal);
      expect(end.goal, AppTokens.dark.goal);
      expect(start.textMuted, AppTokens.light.textMuted);
      expect(end.textMuted, AppTokens.dark.textMuted);
      expect(start.of(Effort.low).ink, AppTokens.light.of(Effort.low).ink);
      expect(end.of(Effort.low).ink, AppTokens.dark.of(Effort.low).ink);
    });

    test('PriorityColor.lerp blends every channel', () {
      final a = AppTokens.light.of(Effort.low);
      final b = AppTokens.dark.of(Effort.low);
      final c = PriorityColor.lerp(a, b, 1);
      expect(c.fill, b.fill);
      expect(c.border, b.border);
      expect(c.ink, b.ink);
      expect(c.accent, b.accent);
    });

    test('the ThemeData extension falls back to dark tokens', () {
      expect(ThemeData().appTokens, same(AppTokens.dark));
      expect(ThemeData(extensions: const [AppTokens.light]).appTokens, same(AppTokens.light));
    });

    test('scales and radii are exposed', () {
      expect(Insets.xs < Insets.sm && Insets.sm < Insets.md && Insets.lg < Insets.xl && Insets.xl < Insets.xxl, isTrue);
      expect(Corners.rSm, const Radius.circular(Corners.sm));
      expect(Corners.rMd, const Radius.circular(Corners.md));
      expect(Corners.rLg, const Radius.circular(Corners.lg));
      expect(Motion.fast < Motion.base && Motion.base < Motion.slow, isTrue);
      expect(Motion.springy, Curves.easeOutBack);
    });
  });
}
