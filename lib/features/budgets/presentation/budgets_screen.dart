import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../transactions/domain/currency.dart';
import '../domain/budget.dart';
import '../domain/budgets_provider.dart';
import 'budget_editor.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(budgetProgressProvider);

    return DsScreenScaffold(
      title: 'Presupuestos',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBudgetEditor(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Presupuesto'),
      ),
      children: [
        const DsFeatureHeader(
          title: 'Presupuestos',
          subtitle: 'Define topes por periodo y categoría, con ritmo de gasto en vivo.',
          icon: Icons.account_balance_rounded,
        ),
        const SizedBox(height: 12),
        if (progress.isEmpty)
          const DsEmptyState(
            icon: Icons.account_balance_outlined,
            title: 'Sin presupuestos',
            message: 'Crea un presupuesto mensual o semanal para controlar tus gastos.',
          )
        else
          ...progress.map((p) => _BudgetCard(progress: p)),
      ],
    );
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.progress});
  final BudgetProgress progress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final b = progress.budget;
    final now = DateTime.now();
    final ratio = progress.ratio.clamp(0.0, 1.0);
    final over = progress.isOverBudget;
    final ahead = progress.isAheadOfPace(now);
    final df = DateFormat('d MMM', 'es_MX');

    final barColor = over
        ? theme.colorScheme.error
        : (ahead ? Colors.orange : b.colorValue);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DsCard(
        padding: const EdgeInsets.all(16),
        onTap: () => showBudgetEditor(context, ref, existing: b),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 12, height: 12, decoration: BoxDecoration(color: b.colorValue, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(b.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                ),
                Text(
                  '${b.period.label} · ${df.format(progress.cycle.start)}–${df.format(progress.cycle.end.subtract(const Duration(days: 1)))}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: ratio == 0 ? null : ratio,
                minHeight: 12,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: barColor,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '${formatMoney(progress.spent)} de ${formatMoney(b.amount)}',
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  over
                      ? 'Excedido ${formatMoney(progress.spent - b.amount)}'
                      : 'Quedan ${formatMoney(progress.remaining)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: over ? theme.colorScheme.error : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            if (ahead && !over) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.speed_rounded, size: 16, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Vas por encima del ritmo: ideal ${formatMoney(progress.pacedTarget(now))} a hoy.',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
