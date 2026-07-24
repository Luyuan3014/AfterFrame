import 'package:flutter/material.dart';

abstract final class AfterFrameColors {
  static const ink = Color(0xFF090A0C);
  static const panel = Color(0xFF15171B);
  static const panelSoft = Color(0xFF1E2025);
  static const glass = Color(0xB31C1E22);
  static const glassSoft = Color(0x7A272A30);
  static const glassBorder = Color(0x24FFFFFF);
  static const paper = Color(0xFFF2F0E9);
  static const muted = Color(0xFF9A9CA3);
  static const lime = Color(0xFFD7FF42);
  static const coral = Color(0xFFFF6A55);
  static const violet = Color(0xFF8E78FF);
}

abstract final class AfterFrameTheme {
  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: AfterFrameColors.lime,
      brightness: Brightness.dark,
      surface: AfterFrameColors.panel,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AfterFrameColors.ink,
      fontFamily: 'sans-serif',
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 38,
          fontWeight: FontWeight.w800,
          height: 1.02,
          letterSpacing: -1.8,
        ),
        headlineMedium: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
        ),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 16, height: 1.45),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      cardTheme: const CardThemeData(
        color: AfterFrameColors.glass,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AfterFrameColors.lime,
          foregroundColor: AfterFrameColors.ink,
          minimumSize: const Size(0, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Color(0xF216171A),
        indicatorColor: Color(0xFFD7FF42),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
