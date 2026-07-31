import 'package:flutter/material.dart';
import 'package:taskr/shared/constants.dart';

/// Design tokens for the "Quiet Depth" redesign.
///
/// This file is the single source of truth for spacing, radius, elevation,
/// motion, the neutral/accent ramps, and the color-coded priority palettes.
/// App-specific tokens (priority palettes, motion) are exposed to widgets via
/// the [AppTokens] theme extension so they adapt automatically to light/dark.

// ─────────────────────────────────────────────────────────────────────────
// Spacing — a 4pt scale. Prefer these over magic numbers.
// ─────────────────────────────────────────────────────────────────────────
abstract class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

// ─────────────────────────────────────────────────────────────────────────
// Corner radius
// ─────────────────────────────────────────────────────────────────────────
abstract class Corners {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 30;

  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius rLg = Radius.circular(lg);
}

// ─────────────────────────────────────────────────────────────────────────
// Elevation — soft, layered shadows tuned per brightness.
// ─────────────────────────────────────────────────────────────────────────
abstract class Shadows {
  static List<BoxShadow> raised(Brightness b) => b == Brightness.dark
      ? const [
          BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 1),
          BoxShadow(color: Color(0x73000000), offset: Offset(0, 10), blurRadius: 30, spreadRadius: -6),
        ]
      : const [
          BoxShadow(color: Color(0x0F141C28), offset: Offset(0, 1), blurRadius: 2),
          BoxShadow(color: Color(0x1A141C28), offset: Offset(0, 8), blurRadius: 24, spreadRadius: -8),
        ];
}

// ─────────────────────────────────────────────────────────────────────────
// Motion — named durations and curves. All animation reads from here.
// ─────────────────────────────────────────────────────────────────────────
abstract class Motion {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 480);

  /// Entrance/settle curve — decelerates into place.
  static const Curve enter = Cubic(0.22, 0.61, 0.36, 1);
  /// Standard emphasized curve for transitions.
  static const Curve standard = Curves.easeInOutCubicEmphasized;
  /// Spring-ish overshoot for playful micro-interactions.
  static const Curve springy = Curves.easeOutBack;
}

// ─────────────────────────────────────────────────────────────────────────
// Priority palette — one entry per [Effort]. Retuned from the original
// maroon/mustard/forest so the mapping (high→red, medium→amber, low→green,
// info→neutral) is preserved but the shades are clean and brightness-aware.
// ─────────────────────────────────────────────────────────────────────────
@immutable
class PriorityColor {
  /// Card background fill.
  final Color fill;
  /// Hairline border around the card.
  final Color border;
  /// Text/icon color that meets contrast against [fill].
  final Color ink;
  /// Saturated accent for the severity keyline and checkbox.
  final Color accent;

  const PriorityColor({
    required this.fill,
    required this.border,
    required this.ink,
    required this.accent,
  });

