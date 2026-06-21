import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/security/app_lock_gate.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_settings.dart';

class NexoApp extends ConsumerWidget {
  const NexoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeSettings = ref.watch(themeSettingsProvider);

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        // A chosen accent overrides dynamic color; otherwise use Material You.
        ColorScheme? lightScheme = lightDynamic;
        ColorScheme? darkScheme = darkDynamic;
        if (themeSettings.accent != null) {
          final seed = Color(themeSettings.accent!);
          lightScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
          darkScheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
        }
        return MaterialApp.router(
          title: 'Nexo',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(dynamicScheme: lightScheme),
          darkTheme: AppTheme.dark(dynamicScheme: darkScheme),
          themeMode: themeSettings.mode,
          routerConfig: router,
          builder: (context, child) => AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
