import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Central SQLite access for Nexo.
///
/// Schema evolution is handled by a versioned migration runner keyed on
/// `PRAGMA user_version`. Each migration is additive and idempotent so existing
/// installs upgrade in place without data loss. Bump [_schemaVersion] and add a
/// branch in [_runMigrations] whenever the schema changes.
class LocalStore {
  LocalStore._();

  static late final Database db;

  /// Current target schema version. Increment when adding a migration.
  static const int _schemaVersion = 8;

  static Future<void> init() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'nexo.db');

    db = sqlite3.open(dbPath);

    // WAL improves concurrency (needed later for the AutoCapture isolate) and
    // foreign keys keep referential integrity across the new relational tables.
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA foreign_keys = ON');

    applySchema(db);
  }

  /// Applies the base schema and all migrations to [database]. Extracted so it
  /// can run against an in-memory database in tests (the DI seam).
  static void applySchema(Database database) {
    _baseSchema(database);
    _runMigrations(database);
  }

  /// The original v1 schema, kept as `IF NOT EXISTS` so pre-migration installs
  /// (which never set `user_version`) are not disturbed.
  static void _baseSchema(Database db) {
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
    bool hasTxColumn(String name) => txColumns.any((c) => (c['name'] as String) == name);
    if (!hasTxColumn('account')) {
      db.execute("ALTER TABLE transactions ADD COLUMN account TEXT NOT NULL DEFAULT 'Efectivo'");
    }
    if (!hasTxColumn('currency')) {
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

  /// Runs ordered, additive migrations from the stored `user_version` up to
  /// [_schemaVersion]. Wrapped so a failure does not leave a half-applied state.
  static void _runMigrations(Database db) {
    final current = db.select('PRAGMA user_version').first['user_version'] as int;
    if (current >= _schemaVersion) return;

    try {
      db.execute('BEGIN');
      if (current < 2) _migrateTo2(db);
      if (current < 3) _migrateTo3(db);
      if (current < 4) _migrateTo4(db);
      if (current < 5) _migrateTo5(db);
      if (current < 6) _migrateTo6(db);
      if (current < 7) _migrateTo7(db);
      if (current < 8) _migrateTo8(db);
      db.execute('PRAGMA user_version = $_schemaVersion');
      db.execute('COMMIT');
    } catch (e, st) {
      db.execute('ROLLBACK');
      if (kDebugMode) {
        debugPrint('LocalStore migration failed (current=$current): $e');
        debugPrintStack(stackTrace: st);
      }
      rethrow;
    }
  }

  /// v2 — relational model for Cashew parity:
  /// accounts, categories, budgets, goals, labels + richer transaction columns.
  static void _migrateTo2(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        currency TEXT NOT NULL DEFAULT 'MXN',
        color INTEGER NOT NULL,
        icon TEXT NOT NULL,
        starting_balance REAL NOT NULL DEFAULT 0,
        include_in_net_worth INTEGER NOT NULL DEFAULT 1,
        archived INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        emoji TEXT NOT NULL DEFAULT '🏷️',
        color INTEGER NOT NULL,
        type TEXT NOT NULL,
        parent_id TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        archived INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS budgets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        color INTEGER NOT NULL,
        period TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT,
        recurring INTEGER NOT NULL DEFAULT 1,
        category_filter TEXT,
        is_additive INTEGER NOT NULL DEFAULT 0,
        include_income INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS goals (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        target_amount REAL NOT NULL,
        current_amount REAL NOT NULL DEFAULT 0,
        color INTEGER NOT NULL,
        emoji TEXT NOT NULL DEFAULT '🎯',
        deadline TEXT,
        created_at TEXT NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS labels (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL
      );
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_labels (
        transaction_id TEXT NOT NULL,
        label_id TEXT NOT NULL,
        PRIMARY KEY (transaction_id, label_id)
      );
    ''');

    // Enrich transactions with the relational + Cashew fields. Old string
    // `account`/`category` columns stay for backward compatibility; new code
    // prefers the *_id columns and falls back to the strings when null.
    final txCols = db.select('PRAGMA table_info(transactions)');
    bool has(String c) => txCols.any((r) => (r['name'] as String) == c);
    void addCol(String name, String ddl) {
      if (!has(name)) db.execute('ALTER TABLE transactions ADD COLUMN $ddl');
    }

    addCol('note', 'note TEXT');
    addCol('account_id', 'account_id TEXT');
    addCol('category_id', 'category_id TEXT');
    addCol('kind', "kind TEXT NOT NULL DEFAULT 'standard'");
    addCol('transfer_account_id', 'transfer_account_id TEXT');
    addCol('goal_id', 'goal_id TEXT');
    addCol('paid', 'paid INTEGER NOT NULL DEFAULT 1');
    addCol('exchange_rate', 'exchange_rate REAL');
    addCol('created_at', 'created_at TEXT');
    addCol('updated_at', 'updated_at TEXT');
  }

  /// v3 — helpful indexes for the new query patterns.
  static void _migrateTo3(Database db) {
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_date ON transactions(date)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_account ON transactions(account_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_category ON transactions(category_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_tx_kind ON transactions(kind)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_categories_parent ON categories(parent_id)');
  }

  /// v4 — partial debt payments: track how much of a debt has been paid.
  static void _migrateTo4(Database db) {
    final cols = db.select('PRAGMA table_info(debts)');
    final hasPaid = cols.any((c) => (c['name'] as String) == 'paid_amount');
    if (!hasPaid) {
      db.execute('ALTER TABLE debts ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
    }
  }

  /// v5 — AI-generated financial plans persisted by the Planning workspace.
  /// `body` holds the plan JSON (steps, milestones, targets); `type` is the
  /// [PlanType] name; `status` tracks active/archived plans.
  static void _migrateTo5(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS ai_plans (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        created_at TEXT NOT NULL
      );
    ''');
  }

  /// v6 — AutoCapture inbox. Bank/fintech notifications captured by the native
  /// NotificationListenerService land here as an audit trail and a review queue:
  /// the deterministic parser fills entity/amount/direction; the AI suggests a
  /// category. `status` tracks pending → confirmed/dismissed. `transaction_id`
  /// links the movement created when the user confirms a captured row.
  static void _migrateTo6(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS captured_notifications (
        id TEXT PRIMARY KEY,
        package TEXT NOT NULL,
        entity TEXT,
        entity_type TEXT,
        title TEXT,
        text TEXT,
        posted_at TEXT NOT NULL,
        captured_at TEXT NOT NULL,
        amount REAL,
        direction TEXT,
        card_last4 TEXT,
        suggested_category TEXT,
        confidence REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        transaction_id TEXT
      );
    ''');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_captured_status ON captured_notifications(status)');
    db.execute(
        'CREATE INDEX IF NOT EXISTS idx_captured_posted ON captured_notifications(posted_at)');
  }

  /// v7 — learned merchant→category memory. Maps a normalized merchant key
  /// (e.g. "oxxo") to the category the user most often files it under, so
  /// captured movements get categorized automatically with no friction. Seeded
  /// from the user's existing categorized transactions and reinforced on each
  /// manual category choice. `hits` breaks ties toward the most-used category.
  static void _migrateTo7(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS merchant_categories (
        merchant_key TEXT PRIMARY KEY,
        category_id TEXT,
        category_name TEXT NOT NULL,
        hits INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  /// v8 — Documents workspace. Uploaded bank statements / receipts (PDF, image,
  /// CSV, pasted text) are tracked in `documents`; the transactions extracted
  /// from each (by the AI vision/text pipeline, the deterministic CSV parser, or
  /// CaptureParser) land as editable drafts in `document_transactions`. The user
  /// reviews, edits and bulk-imports the staged drafts into real `transactions`;
  /// `transaction_id` links a staged row to the movement it created and
  /// `dedupe_hash` flags re-imports of the same statement. No FK is declared
  /// (matching `captured_notifications`): refs are soft + indexed.
  static void _migrateTo8(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        source_type TEXT NOT NULL,
        file_name TEXT,
        stored_path TEXT,
        mime_type TEXT,
        size_bytes INTEGER,
        page_count INTEGER,
        status TEXT NOT NULL DEFAULT 'parsing',
        tx_count INTEGER NOT NULL DEFAULT 0,
        imported_count INTEGER NOT NULL DEFAULT 0,
        engine TEXT,
        error TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS document_transactions (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL DEFAULT 'Sin categoría',
        category_id TEXT,
        date TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'expense',
        account TEXT NOT NULL DEFAULT 'Efectivo',
        account_id TEXT,
        currency TEXT NOT NULL DEFAULT 'MXN',
        note TEXT,
        confidence REAL NOT NULL DEFAULT 0,
        selected INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'staged',
        transaction_id TEXT,
        dedupe_hash TEXT,
        source_page INTEGER,
        source_line INTEGER,
        created_at TEXT NOT NULL
      );
    ''');
    db.execute('CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doctx_document ON document_transactions(document_id)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doctx_status ON document_transactions(status)');
    db.execute('CREATE INDEX IF NOT EXISTS idx_doctx_dedupe ON document_transactions(dedupe_hash)');
  }
}
