import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

TextTheme dsTextTheme(ColorScheme scheme) {
  final display = GoogleFonts.spaceGrotesk(
    color: scheme.onSurface,
    fontWeight: FontWeight.w700,
  );

  final body = GoogleFonts.plusJakartaSans(
    color: scheme.onSurface,
    fontWeight: FontWeight.w500,
  );

  final label = GoogleFonts.plusJakartaSans(
    color: scheme.onSurfaceVariant,
    fontWeight: FontWeight.w700,
  );

  return TextTheme(
    headlineSmall: display.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.04,
      letterSpacing: -0.6,
    ),
    titleLarge: display.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.12,
      letterSpacing: -0.35,
    ),
    titleMedium: body.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.22,
      color: scheme.onSurface,
    ),
    bodyLarge: body.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    bodyMedium: body.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.4,
    ),
    labelLarge: label.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.2,
    ),
    labelMedium: label.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.25,
    ),
  );
}
