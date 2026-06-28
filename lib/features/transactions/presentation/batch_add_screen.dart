import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/util/ids.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../ai/domain/ai_providers.dart';
import '../../categories/domain/categories_provider.dart';
import '../domain/capture_layout.dart';
import '../domain/capture_layout_provider.dart';
import '../domain/currency.dart';
import '../domain/transaction.dart';
import '../domain/transactions_provider.dart';
import 'quick_add_sheet.dart';

/// Rapid multi-row manual entry. Columns/fields come from the Batch Add layout
/// config; rows commit together via [TransactionsNotifier.addBatch].
class BatchAddScreen extends ConsumerStatefulWidget {
  const BatchAddScreen({super.key});

  @override
  ConsumerState<BatchAddScreen> createState() => _BatchAddScreenState();
}

class _BatchAddScreenState extends ConsumerState<BatchAddScreen> {
  final List<_BatchRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _addRow();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final cfg = ref.read(captureLayoutProvider);
    _rows.add(_BatchRow(
      type: cfg.defaultType,
      currency: cfg.defaultCurrency,
      category: cfg.defaultCategoryName,
      account: cfg.defaultAccountName,
    ));
  }

  void _removeRow(int i) {
    setState(() {
      _rows[i].dispose();
      _rows.removeAt(i);
    });
  }

  void _commit() {
    final catalog = ref.read(aiCatalogProvider);
    final entries = <FinanceEntry>[];
    for (final r in _rows) {
      final amount = parseAmountInput(r.amount.text);
      if (amount == null || amount <= 0) continue;
      final resolved = resolveCatalog(
        r.category,
        r.account,
        categories: catalog.categories,
        accounts: catalog.accounts,
      );
      entries.add(FinanceEntry(
        id: newId('tx'),
        title: r.title.text.trim().isEmpty ? (r.category ?? 'Movimiento') : r.title.text.trim(),
        amount: amount,
        category: resolved.category?.name ?? r.category ?? 'Sin categoría',
        categoryId: resolved.category?.id,
        date: r.date,
        type: r.type,
        account: resolved.account?.name ?? r.account ?? 'Efectivo',
        accountId: resolved.account?.id,
        currency: r.currency,
        note: r.note.text.trim().isEmpty ? null : r.note.text.trim(),
        paid: r.paid,
        exchangeRate: effectiveMxnRate(r.currency),
        createdAt: DateTime.now(),
      ));
    }
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos una fila con monto válido')),
      );
      return;
    }
    ref.read(transactionsProvider.notifier).addBatch(entries);
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Guardados ${entries.length} movimientos')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(captureLayoutProvider);
    final fields = cfg.visibleBatchFields;
    final categories = [for (final c in ref.watch(activeCategoriesProvider)) c.name];
    final accounts = [for (final a in ref.watch(activeAccountsProvider)) a.name];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch add'),
        actions: [
          TextButton.icon(
            onPressed: _commit,
            icon: const Icon(Icons.check_rounded),
            label: Text('Guardar (${_rows.length})'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(_addRow),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Agregar fila'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
        itemCount: _rows.length,
        itemBuilder: (context, i) => _RowCard(
          index: i,
          row: _rows[i],
          fields: fields,
          categories: categories,
          accounts: accounts,
          onChanged: () => setState(() {}),
          onDelete: _rows.length > 1 ? () => _removeRow(i) : null,
        ),
      ),
    );
  }
}

class _BatchRow {
  _BatchRow({required this.type, required this.currency, this.category, this.account})
      : date = DateTime.now();

  final amount = TextEditingController();
  final title = TextEditingController();
  final note = TextEditingController();
  EntryType type;
  String? category;
  String? account;
  String currency;
  DateTime date;
  bool paid = true;

  void dispose() {
    amount.dispose();
    title.dispose();
    note.dispose();
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({
    required this.index,
    required this.row,
    required this.fields,
    required this.categories,
    required this.accounts,
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final _BatchRow row;
  final List<CaptureField> fields;
  final List<String> categories;
  final List<String> accounts;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Movimiento ${index + 1}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                  ),
              ],
            ),
            for (final f in fields) ...[
              _field(context, f),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(BuildContext context, CaptureField f) {
    switch (f) {
      case CaptureField.type:
        return SegmentedButton<EntryType>(
          segments: const [
            ButtonSegment(value: EntryType.expense, label: Text('Gasto')),
            ButtonSegment(value: EntryType.income, label: Text('Ingreso')),
          ],
          selected: {row.type},
          onSelectionChanged: (s) {
            row.type = s.first;
            onChanged();
          },
        );
      case CaptureField.amount:
        return TextField(
          controller: row.amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Monto', prefixIcon: Icon(Icons.attach_money_rounded), isDense: true),
        );
      case CaptureField.title:
        return TextField(
          controller: row.title,
          decoration: const InputDecoration(labelText: 'Concepto', prefixIcon: Icon(Icons.edit_note_rounded), isDense: true),
        );
      case CaptureField.category:
        final names = {if (row.category != null) row.category!, ...categories}.toList();
        return DropdownButtonFormField<String>(
          initialValue: row.category,
          isExpanded: true,
          items: [for (final c in names) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) {
            row.category = v;
            onChanged();
          },
          decoration: const InputDecoration(labelText: 'Categoría', isDense: true),
        );
      case CaptureField.account:
        final names = {if (row.account != null) row.account!, ...accounts, 'Efectivo'}.toList();
        return DropdownButtonFormField<String>(
          initialValue: row.account,
          isExpanded: true,
          items: [for (final a in names) DropdownMenuItem(value: a, child: Text(a))],
          onChanged: (v) {
            row.account = v;
            onChanged();
          },
          decoration: const InputDecoration(labelText: 'Cuenta', isDense: true),
        );
      case CaptureField.currency:
        final names = {row.currency, ...supportedCurrencies}.toList();
        return DropdownButtonFormField<String>(
          initialValue: row.currency,
          items: [for (final c in names) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) {
            row.currency = v ?? row.currency;
            onChanged();
          },
          decoration: const InputDecoration(labelText: 'Moneda', isDense: true),
        );
      case CaptureField.date:
        return OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: row.date,
              firstDate: DateTime(2015),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) {
              row.date = picked;
              onChanged();
            }
          },
          icon: const Icon(Icons.event_rounded),
          label: Text(DateFormat.yMMMd('es_MX').format(row.date)),
        );
      case CaptureField.note:
        return TextField(
          controller: row.note,
          decoration: const InputDecoration(labelText: 'Nota', isDense: true),
        );
      case CaptureField.paid:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Pagado'),
          value: row.paid,
          onChanged: (v) {
            row.paid = v;
            onChanged();
          },
        );
    }
  }
}
