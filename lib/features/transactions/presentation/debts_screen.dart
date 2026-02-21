import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_empty_state.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_list_tile.dart';
import '../../../design_system/components/ds_primary_button.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../domain/debt.dart';
import '../domain/debts_provider.dart';
import '../domain/transaction.dart';
import '../domain/transactions_provider.dart';

class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _concept = TextEditingController();
  final _amount = TextEditingController();

  DebtKind _kind = DebtKind.lent;

  @override
  void dispose() {
    _person.dispose();
    _concept.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(debtsProvider);
    final money = NumberFormat.currency(locale: 'es_MX', symbol: r'$');

    return DsScreenScaffold(
      title: 'Deudas y préstamos',
      children: [
          const DsFeatureHeader(
            title: 'Deudas y préstamos',
            subtitle: 'Lleva control claro de lo que prestaste y lo que debes.',
            icon: Icons.handshake_outlined,
          ),
          const SizedBox(height: 12),
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Nuevo registro', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  SegmentedButton<DebtKind>(
                    segments: const [
                      ButtonSegment(value: DebtKind.lent, label: Text('Presté')),
                      ButtonSegment(value: DebtKind.borrowed, label: Text('Debo')),
                    ],
                    selected: {_kind},
                    onSelectionChanged: (v) => setState(() => _kind = v.first),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _person,
                    decoration: const InputDecoration(labelText: 'Persona'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa una persona' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _concept,
                    decoration: const InputDecoration(labelText: 'Concepto'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa un concepto' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Monto'),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Monto inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  DsPrimaryButton(
                    onPressed: _save,
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Guardar deuda/préstamo',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Pendientes', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (debts.isEmpty)
            const DsEmptyState(
              icon: Icons.handshake_outlined,
              title: 'Sin deudas registradas',
              message: 'Aún no tienes deudas o préstamos registrados.',
            )
          else
            ...debts.map((d) {
              final pending = d.status == DebtStatus.pending;
              return DsListTile(
                icon: d.kind == DebtKind.lent ? Icons.call_received_rounded : Icons.call_made_rounded,
                title: '${d.person} · ${d.concept}',
                subtitle: pending ? 'Pendiente' : 'Liquidado',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${d.kind == DebtKind.borrowed ? '-' : '+'}${money.format(d.amount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: d.kind == DebtKind.borrowed ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    Checkbox(
                      value: !pending,
                      onChanged: (v) => _onSettleChanged(d, v ?? false),
                    ),
                    IconButton(
                      onPressed: () => ref.read(debtsProvider.notifier).remove(d.id),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              );
            }),
      ],
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    ref.read(debtsProvider.notifier).add(
          DebtEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            person: _person.text.trim(),
            concept: _concept.text.trim(),
            amount: double.parse(_amount.text),
            kind: _kind,
            status: DebtStatus.pending,
            createdAt: DateTime.now(),
          ),
        );

    _person.clear();
    _concept.clear();
    _amount.clear();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registro guardado')));
  }

  void _onSettleChanged(DebtEntry debt, bool settled) {
    ref.read(debtsProvider.notifier).markSettled(debt.id, settled);

    if (settled && debt.status == DebtStatus.pending) {
      final type = debt.kind == DebtKind.lent ? EntryType.income : EntryType.expense;
      final titlePrefix = debt.kind == DebtKind.lent ? 'Liquidación por cobrar' : 'Liquidación por pagar';

      ref.read(transactionsProvider.notifier).add(
            FinanceEntry(
              id: 'debt-${debt.id}-${DateTime.now().millisecondsSinceEpoch}',
              title: '$titlePrefix · ${debt.person}',
              amount: debt.amount,
              category: debt.kind == DebtKind.lent ? 'Ingresos' : 'Casa',
              date: DateTime.now(),
              type: type,
            ),
          );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Liquidado y registrado como transacción')),
      );
    }
  }
}
