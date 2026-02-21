import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_input.dart';
import '../../../design_system/components/ds_primary_button.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../../design_system/components/ds_select.dart';
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
    return DsScreenScaffold(
      title: widget.initialEntry == null ? 'Nuevo movimiento' : 'Editar movimiento',
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
                const SizedBox(height: 12),
                DsInput(
                  controller: _amount,
                  label: 'Monto',
                  icon: Icons.attach_money_rounded,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    final n = double.tryParse(v ?? '');
                    if (n == null || n <= 0) return 'Monto inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DsInput(
                  controller: _title,
                  label: 'Concepto',
                  icon: Icons.edit_note_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresa un concepto' : null,
                ),
                const SizedBox(height: 8),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('Detalles opcionales'),
                  subtitle: const Text('Categoría, cuenta y moneda'),
                  children: [
                    DsSelect<String>(
                      label: 'Categoría',
                      value: _category,
                      icon: Icons.category_outlined,
                      items: const ['Comida', 'Transporte', 'Casa', 'Salud', 'Ocio', 'Ingresos']
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _category = v ?? 'Comida'),
                    ),
                    const SizedBox(height: 12),
                    DsSelect<String>(
                      label: 'Cuenta',
                      value: _account,
                      icon: Icons.account_balance_wallet_outlined,
                      items: const ['Efectivo', 'Débito', 'Crédito', 'Ahorros']
                          .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                          .toList(),
                      onChanged: (v) => setState(() => _account = v ?? 'Efectivo'),
                    ),
                    const SizedBox(height: 12),
                    DsSelect<String>(
                      label: 'Moneda',
                      value: _currency,
                      icon: Icons.currency_exchange_rounded,
                      items: supportedCurrencies
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _currency = v ?? 'MXN'),
                    ),
                  ],
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
