import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../transactions/domain/category_limits_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/debts_provider.dart';
import '../../transactions/domain/recurring_transaction.dart';
import '../../transactions/domain/recurring_transactions_provider.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../../../../design_system/components/ds_card.dart';
import '../../../../design_system/components/ds_empty_state.dart';
import '../../../../design_system/components/ds_section_title.dart';
import '../../../../design_system/components/ds_stat_card.dart';
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
  String _accountFilter = 'Todas';

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(transactionsProvider);
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');
    final upcomingPayments = ref.watch(upcomingPaymentsProvider);
    final debtPendingTotal = ref.watch(debtPendingTotalProvider);

    final accounts = {
      'Todas',
      ...entries.map((e) => e.account),
    }.toList();

    final visibleEntries = _accountFilter == 'Todas'
        ? entries
        : entries.where((e) => e.account == _accountFilter).toList();

    final income = visibleEntries
        .where((e) => e.type == EntryType.income)
        .fold<double>(0, (sum, e) => sum + toMxn(e.amount, e.currency));
    final expense = visibleEntries
        .where((e) => e.type == EntryType.expense)
        .fold<double>(0, (sum, e) => sum + toMxn(e.amount, e.currency));
    final balance = income - expense;

    final pages = [
      _DashboardTab(
        entries: visibleEntries,
        upcomingPayments: upcomingPayments,
        balance: money.format(balance),
        income: money.format(income),
        expense: money.format(expense),
        debtPendingTotal: debtPendingTotal,
        money: money,
        accountFilter: _accountFilter,
        accounts: accounts,
        onAccountChanged: (v) => setState(() => _accountFilter = v),
      ),
      _AnalyticsTab(entries: visibleEntries, ref: ref),
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
              onPressed: _openQuickAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Quick add'),
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

  Future<void> _openQuickAdd() async {
    final amountCtrl = TextEditingController();
    final titleCtrl = TextEditingController();

    EntryType type = EntryType.expense;
    String category = 'Comida';
    String account = 'Efectivo';
    String currency = 'MXN';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Quick add', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('Registra un movimiento en 10 segundos.'),
                  const SizedBox(height: 14),
                  SegmentedButton<EntryType>(
                    segments: const [
                      ButtonSegment(value: EntryType.expense, label: Text('Gasto')),
                      ButtonSegment(value: EntryType.income, label: Text('Ingreso')),
                    ],
                    selected: {type},
                    onSelectionChanged: (v) => setModalState(() => type = v.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Concepto (opcional)',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _quickCategories
                        .map(
                          (c) => ChoiceChip(
                            label: Text(c),
                            selected: c == category,
                            onSelected: (_) => setModalState(() => category = c),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: account,
                    items: const ['Efectivo', 'Débito', 'Crédito', 'Ahorros']
                        .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                        .toList(),
                    onChanged: (v) => setModalState(() => account = v ?? 'Efectivo'),
                    decoration: const InputDecoration(
                      labelText: 'Cuenta',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: currency,
                    items: supportedCurrencies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setModalState(() => currency = v ?? 'MXN'),
                    decoration: const InputDecoration(
                      labelText: 'Moneda',
                      prefixIcon: Icon(Icons.currency_exchange_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        final amount = _parseAmountInput(amountCtrl.text);
                        if (amount == null || amount <= 0) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(content: Text('Ingresa un monto válido para guardar rápido')),
                          );
                          return;
                        }

                        if (_accountFilter != 'Todas' && _accountFilter != account) {
                          setState(() => _accountFilter = account);
                        }

                        ref.read(transactionsProvider.notifier).add(
                              FinanceEntry(
                                id: DateTime.now().millisecondsSinceEpoch.toString(),
                                title: titleCtrl.text.trim().isEmpty ? category : titleCtrl.text.trim(),
                                amount: amount,
                                category: category,
                                date: DateTime.now(),
                                type: type,
                                account: account,
                                currency: currency,
                              ),
                            );

                        Navigator.pop(sheetContext, true);
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Guardar rápido'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Movimiento guardado')),
      );
    }
  }

  double? _parseAmountInput(String input) {
    final raw = input.trim().replaceAll(' ', '');
    if (raw.isEmpty) return null;

    if (raw.contains(',') && raw.contains('.')) {
      return double.tryParse(raw.replaceAll(',', ''));
    }

    if (raw.contains(',')) {
      return double.tryParse(raw.replaceAll(',', '.'));
    }

    return double.tryParse(raw);
  }
}

const _quickCategories = ['Comida', 'Transporte', 'Casa', 'Salud', 'Ocio', 'Ingresos'];

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.entries,
    required this.upcomingPayments,
    required this.balance,
    required this.income,
    required this.expense,
    required this.debtPendingTotal,
    required this.money,
    required this.accountFilter,
    required this.accounts,
    required this.onAccountChanged,
  });

  final List<FinanceEntry> entries;
  final List<UpcomingPayment> upcomingPayments;
  final String balance;
  final String income;
  final String expense;
  final double debtPendingTotal;
  final NumberFormat money;
  final String accountFilter;
  final List<String> accounts;
  final ValueChanged<String> onAccountChanged;

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
        DropdownButtonFormField<String>(
          initialValue: accountFilter,
          items: accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
          onChanged: (v) {
            if (v != null) onAccountChanged(v);
          },
          decoration: const InputDecoration(
            labelText: 'Cuenta activa',
            prefixIcon: Icon(Icons.account_balance_wallet_outlined),
          ),
        ),
        const SizedBox(height: 10),
        _BalanceHero(balance: balance, income: income, expense: expense),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.handshake_outlined),
            title: const Text('Deudas y préstamos'),
            subtitle: Text(
              debtPendingTotal >= 0
                  ? 'Neto por cobrar: ${money.format(debtPendingTotal)}'
                  : 'Neto por pagar: ${money.format(debtPendingTotal.abs())}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.pushNamed('debts'),
          ),
        ),
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
            const Spacer(),
            TextButton.icon(
              onPressed: () => context.pushNamed('recurring'),
              icon: const Icon(Icons.edit_calendar_rounded),
              label: const Text('Gestionar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (upcomingPayments.isEmpty)
          const DsEmptyState(
            icon: Icons.schedule_rounded,
            title: 'Sin pagos próximos',
            message: 'No hay pagos programados en los próximos 30 días.',
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
                  '${p.category} · ${DateFormat.yMMMd('es_MX').format(p.dueDate)} · ${p.frequency == RecurringFrequency.weekly ? 'Semanal' : 'Mensual'}${_dueTag(p.dueDate)}',
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isExpense ? '-' : '+'}${money.format(p.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: isExpense ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Consumer(
                      builder: (context, ref, _) {
                        return PopupMenuButton<String>(
                          tooltip: 'Acciones',
                          onSelected: (value) {
                            if (value == 'done') {
                              ref.read(transactionsProvider.notifier).add(
                                    FinanceEntry(
                                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                                      title: p.title,
                                      amount: p.amount,
                                      category: p.category,
                                      date: DateTime.now(),
                                      type: p.type,
                                    ),
                                  );
                              ref.read(recurringTransactionsProvider.notifier).completeOccurrence(p.recurringId);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Registrado y movido al siguiente ${p.frequency == RecurringFrequency.weekly ? 'ciclo semanal' : 'ciclo mensual'}')),
                              );
                            } else if (value == 'snooze') {
                              ref.read(recurringTransactionsProvider.notifier).snooze(p.recurringId, days: 1);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pago pospuesto 1 día')),
                              );
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'done', child: Text('Registrar ahora')),
                            PopupMenuItem(value: 'snooze', child: Text('Posponer 1 día')),
                          ],
                          child: const Icon(Icons.more_horiz_rounded),
                        );
                      },
                    ),
                  ],
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
          const DsEmptyState(
            icon: Icons.wallet_outlined,
            title: 'Aún no tienes movimientos',
            message: 'Empieza agregando tu primer gasto o ingreso.',
          )
        else
          ...entries.take(10).map((e) => _EntryTile(entry: e, money: money)),
      ],
    );
  }

  String _dueTag(DateTime dueDate) {
    final today = DateTime.now();
    final a = DateTime(today.year, today.month, today.day);
    final b = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = b.difference(a).inDays;

    if (days <= 0) return ' · Hoy';
    if (days == 1) return ' · Mañana';
    if (days <= 3) return ' · En $days días';
    return '';
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
        .fold<double>(0, (s, e) => s + toMxn(e.amount, e.currency));
    final weekly = entries
        .where((e) => e.type == EntryType.expense)
        .where((e) => e.date.isAfter(DateTime.now().subtract(const Duration(days: 7))))
        .fold<double>(0, (s, e) => s + toMxn(e.amount, e.currency));

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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Presupuestos por categoría', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.pushNamed('category-limits'),
                      child: const Text('Configurar límites'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...budgets.entries.map((b) {
                final used = spent[b.key] ?? 0;
                final ratio = (used / b.value).clamp(0.0, 1.0);
                final over = used > b.value;
                final near = !over && ratio >= 0.8;
                final progressColor = over
                    ? Theme.of(context).colorScheme.error
                    : near
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.primary;

                final status = over
                    ? 'Excedido'
                    : near
                        ? 'Cerca del límite'
                        : 'En rango';

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
                      const SizedBox(height: 4),
                      Text(status, style: TextStyle(fontSize: 12, color: progressColor, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: ratio, color: progressColor),
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
                Expanded(child: DsStatCard(label: 'Ingresos', value: income, icon: Icons.trending_up_rounded)),
                const SizedBox(width: 10),
                Expanded(child: DsStatCard(label: 'Gastos', value: expense, icon: Icons.trending_down_rounded)),
              ],
            ),
          ],
        ),
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
        subtitle: Text('${entry.category} · ${entry.account} · ${DateFormat.yMMMd('es_MX').format(entry.date)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isExpense ? '-' : '+'}${entry.currency == 'MXN' ? money.format(entry.amount) : '${entry.currency} ${entry.amount.toStringAsFixed(2)}'}',
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

