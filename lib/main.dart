import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/db/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    Zone.current.handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.current,
    );
  };

  await runZonedGuarded(() async {
    try {
      await initializeDateFormatting('es_MX');
    } catch (_) {
      // Keep startup resilient on newer Android/runtime combinations.
    }

    try {
      await LocalStore.init();
    } catch (_) {
      // LocalStore has its own fallback strategy; avoid hard crash at boot.
    }

    runApp(const ProviderScope(child: NexoApp()));
  }, (error, stack) {
    runApp(_EmergencyApp(error: error.toString()));
  });
}

class _EmergencyApp extends StatelessWidget {
  const _EmergencyApp({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Nexo inició en modo seguro.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