  static PriorityColor lerp(PriorityColor a, PriorityColor b, double t) => PriorityColor(
        fill: Color.lerp(a.fill, b.fill, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// Brand ramps
// ─────────────────────────────────────────────────────────────────────────
abstract class Brand {
  // Accent (one calm teal). Kept distinct from the semantic priority hues.
  static const Color accentDark = Color(0xFF58C4B4);
  static const Color accentDarkInk = Color(0xFF08201D);
  static const Color accentLight = Color(0xFF0E8C7E);
  static const Color accentLightInk = Color(0xFFFFFFFF);

  // Dark neutral ramp (layered charcoal, slight blue bias).
  static const Color dGround = Color(0xFF0D1015);
  static const Color dGround2 = Color(0xFF12151A);
  static const Color dSurface = Color(0xFF1A1F27);
  static const Color dSurface2 = Color(0xFF222833);
  static const Color dText = Color(0xFFE9ECF1);
  static const Color dMuted = Color(0xFF98A2B0);
  static const Color dFaint = Color(0xFF6B7482);
  static const Color dHairline = Color(0x14FFFFFF);
  static const Color dOutline = Color(0x24FFFFFF);
  static const Color dGoal = Color(0xFFD8B15A);

  // Light neutral ramp (cool paper, not cream).
  static const Color lGround = Color(0xFFE7EBF0);
  static const Color lSurface = Color(0xFFFFFFFF);
  static const Color lSurface2 = Color(0xFFF5F7FA);
  static const Color lText = Color(0xFF171C24);
  static const Color lMuted = Color(0xFF5C6672);
  static const Color lFaint = Color(0xFF8C95A2);
  static const Color lHairline = Color(0x1A141C28);
  static const Color lOutline = Color(0x29141C28);
  static const Color lGoal = Color(0xFFA9822E);
}

const Map<Effort, PriorityColor> _priorityDark = {
  Effort.high: PriorityColor(
      fill: Color(0xFF45222A), border: Color(0x80C56A75), ink: Color(0xFFF4D6DA), accent: Color(0xFFD4737E)),
  Effort.medium: PriorityColor(
      fill: Color(0xFF3E351B), border: Color(0x80C9A346), ink: Color(0xFFF3E4BF), accent: Color(0xFFD6B052)),
  Effort.low: PriorityColor(
      fill: Color(0xFF1E3A2C), border: Color(0x804FA97F), ink: Color(0xFFCFEFDD), accent: Color(0xFF58BC8A)),
  Effort.info: PriorityColor(
      fill: Color(0xFF262C36), border: Color(0x4D8C95A2), ink: Color(0xFFC9D2DE), accent: Color(0xFF7C8593)),
};

const Map<Effort, PriorityColor> _priorityLight = {
  Effort.high: PriorityColor(
      fill: Color(0xFFFBE1E3), border: Color(0x80C04551), ink: Color(0xFF7A2530), accent: Color(0xFFC24551)),
  Effort.medium: PriorityColor(
      fill: Color(0xFFFBEECB), border: Color(0x80B98A1E), ink: Color(0xFF6E5411), accent: Color(0xFFC79A22)),
  Effort.low: PriorityColor(
      fill: Color(0xFFD9EFE1), border: Color(0x802E8A5E), ink: Color(0xFF1E5238), accent: Color(0xFF2E9A66)),
  Effort.info: PriorityColor(
      fill: Color(0xFFE9EDF2), border: Color(0x4D6B7583), ink: Color(0xFF3A4250), accent: Color(0xFF8C95A2)),
};

// ─────────────────────────────────────────────────────────────────────────
// AppTokens — theme extension carrying app-specific tokens that Material's
// ColorScheme has no slot for. Read via Theme.of(context).appTokens.
// ─────────────────────────────────────────────────────────────────────────
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  final Brightness brightness;
  final Map<Effort, PriorityColor> priority;

  /// Surface tiers for layered depth.
  final Color surfaceRaised;
  final Color hairline;

  /// Muted/faint text roles beyond the standard scheme.
  final Color textMuted;
  final Color textFaint;

  /// Semantic accent for goal-linked affordances (deliberately quiet gold).
  final Color goal;

  const AppTokens({
    required this.brightness,
    required this.priority,
    required this.surfaceRaised,
    required this.hairline,
    required this.textMuted,
    required this.textFaint,
    required this.goal,
  });

  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    priority: _priorityDark,
    surfaceRaised: Brand.dSurface2,
    hairline: Brand.dHairline,
    textMuted: Brand.dMuted,
    textFaint: Brand.dFaint,
    goal: Brand.dGoal,
  );

  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    priority: _priorityLight,
    surfaceRaised: Brand.lSurface2,
    hairline: Brand.lHairline,
    textMuted: Brand.lMuted,
    textFaint: Brand.lFaint,
    goal: Brand.lGoal,
  );

  PriorityColor of(Effort e) => priority[e] ?? priority[Effort.info]!;

  List<BoxShadow> get raisedShadow => Shadows.raised(brightness);

  @override
  AppTokens copyWith({
    Brightness? brightness,
    Map<Effort, PriorityColor>? priority,
    Color? surfaceRaised,
    Color? hairline,
    Color? textMuted,
    Color? textFaint,
    Color? goal,
  }) =>
      AppTokens(
        brightness: brightness ?? this.brightness,
        priority: priority ?? this.priority,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        hairline: hairline ?? this.hairline,
        textMuted: textMuted ?? this.textMuted,
        textFaint: textFaint ?? this.textFaint,
        goal: goal ?? this.goal,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      priority: {
        for (final e in Effort.values)
          e: PriorityColor.lerp(of(e), other.of(e), t),
      },
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      goal: Color.lerp(goal, other.goal, t)!,
    );
  }
}

/// Convenience access: `Theme.of(context).appTokens`.
extension AppTokensX on ThemeData {
  AppTokens get appTokens => extension<AppTokens>() ?? AppTokens.dark;
}
