import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_section_title.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../budgets/domain/budget.dart';
import '../../budgets/domain/budgets_provider.dart';
import '../../goals/domain/goals_provider.dart';
import '../../transactions/domain/currency.dart';

Widget _header(BuildContext context, String title, IconData icon, String route) {
  return Row(
    children: [
      DsSectionTitle(title: title, icon: icon),
      const Spacer(),
      TextButton(onPressed: () => context.pushNamed(route), child: const Text('Ver todos')),
    ],
  );
}

Widget _emptyCta(BuildContext context, String message, String cta, String route) {
  return DsCard(
    padding: const EdgeInsets.all(14),
    onTap: () => context.pushNamed(route),
    child: Row(
      children: [
        Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
        const SizedBox(width: 8),
        FilledButton.tonal(onPressed: () => context.pushNamed(route), child: Text(cta)),
      ],
    ),
  );
}

/// Embedded dashboard module: active budgets with live progress.
class HomeBudgetsModule extends ConsumerWidget {
  const HomeBudgetsModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Presupuestos', Icons.account_balance_rounded, 'budgets'),
        const SizedBox(height: 8),
        if (progress.isEmpty)
          _emptyCta(context, 'Crea un presupuesto para controlar tus gastos.', 'Crear', 'budgets')
        else
          DsCard(
            padding: const EdgeInsets.all(14),
            onTap: () => context.pushNamed('budgets'),
            child: Column(
              children: [
                for (final p in progress.take(3)) ...[
                  _BudgetMiniRow(progress: p, now: now),
                  if (p != progress.take(3).last) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _BudgetMiniRow extends StatelessWidget {
  const _BudgetMiniRow({required this.progress, required this.now});
  final BudgetProgress progress;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = progress.budget;
    final over = progress.isOverBudget;
    final color = over ? theme.colorScheme.error : (progress.isAheadOfPace(now) ? Colors.orange : b.colorValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(b.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text(
              over ? 'Excedido' : '${formatMoneyShort(progress.remaining)} libre',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: over ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.ratio.clamp(0.0, 1.0),
            minHeight: 9,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text('${formatMoney(progress.spent)} de ${formatMoney(b.amount)}', style: theme.textTheme.bodySmall),
      ],
    );
  }
}

/// Embedded dashboard module: savings goals with progress.
class HomeGoalsModule extends ConsumerWidget {
  const HomeGoalsModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(activeGoalsProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Metas de ahorro', Icons.savings_rounded, 'goals'),
        const SizedBox(height: 8),
        if (goals.isEmpty)
          _emptyCta(context, 'Define una meta y registra aportes.', 'Crear', 'goals')
        else
          DsCard(
            padding: const EdgeInsets.all(14),
            onTap: () => context.pushNamed('goals'),
            child: Column(
              children: [
                for (final g in goals.take(3)) ...[
                  Row(
                    children: [
                      Text(g.emoji),
                      const SizedBox(width: 8),
                      Expanded(child: Text(g.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                      Text('${(g.ratio * 100).round()}%', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: g.ratio,
                      minHeight: 9,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      color: g.colorValue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('${formatMoney(g.currentAmount)} de ${formatMoney(g.targetAmount)}', style: theme.textTheme.bodySmall),
                  if (g != goals.take(3).last) const SizedBox(height: 14),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Embedded dashboard module: accounts with live balances.
class HomeAccountsModule extends ConsumerWidget {
  const HomeAccountsModule({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activeAccountsProvider);
    final balances = ref.watch(accountBalancesProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, 'Cuentas', Icons.account_balance_wallet_rounded, 'accounts'),
        const SizedBox(height: 8),
        if (accounts.isEmpty)
          _emptyCta(context, 'Agrega cuentas para ver saldos.', 'Crear', 'accounts')
        else
          DsCard(
            padding: const EdgeInsets.all(8),
            onTap: () => context.pushNamed('accounts'),
            child: Column(
              children: accounts.take(4).map((a) {
                final bal = balances[a.id] ?? 0;
                return ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: a.colorValue.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(11)),
                    child: Text(a.icon, style: const TextStyle(fontSize: 18)),
                  ),
                  title: Text(a.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  trailing: Text(
                    formatMoney(bal, currency: a.currency),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: bal >= 0 ? theme.colorScheme.onSurface : theme.colorScheme.error,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
