import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colore primario del brand (blu stile Google Maps).
const kBrandCopper = Color(0xFF1A73E8);

/// Grigio scuro neutro per testi/superfici scure.
const kBrandDark = Color(0xFF202124);

/// Design tokens: spaziature su griglia 8pt.
abstract class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

/// Design tokens: raggi di arrotondamento.
abstract class AppRadius {
  static const double chip = 10;
  static const double card = 14;
  static const double sheet = 20;
}

/// Temi chiaro e scuro dell'app, costruiti da un'unica fonte (design tokens).
abstract class AppTheme {
  static ThemeData light([Color accent = kBrandCopper]) =>
      _build(Brightness.light, accent);
  static ThemeData dark([Color accent = kBrandCopper]) =>
      _build(Brightness.dark, accent);

  static ThemeData _build(Brightness brightness, Color accent) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      primary: accent,
      brightness: brightness,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121316) : const Color(0xFFF6F7F9),
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1B1C1F) : Colors.white,
        foregroundColor: isDark ? Colors.white : kBrandDark,
        surfaceTintColor: isDark ? const Color(0xFF1B1C1F) : Colors.white,
        elevation: 0.5,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : kBrandDark,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
