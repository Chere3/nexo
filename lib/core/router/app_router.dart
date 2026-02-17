import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../features/transactions/presentation/add_transaction_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'home',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: '/add',
        name: 'add',
        builder: (context, state) {
          final initialEntry = state.extra is FinanceEntry ? state.extra as FinanceEntry : null;
          return AddTransactionScreen(initialEntry: initialEntry);
        },
      ),
    ],
  );
});
