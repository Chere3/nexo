import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import 'currency.dart';
import 'transaction.dart';

class TransactionsNotifier extends StateNotifier<List<FinanceEntry>> {
  TransactionsNotifier() : super([]) {
    load();
  }

  void load() {
    final rows = LocalStore.db.select(
      'SELECT id, title, amount, category, date, type, account, currency FROM transactions ORDER BY date DESC',
    );

    state = rows
        .map(
          (r) => FinanceEntry(
            id: r['id'] as String,
            title: r['title'] as String,
            amount: (r['amount'] as num).toDouble(),
            category: r['category'] as String,
            date: DateTime.parse(r['date'] as String),
            type: (r['type'] as String) == 'income' ? EntryType.income : EntryType.expense,
            account: (r['account'] as String?) ?? 'Efectivo',
            currency: (r['currency'] as String?) ?? 'MXN',
          ),
        )
        .toList();

    final seeded = _isSeeded();

    if (state.isNotEmpty && !seeded) {
      _setSeeded();
      return;
    }

    if (state.isEmpty && !seeded) {
      _seed();
      _setSeeded();
      load();
    }
  }

  void add(FinanceEntry entry) {
    LocalStore.db.execute(
      'INSERT OR REPLACE INTO transactions (id, title, amount, category, date, type, account, currency) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        entry.id,
        entry.title,
        entry.amount,
        entry.category,
        entry.date.toIso8601String(),
        entry.type == EntryType.income ? 'income' : 'expense',
        entry.account,
        entry.currency,
      ],
    );
    load();
  }

  void remove(String id) {
    LocalStore.db.execute('DELETE FROM transactions WHERE id = ?', [id]);
    load();
  }

  bool _isSeeded() {
    final rows = LocalStore.db.select(
      "SELECT value FROM app_meta WHERE key = 'seeded_v1' LIMIT 1",
    );
    if (rows.isEmpty) return false;
    return (rows.first['value'] as String) == 'true';
  }

  void _setSeeded() {
    LocalStore.db.execute(
      "INSERT OR REPLACE INTO app_meta (key, value) VALUES ('seeded_v1', 'true')",
    );
  }

  void _seed() {
    final now = DateTime.now();
    final seed = [
      FinanceEntry(
        id: '1',
        title: 'Supermercado',
        amount: 820,
        category: 'Comida',
        date: now.subtract(const Duration(days: 1)),
        type: EntryType.expense,
        account: 'Débito',
      ),
      FinanceEntry(
        id: '2',
        title: 'Uber',
        amount: 145,
        category: 'Transporte',
        date: now.subtract(const Duration(days: 1)),
        type: EntryType.expense,
        account: 'Crédito',
      ),
      FinanceEntry(
        id: '3',
        title: 'Pago freelance',
        amount: 3500,
        category: 'Ingresos',
        date: now.subtract(const Duration(days: 2)),
        type: EntryType.income,
        account: 'Débito',
      ),
      FinanceEntry(
        id: '4',
        title: 'Café',
        amount: 70,
        category: 'Comida',
        date: now.subtract(const Duration(days: 3)),
        type: EntryType.expense,
        account: 'Efectivo',
      ),
    ];

    for (final entry in seed) {
      LocalStore.db.execute(
        'INSERT OR REPLACE INTO transactions (id, title, amount, category, date, type, account, currency) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [
          entry.id,
          entry.title,
          entry.amount,
          entry.category,
          entry.date.toIso8601String(),
          entry.type == EntryType.income ? 'income' : 'expense',
          entry.account,
          entry.currency,
        ],
      );
    }
  }
}

final transactionsProvider = StateNotifierProvider<TransactionsNotifier, List<FinanceEntry>>(
  (ref) => TransactionsNotifier(),
);

final totalIncomeProvider = Provider<double>((ref) {
  return ref
      .watch(transactionsProvider)
      .where((e) => e.type == EntryType.income)
      .fold(0.0, (sum, e) => sum + e.amount);
});

final totalExpenseProvider = Provider<double>((ref) {
  return ref
      .watch(transactionsProvider)
      .where((e) => e.type == EntryType.expense)
      .fold(0.0, (sum, e) => sum + e.amount);
});

final balanceProvider = Provider<double>((ref) {
  return ref.watch(totalIncomeProvider) - ref.watch(totalExpenseProvider);
});

final spentByCategoryProvider = Provider<Map<String, double>>((ref) {
  final entries = ref.watch(transactionsProvider);
  final now = DateTime.now();

  final map = <String, double>{};
  for (final e in entries) {
    if (e.type != EntryType.expense) continue;
    if (e.date.year != now.year || e.date.month != now.month) continue;
    map[e.category] = (map[e.category] ?? 0) + toMxn(e.amount, e.currency);
  }
  return map;
});
