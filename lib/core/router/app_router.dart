import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/presentation/accounts_screen.dart';
import '../../features/ai/presentation/ai_insights_screen.dart';
import '../../features/ai/presentation/ai_settings_screen.dart';
import '../../features/budgets/presentation/budgets_screen.dart';
import '../../features/categories/presentation/categories_screen.dart';
import '../../features/data/presentation/data_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/home/presentation/home_customize_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/labels/presentation/labels_screen.dart';
import '../../features/notifications/presentation/reminders_screen.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../features/transactions/presentation/add_transaction_screen.dart';
import '../../features/transactions/presentation/category_limits_screen.dart';
import '../../features/transactions/presentation/debts_screen.dart';
import '../../features/transactions/presentation/recurring_transactions_screen.dart';
import '../../features/transactions/presentation/transactions_screen.dart';

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
      GoRoute(
        path: '/accounts',
        name: 'accounts',
        builder: (context, state) => const AccountsScreen(),
      ),
      GoRoute(
        path: '/categories',
        name: 'categories',
        builder: (context, state) => const CategoriesScreen(),
      ),
      GoRoute(
        path: '/budgets',
        name: 'budgets',
        builder: (context, state) => const BudgetsScreen(),
      ),
      GoRoute(
        path: '/goals',
        name: 'goals',
        builder: (context, state) => const GoalsScreen(),
      ),
      GoRoute(
        path: '/ai-insights',
        name: 'ai-insights',
        builder: (context, state) => const AiInsightsScreen(),
      ),
      GoRoute(
        path: '/ai-settings',
        name: 'ai-settings',
        builder: (context, state) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: '/data',
        name: 'data',
        builder: (context, state) => const DataScreen(),
      ),
      GoRoute(
        path: '/transactions',
        name: 'transactions',
        builder: (context, state) => const TransactionsScreen(),
      ),
      GoRoute(
        path: '/reminders',
        name: 'reminders',
        builder: (context, state) => const RemindersScreen(),
      ),
      GoRoute(
        path: '/labels',
        name: 'labels',
        builder: (context, state) => const LabelsScreen(),
      ),
      GoRoute(
        path: '/home-customize',
        name: 'home-customize',
        builder: (context, state) => const HomeCustomizeScreen(),
      ),
    ],
  );
});
