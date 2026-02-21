import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_primary_button.dart';
import '../domain/currency.dart';
import '../domain/transaction.dart';
import '../domain/transactions_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key, this.initialEntry});

  final FinanceEntry? initialEntry;

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'Comida';
  String _account = 'Efectivo';
  String _currency = 'MXN';
  EntryType _type = EntryType.expense;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial != null) {
      _title.text = initial.title;
      _amount.text = initial.amount.toStringAsFixed(initial.amount.truncateToDouble() == initial.amount ? 0 : 2);
      _category = initial.category;
      _account = initial.account;
      _currency = initial.currency;
      _type = initial.type;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initialEntry == null ? 'Nuevo movimiento' : 'Editar movimiento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          const DsFeatureHeader(
            title: 'Registra un movimiento',
            subtitle: 'Mantén tus finanzas al día con registros rápidos.',
            icon: Icons.edit_note_rounded,
          ),
          const SizedBox(height: 16),
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Concepto',
                      prefixIcon: Icon(Icons.edit_note_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa un concepto' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monto',
                      prefixIcon: Icon(Icons.attach_money_rounded),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Monto inválido';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    items: const ['Comida', 'Transporte', 'Casa', 'Salud', 'Ocio', 'Ingresos']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v ?? 'Comida'),
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _account,
                    items: const ['Efectivo', 'Débito', 'Crédito', 'Ahorros']
                        .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                        .toList(),
                    onChanged: (v) => setState(() => _account = v ?? 'Efectivo'),
                    decoration: const InputDecoration(
                      labelText: 'Cuenta',
                      prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    items: supportedCurrencies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v ?? 'MXN'),
                    decoration: const InputDecoration(
                      labelText: 'Moneda',
                      prefixIcon: Icon(Icons.currency_exchange_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<EntryType>(
                    segments: const [
                      ButtonSegment(
                        value: EntryType.expense,
                        label: Text('Gasto'),
                        icon: Icon(Icons.remove_circle_outline_rounded),
                      ),
                      ButtonSegment(
                        value: EntryType.income,
                        label: Text('Ingreso'),
                        icon: Icon(Icons.add_circle_outline_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (v) => setState(() => _type = v.first),
                  ),
                  const SizedBox(height: 20),
                  DsPrimaryButton(
                    onPressed: _submit,
                    icon: Icons.save_rounded,
                    label: widget.initialEntry == null ? 'Guardar movimiento' : 'Actualizar movimiento',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amount.text);

    final initial = widget.initialEntry;

    ref.read(transactionsProvider.notifier).add(
          FinanceEntry(
            id: initial?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
            title: _title.text.trim(),
            amount: amount,
            category: _category,
            date: initial?.date ?? DateTime.now(),
            type: _type,
            account: _account,
            currency: _currency,
          ),
        );

    context.pop();
  }
}
