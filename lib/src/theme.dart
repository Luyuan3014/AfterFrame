import 'package:flutter/material.dart';

abstract final class AfterFrameColors {
  static const ink = Color(0xFF070708);
  static const page = ink;
  static const surface = Color(0xFF111114);
  static const elevated = Color(0xFF16171A);
  static const panel = Color(0xFF15171B);
  static const panelSoft = Color(0xFF1E2025);
  static const card = Color(0xCC1A1B20);
  static const glass = Color(0xB31C1E22);
  static const glassSoft = Color(0x7A272A30);
  static const glassBorder = Color(0x24FFFFFF);
  static const paper = Color(0xFFF2F0E9);
  static const textPrimary = Color(0xFFF4F4F2);
  static const muted = Color(0xFF9A9CA3);
  static const textSecondary = muted;
  // Keeps the 11px captions at ~4.9:1 against the page background (WCAG AA).
  static const textTertiary = Color(0xFF7B7E85);
  static const disabled = Color(0xFF4A4B50);
  static const lime = Color(0xFFD7FF42);
  static const brandPrimary = lime;
  static const brandGlow = Color(0xFF1F3D2C);
  static const brandDark = Color(0xFF0B1610);
  static const coral = Color(0xFFFF6A55);
  static const violet = Color(0xFF8E78FF);
  static const navBar = Color(0xFF111114);
  static const navHairline = Color(0x14FFFFFF);
}

abstract final class AfterFrameRadius {
  static const sm = 8.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const xl = 32.0;
}

abstract final class AfterFrameSpace {
  static const s4 = 4.0;
  static const s8 = 8.0;
  static const s12 = 12.0;
  static const s16 = 16.0;
  static const s20 = 20.0;
  static const s24 = 24.0;
  static const s32 = 32.0;
  static const s40 = 40.0;
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
      scaffoldBackgroundColor: AfterFrameColors.page,
      fontFamily: 'sans-serif',
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w600,
          height: 1.08,
          letterSpacing: -1.4,
          color: AfterFrameColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 27,
          fontWeight: FontWeight.w700,
          letterSpacing: -1,
          color: AfterFrameColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -.4,
          color: AfterFrameColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AfterFrameColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 1.45,
          color: AfterFrameColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: AfterFrameColors.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AfterFrameColors.textPrimary,
        ),
      ),
      cardTheme: const CardThemeData(
        color: AfterFrameColors.glass,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AfterFrameRadius.lg)),
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
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        overlayColor: WidgetStatePropertyAll(
          AfterFrameColors.lime.withValues(alpha: .06),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected
                ? AfterFrameColors.lime
                : AfterFrameColors.textTertiary,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected
                ? AfterFrameColors.lime
                : AfterFrameColors.textTertiary,
          );
        }),
      ),
    );
  }
}
