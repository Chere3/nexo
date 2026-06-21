import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/db/local_store.dart';
import 'core/firebase/firebase_bootstrap.dart';
import 'core/fx/fx_service.dart';
import 'core/notifications/notification_service.dart';
import 'features/data/domain/auto_backup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_MX');
  await LocalStore.init();
  loadCachedFxRates();
  await AutoBackup.maybeRunOnLaunch();
  await FirebaseBootstrap.initialize();
  await NotificationService.init();
  runApp(const ProviderScope(child: NexoApp()));
}
