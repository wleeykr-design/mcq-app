import 'package:flutter/material.dart';

class BatchColors {
  static const Color navy = Color(0xFF0F2942);
  static const Color navy2 = Color(0xFF163A5C);
  static const Color teal = Color(0xFF0D9488);
  static const Color tealLight = Color(0xFF14B8A6);
  static const Color gold = Color(0xFFC59B27);
  static const Color ok = Color(0xFF059669);
  static const Color err = Color(0xFFDC2626);
  static const Color warn = Color(0xFFD97706);

  static const Color lightBg = Color(0xFFF4F7FA);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFD5E0EA);

  static const Color darkBg = Color(0xFF08121E);
  static const Color darkCard = Color(0xFF0F2035);
  static const Color darkCard2 = Color(0xFF152A44);
  static const Color darkBorder = Color(0xFF213A58);

  static Color mutedColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black54;
}

class AppTheme {
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: BatchColors.lightBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BatchColors.teal,
        primary: BatchColors.navy,
        secondary: BatchColors.teal,
        tertiary: BatchColors.gold,
        surface: BatchColors.lightCard,
        brightness: Brightness.light,
      ),
      cardTheme: CardThemeData(
        color: BatchColors.lightCard,
        elevation: 1.5,
        shadowColor: BatchColors.navy.withOpacity(0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: BatchColors.lightBorder),
        ),
        margin: const EdgeInsets.only(bottom: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BatchColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BatchColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BatchColors.teal, width: 1.6),
        ),
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: BatchColors.darkBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BatchColors.tealLight,
        primary: BatchColors.tealLight,
        secondary: BatchColors.gold,
        surface: BatchColors.darkCard,
        brightness: Brightness.dark,
      ),
      cardTheme: CardThemeData(
        color: BatchColors.darkCard,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: BatchColors.darkBorder),
        ),
        margin: const EdgeInsets.only(bottom: 12),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BatchColors.darkCard2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BatchColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BatchColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BatchColors.tealLight, width: 1.6),
        ),
      ),
    );
  }
}

TextDirection detectTextDirection(String text) {
  final arCount = RegExp(r'[\u0600-\u06FF]').allMatches(text).length;
  final enCount = RegExp(r'[A-Za-z]').allMatches(text).length;
  return arCount > enCount * 0.4 ? TextDirection.rtl : TextDirection.ltr;
}

Color parseHexColor(String hex, {Color fallback = BatchColors.teal}) {
  final clean = hex.replaceAll('#', '').trim();
  if (clean.length == 6) {
    final val = int.tryParse('FF$clean', radix: 16);
    if (val != null) return Color(val);
  }
  return fallback;
}
