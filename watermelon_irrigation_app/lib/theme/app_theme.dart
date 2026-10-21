import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colors taken from the crop itself: rind greens for structure,
/// water blue only for "irrigation needed", flesh red only for errors.
class Palette {
  static const ink = Color(0xFF15261B);
  static const muted = Color(0xFF55675B);
  static const background = Color(0xFFEDF1E8);
  static const surface = Color(0xFFFFFFFF);
  static const line = Color(0xFFD3DCCC);

  static const rind = Color(0xFF1E5130);
  static const leaf = Color(0xFF3D7F3A);
  static const leafTint = Color(0xFFDCEBD3);

  static const water = Color(0xFF1667A8);
  static const waterTint = Color(0xFFDCEAF6);

  static const sun = Color(0xFF8A5E08);
  static const sunTint = Color(0xFFF6EBCF);

  static const flesh = Color(0xFFB8313D);
  static const fleshTint = Color(0xFFF7DEE0);

  static const stone = Color(0xFF5F6B63);
  static const stoneTint = Color(0xFFE4E8E2);
}

class AppTheme {
  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: Palette.rind,
      brightness: Brightness.light,
    ).copyWith(
      primary: Palette.rind,
      surface: Palette.surface,
      onSurface: Palette.ink,
      error: Palette.flesh,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Palette.background,
    );

    final text = GoogleFonts.atkinsonHyperlegibleTextTheme(base.textTheme)
        .apply(bodyColor: Palette.ink, displayColor: Palette.ink);

    TextStyle label(bool selected) => GoogleFonts.atkinsonHyperlegible(
          fontSize: 14,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          color: Palette.ink,
        );

    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
            fontSize: 64, fontWeight: FontWeight.w700, height: 1.0, letterSpacing: -1.5),
        headlineMedium: text.headlineMedium?.copyWith(
            fontSize: 30, fontWeight: FontWeight.w700, height: 1.15),
        titleLarge: text.titleLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: 17, height: 1.4),
        bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.4),
        labelLarge: text.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
        labelMedium: text.labelMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Palette.background,
        foregroundColor: Palette.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.atkinsonHyperlegible(
            fontSize: 24, fontWeight: FontWeight.w700, color: Palette.ink),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Palette.surface,
        indicatorColor: Palette.leafTint,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => label(states.contains(WidgetState.selected))),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              size: 26,
              color: states.contains(WidgetState.selected) ? Palette.rind : Palette.muted,
            )),
      ),
      dividerTheme: const DividerThemeData(color: Palette.line, thickness: 1, space: 1),
    );
  }
}
