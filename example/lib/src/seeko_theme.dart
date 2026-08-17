import 'package:flutter/material.dart';

abstract final class SeekoColors {
  static const seekMint = Color(0xFF16C79A);
  static const motionBlue = Color(0xFF4C7DFF);
  static const deepInk = Color(0xFF07111F);
  static const cloud = Color(0xFFF8FAFC);
}

ThemeData buildSeekoTheme(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final ColorScheme scheme =
      ColorScheme.fromSeed(
        seedColor: SeekoColors.seekMint,
        brightness: brightness,
      ).copyWith(
        primary: SeekoColors.seekMint,
        onPrimary: SeekoColors.deepInk,
        primaryContainer: dark
            ? const Color(0xFF0B493E)
            : const Color(0xFFD8F7ED),
        onPrimaryContainer: dark
            ? const Color(0xFFB8F5E3)
            : const Color(0xFF073D33),
        secondary: dark ? const Color(0xFF8BA6FF) : SeekoColors.motionBlue,
        secondaryContainer: dark
            ? const Color(0xFF24365F)
            : const Color(0xFFE3E9FF),
        surface: dark ? const Color(0xFF0B1523) : const Color(0xFFFFFFFF),
        surfaceContainerLowest: dark
            ? SeekoColors.deepInk
            : const Color(0xFFFFFFFF),
        surfaceContainerLow: dark
            ? const Color(0xFF101D2D)
            : const Color(0xFFF7F9FC),
        surfaceContainer: dark
            ? const Color(0xFF142235)
            : const Color(0xFFF0F4F8),
        surfaceContainerHigh: dark
            ? const Color(0xFF1A2A3E)
            : const Color(0xFFE8EEF4),
        surfaceContainerHighest: dark
            ? const Color(0xFF22344A)
            : const Color(0xFFDDE6EE),
        onSurface: dark ? SeekoColors.cloud : SeekoColors.deepInk,
        onSurfaceVariant: dark
            ? const Color(0xFFB7C4D4)
            : const Color(0xFF526071),
        outline: dark ? const Color(0xFF6F8197) : const Color(0xFF718093),
        outlineVariant: dark
            ? const Color(0xFF314359)
            : const Color(0xFFCFD9E3),
      );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? SeekoColors.deepInk
        : const Color(0xFFF1F5F9),
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    textTheme: TextTheme(
      headlineSmall: TextStyle(
        color: scheme.onSurface,
        fontSize: 25,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      titleLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        height: 1.45,
      ),
      bodySmall: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 12.5,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        color: scheme.onSurface,
        fontSize: 13,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: SeekoColors.motionBlue, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 42)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        textStyle: const WidgetStatePropertyAll<TextStyle>(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      textStyle: TextStyle(color: scheme.onInverseSurface),
    ),
  );
}
