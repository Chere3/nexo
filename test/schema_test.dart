import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/core/db/local_store.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('LocalStore.applySchema', () {
    test('creates all tables and sets user_version', () {
      final db = sqlite3.openInMemory();
      LocalStore.applySchema(db);

      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toSet();

      for (final t in [
        'transactions',
        'accounts',
        'categories',
        'budgets',
        'goals',
        'labels',
        'transaction_labels',
        'recurring_transactions',
        'debts',
        'category_limits',
        'app_meta',
      ]) {
        expect(tables.contains(t), isTrue, reason: 'missing table $t');
      }

      final version = db.select('PRAGMA user_version').first['user_version'] as int;
      expect(version, 3);
      db.dispose();
    });

    test('is idempotent — applying twice does not throw or duplicate', () {
      final db = sqlite3.openInMemory();
      LocalStore.applySchema(db);
      LocalStore.applySchema(db);
      final version = db.select('PRAGMA user_version').first['user_version'] as int;
      expect(version, 3);
      db.dispose();
    });

    test('transactions has the enriched columns', () {
      final db = sqlite3.openInMemory();
      LocalStore.applySchema(db);
      final cols = db
          .select('PRAGMA table_info(transactions)')
          .map((r) => r['name'] as String)
          .toSet();
      for (final c in ['account_id', 'category_id', 'kind', 'transfer_account_id', 'note', 'paid', 'exchange_rate']) {
        expect(cols.contains(c), isTrue, reason: 'missing column $c');
      }
      db.dispose();
    });

    test('upgrades a legacy v1 database in place', () {
      final db = sqlite3.openInMemory();
      // Simulate the original v1 schema (user_version 0, no new tables).
      db.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY, title TEXT NOT NULL, amount REAL NOT NULL,
          category TEXT NOT NULL, date TEXT NOT NULL, type TEXT NOT NULL
        );
      ''');
      db.execute("INSERT INTO transactions (id,title,amount,category,date,type) "
          "VALUES ('1','Café',45,'Comida','2026-01-01','expense')");

      LocalStore.applySchema(db);

      // Existing row survives and gains defaults for new columns.
      final row = db.select('SELECT account, currency, kind, paid FROM transactions WHERE id = ?', ['1']).first;
      expect(row['account'], 'Efectivo');
      expect(row['currency'], 'MXN');
      expect(row['kind'], 'standard');
      expect((row['paid'] as num).toInt(), 1);
      expect(db.select('PRAGMA user_version').first['user_version'], 3);
      db.dispose();
    });
  });
}
