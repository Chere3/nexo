import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../transactions/domain/recurring_transaction.dart';
import '../../transactions/domain/recurring_transactions_provider.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../../../../design_system/components/ds_card.dart';
import '../../../../design_system/components/ds_section_title.dart';
import '../../../../design_system/tokens/ds_motion.dart';
import 'widgets/expense_pie_chart.dart';
import 'widgets/spending_line_chart.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(transactionsProvider);
    final balance = ref.watch(balanceProvider);
    final income = ref.watch(totalIncomeProvider);
    final expense = ref.watch(totalExpenseProvider);
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
    final upcomingPayments = ref.watch(upcomingPaymentsProvider);

    final pages = [
      _DashboardTab(
        entries: entries,
        upcomingPayments: upcomingPayments,
        balance: money.format(balance),
        income: money.format(income),
        expense: money.format(expense),
        money: money,
      ),
      _AnalyticsTab(entries: entries, ref: ref),
      const _SettingsTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 0 ? 'Nexo' : _index == 1 ? 'Analytics' : 'Settings'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none_rounded)),
        ],
      ),
      body: AnimatedSwitcher(
        duration: DsMotion.normal,
        switchInCurve: DsMotion.emphasized,
        switchOutCurve: DsMotion.standard,
        child: KeyedSubtree(
          key: ValueKey(_index),
          child: pages[_index],
        ),
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              onPressed: () => context.pushNamed('add'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nuevo movimiento'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Analytics'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.entries,
    required this.upcomingPayments,
    required this.balance,
    required this.income,
    required this.expense,
    required this.money,
  });

  final List<FinanceEntry> entries;
  final List<UpcomingPayment> upcomingPayments;
  final String balance;
  final String income;
  final String expense;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text(
          'Controla tu dinero, sin fricción.',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _BalanceHero(balance: balance, income: income, expense: expense),
        const SizedBox(height: 18),
        Row(
          children: [
            const DsSectionTitle(title: 'Gastos por categoría', icon: Icons.pie_chart_outline_rounded),
          ],
        ),
        const SizedBox(height: 8),
        ExpensePieChart(entries: entries),
        const SizedBox(height: 16),
        Row(
          children: [
            const DsSectionTitle(title: 'Tendencia semanal', icon: Icons.show_chart_rounded),
          ],
        ),
        const SizedBox(height: 8),
        SpendingLineChart(entries: entries),
        const SizedBox(height: 16),
        Row(
          children: [
            const DsSectionTitle(title: 'Próximos pagos', icon: Icons.schedule_rounded),
          ],
        ),
        const SizedBox(height: 8),
        if (upcomingPayments.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No hay pagos programados en los próximos 30 días.'),
            ),
          )
        else
          ...upcomingPayments.map<Widget>((p) {
            final isExpense = p.type == EntryType.expense;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded),
                title: Text(p.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${p.category} · ${DateFormat.yMMMd('es_MX').format(p.dueDate)} · ${p.frequency == RecurringFrequency.weekly ? 'Semanal' : 'Mensual'}',
                ),
                trailing: Text(
                  '${isExpense ? '-' : '+'}${money.format(p.amount)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: isExpense ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
        Row(
          children: [
            const DsSectionTitle(title: 'Movimientos recientes', icon: Icons.receipt_long_rounded),
          ],
        ),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          const _EmptyStateCard()
        else
          ...entries.take(10).map((e) => _EntryTile(entry: e, money: money)),
      ],
    );
  }
}

class _AnalyticsTab extends StatelessWidget {
  const _AnalyticsTab({required this.entries, required this.ref});

  final List<FinanceEntry> entries;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final monthly = entries
        .where((e) => e.type == EntryType.expense)
        .where((e) => e.date.year == DateTime.now().year && e.date.month == DateTime.now().month)
        .fold<double>(0, (s, e) => s + e.amount);
    final weekly = entries
        .where((e) => e.type == EntryType.expense)
        .where((e) => e.date.isAfter(DateTime.now().subtract(const Duration(days: 7))))
        .fold<double>(0, (s, e) => s + e.amount);

    final budgets = ref.watch(monthlyCategoryBudgetsProvider);
    final spent = ref.watch(spentByCategoryProvider);
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DsCard(
          child: Row(
            children: [
              Expanded(child: _MetricTile(label: 'Gasto semanal', value: money.format(weekly))),
              const SizedBox(width: 10),
              Expanded(child: _MetricTile(label: 'Gasto mensual', value: money.format(monthly))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 220,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: BarChart(
                BarChartData(
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  barGroups: [
                    BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: weekly, width: 24)]),
                    BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: monthly, width: 24)]),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Presupuestos por categoría', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...budgets.entries.map((b) {
                final used = spent[b.key] ?? 0;
                final ratio = (used / b.value).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(b.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${money.format(used)} / ${money.format(b.value)}'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: ratio),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTab extends StatelessWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Card(child: ListTile(leading: Icon(Icons.payments_outlined), title: Text('Moneda'), subtitle: Text('MXN'))),
        SizedBox(height: 8),
        Card(child: ListTile(leading: Icon(Icons.dark_mode_outlined), title: Text('Tema'), subtitle: Text('Sistema (Material 3)'))),
        SizedBox(height: 8),
        Card(child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Exportar CSV'), subtitle: Text('Próximamente'))),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({required this.balance, required this.income, required this.expense});

  final String balance;
  final String income;
  final String expense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balance actual', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            Text(balance, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _StatPill(label: 'Ingresos', value: income, icon: Icons.trending_up_rounded, bg: scheme.surface)),
                const SizedBox(width: 10),
                Expanded(child: _StatPill(label: 'Gastos', value: expense, icon: Icons.trending_down_rounded, bg: scheme.surface)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value, required this.icon, required this.bg});

  final String label;
  final String value;
  final IconData icon;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(color: bg.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry, required this.money});

  final FinanceEntry entry;
  final NumberFormat money;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = entry.type == EntryType.expense;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => context.pushNamed('add', extra: entry),
        leading: CircleAvatar(
          backgroundColor: (isExpense ? scheme.errorContainer : scheme.primaryContainer),
          child: Icon(
            isExpense ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            color: isExpense ? scheme.error : scheme.primary,
          ),
        ),
        title: Text(entry.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${entry.category} · ${DateFormat.yMMMd('es_MX').format(entry.date)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isExpense ? '-' : '+'}${money.format(entry.amount)}',
              style: TextStyle(fontWeight: FontWeight.w900, color: isExpense ? scheme.error : scheme.primary),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  context.pushNamed('add', extra: entry);
                } else if (value == 'delete') {
                  ref.read(transactionsProvider.notifier).remove(entry.id);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movimiento eliminado')));
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(value: 'delete', child: Text('Eliminar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.wallet_outlined, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text('Aún no tienes movimientos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Empieza agregando tu primer gasto o ingreso.', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
