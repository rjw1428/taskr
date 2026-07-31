import 'package:flutter/material.dart';
import 'package:taskr/shared/shared.dart';

/// Maps an accomplishment difficulty score (1–10) to a color on a
/// green → amber → red gradient, reusing the priority-palette accents so it
/// reads consistently with the rest of the app in both themes.
Color accomplishmentScoreColor(ThemeData theme, int score) {
  final t = theme.appTokens;
  final low = t.of(Effort.low).accent; // green
  final mid = t.of(Effort.medium).accent; // amber
  final high = t.of(Effort.high).accent; // red
  final s = (score.clamp(1, 10) - 1) / 9.0; // 0..1
  return s <= 0.5 ? Color.lerp(low, mid, s * 2)! : Color.lerp(mid, high, (s - 0.5) * 2)!;
}
