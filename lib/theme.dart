import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:taskr/shared/design/tokens.dart';

/// Light and dark themes for the "Quiet Depth" redesign, both built on
/// Material 3 from the design tokens. `main.dart` wires these with
/// `themeMode: ThemeMode.system` so the app follows the OS appearance.

// Display face carries titles and large figures; body face carries content.
TextTheme _textTheme(Color onSurface, Color muted) {
  TextStyle display(double size, {FontWeight w = FontWeight.w700, double ls = -0.5}) =>
      GoogleFonts.sora(fontSize: size, fontWeight: w, letterSpacing: ls, color: onSurface, height: 1.05);
  TextStyle body(double size, {Color? c, FontWeight w = FontWeight.w400, double h = 1.45}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: w, color: c ?? onSurface, height: h);

  return TextTheme(
    displaySmall: display(32, w: FontWeight.w800, ls: -1),
    headlineMedium: display(26, w: FontWeight.w800, ls: -0.8),
    headlineSmall: display(22, w: FontWeight.w700, ls: -0.5),
    titleLarge: display(19, w: FontWeight.w700, ls: -0.3),
    titleMedium: body(15.5, w: FontWeight.w600, h: 1.3),
    titleSmall: body(13.5, w: FontWeight.w600, h: 1.3),
    bodyLarge: body(15.5),
    bodyMedium: body(14),
    bodySmall: body(12.5, c: muted),
    labelLarge: body(14, w: FontWeight.w600),
    labelMedium: body(12, w: FontWeight.w600, c: muted),
    labelSmall: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w700, color: muted, letterSpacing: 0.8, height: 1.2),
  );
}

ThemeData _build({
  required Brightness brightness,
  required AppTokens tokens,
  required Color accent,
  required Color accentInk,
  required Color ground,
  required Color surface,
  required Color surfaceRaised,
  required Color onSurface,
  required Color muted,
  required Color outline,
  required Color hairline,
}) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    onPrimary: accentInk,
    secondary: accent,
    onSecondary: accentInk,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: muted,
    surfaceContainerLowest: ground,
    surfaceContainerLow: surface,
    surfaceContainer: surfaceRaised,
    surfaceContainerHigh: surfaceRaised,
    surfaceContainerHighest: surfaceRaised,
    outline: outline,
    outlineVariant: hairline,
  );
  final text = _textTheme(onSurface, muted);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: ground,
    canvasColor: ground,
    textTheme: text,
    extensions: [tokens],
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: ground,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.md)),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      side: BorderSide(color: muted, width: 2),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: accentInk,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.lg)),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: isDark ? surface : surface,
      selectedItemColor: accent,
      unselectedItemColor: tokens.textFaint,
      type: BottomNavigationBarType.fixed,
      showUnselectedLabels: true,
      elevation: 0,
      selectedLabelStyle: text.labelSmall?.copyWith(letterSpacing: 0.2),
      unselectedLabelStyle: text.labelSmall?.copyWith(letterSpacing: 0.2),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceRaised,
      contentTextStyle: text.bodyMedium,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.md)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.md),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Corners.md), borderSide: BorderSide(color: hairline)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Corners.md), borderSide: BorderSide(color: hairline)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Corners.md), borderSide: BorderSide(color: accent, width: 1.6)),
      labelStyle: text.bodyMedium?.copyWith(color: muted),
      hintStyle: text.bodyMedium?.copyWith(color: tokens.textFaint),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: surfaceRaised,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.md)),
      textStyle: text.bodyMedium,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surfaceRaised,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.lg)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Corners.xl))),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceRaised,
      side: BorderSide(color: hairline),
      labelStyle: text.labelMedium,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.sm)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: accentInk,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: Insets.xl, vertical: Insets.md),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Corners.md)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: accent, textStyle: text.labelLarge),
    ),
  );
}

final ThemeData lightTheme = _build(
  brightness: Brightness.light,
  tokens: AppTokens.light,
  accent: Brand.accentLight,
  accentInk: Brand.accentLightInk,
  ground: Brand.lGround,
  surface: Brand.lSurface,
  surfaceRaised: Brand.lSurface2,
  onSurface: Brand.lText,
  muted: Brand.lMuted,
  outline: Brand.lOutline,
  hairline: Brand.lHairline,
);

final ThemeData darkTheme = _build(
  brightness: Brightness.dark,
  tokens: AppTokens.dark,
  accent: Brand.accentDark,
  accentInk: Brand.accentDarkInk,
  ground: Brand.dGround,
  surface: Brand.dSurface,
  surfaceRaised: Brand.dSurface2,
  onSurface: Brand.dText,
  muted: Brand.dMuted,
  outline: Brand.dOutline,
  hairline: Brand.dHairline,
);

/// Deprecated alias kept so any lingering reference still resolves to a valid
/// theme; prefer [lightTheme] / [darkTheme].
final ThemeData appTheme = darkTheme;
