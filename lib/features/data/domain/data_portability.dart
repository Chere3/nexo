import 'dart:convert';

import '../../../core/db/local_store.dart';
import '../../../core/util/ids.dart';

/// Tables included in a full backup/restore. Order matters for FK-free restore
/// (parents before children isn't enforced since FKs aren't declared, but we
/// keep a sensible order anyway).
const kBackupTables = <String>[
  'accounts',
  'categories',
  'budgets',
  'goals',
  'labels',
  'transactions',
  'transaction_labels',
  'recurring_transactions',
  'debts',
  'category_limits',
  'app_meta',
];

/// Result of an import operation.
class ImportResult {
  ImportResult(this.inserted, this.message);
  final int inserted;
  final String message;
}

class DataPortability {
  /// Builds a CSV of all transactions. Safe-quotes every field.
  static String transactionsCsv() {
    final rows = LocalStore.db.select(
      'SELECT id, date, type, amount, currency, category, account, title, note, kind, paid '
      'FROM transactions ORDER BY date DESC',
    );
    final b = StringBuffer();
    b.writeln('id,date,type,amount,currency,category,account,title,note,kind,paid');
    for (final r in rows) {
      b.writeln([
        r['id'],
        r['date'],
        r['type'],
        r['amount'],
        r['currency'],
        r['category'],
        r['account'],
        r['title'],
        r['note'],
        r['kind'],
        r['paid'],
      ].map(_csvField).join(','));
    }
    return b.toString();
  }

  /// Full JSON backup of all known tables, plus schema version + timestamp.
  static String backupJson({required String generatedAtIso}) {
    final dump = <String, dynamic>{
      'app': 'nexo',
      'schema': 'v3',
      'generated_at': generatedAtIso,
      'tables': <String, dynamic>{},
    };
    final tables = dump['tables'] as Map<String, dynamic>;
    for (final t in kBackupTables) {
      tables[t] = _dumpTable(t);
    }
    return const JsonEncoder.withIndent('  ').convert(dump);
  }

  static List<Map<String, dynamic>> _dumpTable(String table) {
    try {
      final rows = LocalStore.db.select('SELECT * FROM $table');
      return rows.map((r) {
        final m = <String, dynamic>{};
        for (final c in r.keys) {
          m[c] = r[c];
        }
        return m;
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Restores a full backup produced by [backupJson]. Upserts every row.
  static ImportResult restoreBackup(String json) {
    final data = jsonDecode(json);
    if (data is! Map || data['tables'] is! Map) {
      throw const FormatException('Archivo de respaldo inválido.');
    }
    final tables = data['tables'] as Map;
    var total = 0;
    LocalStore.db.execute('BEGIN');
    try {
      for (final entry in tables.entries) {
        final table = entry.key as String;
        if (!kBackupTables.contains(table)) continue;
        final rows = entry.value;
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          total += _upsertRow(table, row.cast<String, dynamic>()) ? 1 : 0;
        }
      }
      LocalStore.db.execute('COMMIT');
    } catch (e) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }
    return ImportResult(total, 'Respaldo restaurado: $total registros.');
  }

  static bool _upsertRow(String table, Map<String, dynamic> row) {
    final cols = _tableColumns(table);
    final present = row.keys.where(cols.contains).toList();
    if (present.isEmpty) return false;
    final placeholders = List.filled(present.length, '?').join(', ');
    final values = present.map((k) => row[k]).toList();
    try {
      LocalStore.db.execute(
        'INSERT OR REPLACE INTO $table (${present.join(', ')}) VALUES ($placeholders)',
        values,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Set<String> _tableColumns(String table) {
    final info = LocalStore.db.select('PRAGMA table_info($table)');
    return info.map((r) => r['name'] as String).toSet();
  }

  /// Imports transactions from a CSV with the header produced by
  /// [transactionsCsv]. New ids are generated when missing/duplicate-safe.
  static ImportResult importTransactionsCsv(String csv) {
    final lines = const LineSplitter().convert(csv).where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return ImportResult(0, 'Archivo vacío.');
    final header = _parseCsvLine(lines.first).map((h) => h.trim().toLowerCase()).toList();
    int idx(String name) => header.indexOf(name);

    final iDate = idx('date');
    final iType = idx('type');
    final iAmount = idx('amount');
    if (iDate < 0 || iAmount < 0) {
      throw const FormatException('CSV sin columnas date/amount.');
    }
    final iCurrency = idx('currency');
    final iCategory = idx('category');
    final iAccount = idx('account');
    final iTitle = idx('title');
    final iNote = idx('note');

    var inserted = 0;
    LocalStore.db.execute('BEGIN');
    try {
      for (final line in lines.skip(1)) {
        final f = _parseCsvLine(line);
        String at(int i) => (i >= 0 && i < f.length) ? f[i] : '';
        final amount = double.tryParse(at(iAmount).replaceAll(',', '.'));
        if (amount == null) continue;
        final date = DateTime.tryParse(at(iDate))?.toIso8601String() ?? DateTime.now().toIso8601String();
        final type = at(iType).toLowerCase() == 'income' ? 'income' : 'expense';
        LocalStore.db.execute(
          'INSERT OR REPLACE INTO transactions (id, title, amount, category, date, type, account, currency, note, kind, paid, created_at, updated_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            newId('imp'),
            iTitle >= 0 && at(iTitle).isNotEmpty ? at(iTitle) : 'Importado',
            amount.abs(),
            iCategory >= 0 && at(iCategory).isNotEmpty ? at(iCategory) : 'Sin categoría',
            date,
            type,
            iAccount >= 0 && at(iAccount).isNotEmpty ? at(iAccount) : 'Efectivo',
            iCurrency >= 0 && at(iCurrency).isNotEmpty ? at(iCurrency) : 'MXN',
            iNote >= 0 ? at(iNote) : null,
            'standard',
            1,
            date,
            DateTime.now().toIso8601String(),
          ],
        );
        inserted++;
      }
      LocalStore.db.execute('COMMIT');
    } catch (e) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }
    return ImportResult(inserted, 'Importadas $inserted transacciones.');
  }

  static String _csvField(Object? value) {
    final s = value?.toString() ?? '';
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static List<String> _parseCsvLine(String line) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          sb.write(ch);
        }
      } else {
        if (ch == '"') {
          inQuotes = true;
        } else if (ch == ',') {
          out.add(sb.toString());
          sb.clear();
        } else {
          sb.write(ch);
        }
      }
    }
    out.add(sb.toString());
    return out;
  }
}
