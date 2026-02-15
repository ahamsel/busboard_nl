import 'package:flutter/material.dart';

class AppTheme {
  static const _fontFamily = 'Inter';

  // Light Theme Colors
  static const _lightPrimary = Color(0xFF0277BD);
  static const _lightSecondary = Color(0xFF2E7D32);
  static const _lightBackground = Color(0xFFF5F5F5);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightError = Color(0xFFD32F2F);
  static const _lightOnPrimary = Colors.white;
  static const _lightOnSecondary = Colors.white;
  static const _lightOnSurface = Color(0xFF1A1A2E);

  // Dark Theme Colors
  static const _darkPrimary = Color(0xFF4FC3F7);
  static const _darkSecondary = Color(0xFF81C784);
  static const _darkBackground = Color(0xFF0F0F1A);
  static const _darkSurface = Color(0xFF1A1A2E);
  static const _darkError = Color(0xFFEF5350);
  static const _darkOnPrimary = Colors.black;
  static const _darkOnSecondary = Colors.black;
  static const _darkOnSurface = Colors.white;

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: _lightPrimary,
        secondary: _lightSecondary,
        surface: _lightSurface,
        error: _lightError,
        onPrimary: _lightOnPrimary,
        onSecondary: _lightOnSecondary,
        onSurface: _lightOnSurface,
      ),
      scaffoldBackgroundColor: _lightBackground,
      cardTheme: CardThemeData(
        color: _lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.black.withValues(alpha: 0.05)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _lightBackground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _lightOnSurface,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: _lightOnSurface),
      ),
      textTheme: _buildTextTheme(_lightOnSurface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _lightPrimary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: Colors.grey.shade600),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: _lightOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.06),
        thickness: 1,
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: _darkPrimary,
        secondary: _darkSecondary,
        surface: _darkSurface,
        error: _darkError,
        onPrimary: _darkOnPrimary,
        onSecondary: _darkOnSecondary,
        onSurface: _darkOnSurface,
      ),
      scaffoldBackgroundColor: _darkBackground,
      cardTheme: CardThemeData(
        color: _darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkBackground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: _darkOnSurface,
          letterSpacing: 0.5,
        ),
      ),
      textTheme: _buildTextTheme(_darkOnSurface),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF252540),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _darkPrimary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _darkPrimary,
          foregroundColor: _darkOnPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: _fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.3,
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.06),
        thickness: 1,
      ),
    );
  }

  static TextTheme _buildTextTheme(Color color) {
    return TextTheme(
      headlineLarge: TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w700,
        fontSize: 28,
        letterSpacing: -0.5,
        color: color,
      ),
      headlineMedium: TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 22,
        letterSpacing: -0.3,
        color: color,
      ),
      titleLarge: TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 18,
        color: color,
      ),
      titleMedium: TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: color,
      ),
      bodyLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      bodyMedium: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: color,
      ),
      labelLarge: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: color,
      ),
    );
  }
}
