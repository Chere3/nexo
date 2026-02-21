import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class LocalStore {
  LocalStore._();

  static late final Database db;

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'nexo.db');

    db = sqlite3.open(dbPath);
    db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        account TEXT NOT NULL DEFAULT 'Efectivo',
        currency TEXT NOT NULL DEFAULT 'MXN'
      );
    ''');

    final txColumns = db.select('PRAGMA table_info(transactions)');
    final hasAccount = txColumns.any((c) => (c['name'] as String) == 'account');
    if (!hasAccount) {
      db.execute("ALTER TABLE transactions ADD COLUMN account TEXT NOT NULL DEFAULT 'Efectivo'");
    }
    final hasCurrency = txColumns.any((c) => (c['name'] as String) == 'currency');
    if (!hasCurrency) {
      db.execute("ALTER TABLE transactions ADD COLUMN currency TEXT NOT NULL DEFAULT 'MXN'");
    }

    db.execute('''
      CREATE TABLE IF NOT EXISTS app_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS recurring_transactions (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        type TEXT NOT NULL,
        frequency TEXT NOT NULL,
        day_of_month INTEGER,
        day_of_week INTEGER,
        next_due_date TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS debts (
        id TEXT PRIMARY KEY,
        person TEXT NOT NULL,
        concept TEXT NOT NULL,
        amount REAL NOT NULL,
        kind TEXT NOT NULL,
        due_date TEXT,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS category_limits (
        category TEXT PRIMARY KEY,
        limit_amount REAL NOT NULL
      );
    ''');
  }
}
