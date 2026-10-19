import 'package:flutter/material.dart';

/// Premium Shopkeeper Pro brand system: deep navy, teal and warm gold accents.
class AppTheme {
  static const Color ink = Color(0xFF0B3D91);
  static const Color paper = Color(0xFFFFFFFF);
  static const Color muted = Color(0xFF64748B);
  static const Color line = Color(0xFFE2E8F0);
  static const Color teal = Color(0xFF14B8A6);
  static const Color gold = Color(0xFFFFBF24);
  static const Color canvas = Color(0xFFF3F4F6);

  static ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: ink,
      onPrimary: paper,
      secondary: teal,
      onSecondary: paper,
      tertiary: gold,
      onTertiary: ink,
      error: Color(0xFFB3261E),
      onError: paper,
      surface: paper,
      onSurface: ink,
      surfaceContainerHighest: Color(0xFFEDF2F8),
    ),
    scaffoldBackgroundColor: canvas,
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: ink,
      foregroundColor: paper,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: paper,
        fontSize: 21,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.4,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: teal,
        disabledForegroundColor: muted,
        disabledBackgroundColor: line,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: teal,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: teal,
      foregroundColor: ink,
      elevation: 3,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: ink,
      indicatorColor: teal.withValues(alpha: 0.22),
      elevation: 8,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? gold : paper,
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? teal : paper,
      )),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: teal),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: teal, width: 1.6),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: paper,
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: line),
      ),
    ),
    dividerColor: line,
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: teal,
      onPrimary: ink,
      secondary: gold,
      onSecondary: ink,
      tertiary: gold,
      onTertiary: ink,
      error: Color(0xFFCF6679),
      onError: ink,
      surface: Color(0xFF082B4C),
      onSurface: paper,
      surfaceContainerHighest: Color(0xFF24354C),
    ),
    scaffoldBackgroundColor: const Color(0xFF082B4C),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      backgroundColor: Color(0xFF082B4C),
      foregroundColor: paper,
      surfaceTintColor: Colors.transparent,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: teal,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF142B4A),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF34465F)),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: const Color(0xFF082B4C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFF2C3E55)),
      ),
    ),
    dividerColor: const Color(0xFF2C3E55),
  );
}
