import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../features/transactions/presentation/add_transaction_screen.dart';
import '../../features/transactions/presentation/category_limits_screen.dart';
import '../../features/transactions/presentation/debts_screen.dart';
import '../../features/transactions/presentation/recurring_transactions_screen.dart';

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
      GoRoute(
        path: '/recurring',
        name: 'recurring',
        builder: (context, state) => const RecurringTransactionsScreen(),
      ),
      GoRoute(
        path: '/debts',
        name: 'debts',
        builder: (context, state) => const DebtsScreen(),
      ),
      GoRoute(
        path: '/category-limits',
        name: 'category-limits',
        builder: (context, state) => const CategoryLimitsScreen(),
      ),
    ],
  );
});
