import 'package:flutter/material.dart';

TextTheme dsTextTheme(ColorScheme scheme) {
  return TextTheme(
    headlineSmall: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: scheme.onSurface),
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: scheme.onSurface),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurface),
    labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
    labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
  );
}
