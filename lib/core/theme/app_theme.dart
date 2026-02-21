import 'package:flutter/material.dart';

import '../../design_system/tokens/ds_radius.dart';
import '../../design_system/tokens/ds_typography.dart';

class AppTheme {
  static ThemeData light({ColorScheme? dynamicScheme}) {
    const seed = Color(0xFF6A3CC3);
    final scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: dsTextTheme(scheme),
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w900,
          color: scheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: DsRadius.brXl),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: DsRadius.brLg,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        selectedColor: scheme.secondaryContainer,
        backgroundColor: scheme.surfaceContainerHigh,
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          iconColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          shape: const RoundedRectangleBorder(borderRadius: DsRadius.brLg),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(const RoundedRectangleBorder(borderRadius: DsRadius.brLg)),
          textStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: const OutlineInputBorder(borderRadius: DsRadius.brLg),
        enabledBorder: OutlineInputBorder(
          borderRadius: DsRadius.brLg,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DsRadius.brLg,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  static ThemeData dark({ColorScheme? dynamicScheme}) {
    const seed = Color(0xFF8D67E8);
    final scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: dsTextTheme(scheme),
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: 0.92),
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w900,
          color: scheme.onSurface,
          letterSpacing: -0.3,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer.withValues(alpha: 0.45),
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w700)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: const RoundedRectangleBorder(borderRadius: DsRadius.brXl),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: DsRadius.brLg,
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        selectedColor: scheme.secondaryContainer.withValues(alpha: 0.7),
        backgroundColor: scheme.surfaceContainerHigh,
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          iconColor: scheme.onPrimary,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: scheme.onSurfaceVariant,
          shape: const RoundedRectangleBorder(borderRadius: DsRadius.brLg),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(const RoundedRectangleBorder(borderRadius: DsRadius.brLg)),
          textStyle: WidgetStateProperty.all(const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: const OutlineInputBorder(borderRadius: DsRadius.brLg),
        enabledBorder: OutlineInputBorder(
          borderRadius: DsRadius.brLg,
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: DsRadius.brLg,
          borderSide: BorderSide(color: scheme.primary, width: 1.7),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
