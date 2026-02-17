import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_primary_button.dart';
import '../domain/transaction.dart';
import '../domain/transactions_provider.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _category = 'Comida';
  EntryType _type = EntryType.expense;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo movimiento')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.secondaryContainer, scheme.primaryContainer],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Registra un movimiento', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text('Mantén tus finanzas al día con registros rápidos.', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
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
                    value: _category,
                    items: const ['Comida', 'Transporte', 'Casa', 'Salud', 'Ocio', 'Ingresos']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _category = v ?? 'Comida'),
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      prefixIcon: Icon(Icons.category_outlined),
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
                    label: 'Guardar movimiento',
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

    ref.read(transactionsProvider.notifier).add(
          FinanceEntry(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            title: _title.text.trim(),
            amount: amount,
            category: _category,
            date: DateTime.now(),
            type: _type,
          ),
        );

    context.pop();
  }
}
