import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/local_store.dart';

class DataPortabilityService {
  Future<String> exportTransactionsCsv() async {
    final rows = LocalStore.db.select(
      'SELECT id, title, amount, category, date, type, account, currency FROM transactions ORDER BY date DESC',
    );

    final lines = <String>[
      'id,title,amount,category,date,type,account,currency',
      ...rows.map(
        (r) => [
          r['id'],
          r['title'],
          r['amount'],
          r['category'],
          r['date'],
          r['type'],
          r['account'],
          r['currency'],
        ].map((v) => _csvEscape('${v ?? ''}')).join(','),
      ),
    ];

    final file = await _createOutputFile(prefix: 'nexo-transactions', extension: '.csv');
    await file.writeAsString(lines.join('\n'));
    return file.path;
  }

  Future<int> importTransactionsCsv(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('No existe el archivo: $path');
    }

    final text = await file.readAsString();
    final lines = const LineSplitter().convert(text).where((l) => l.trim().isNotEmpty).toList();
    if (lines.length <= 1) return 0;

    final headers = _parseCsvLine(lines.first).map((h) => h.trim()).toList();
    final required = ['id', 'title', 'amount', 'category', 'date', 'type', 'account', 'currency'];
    for (final key in required) {
      if (!headers.contains(key)) {
        throw Exception('CSV inválido: falta columna "$key"');
      }
    }

    final index = {for (var i = 0; i < headers.length; i++) headers[i]: i};

    var imported = 0;
    LocalStore.db.execute('BEGIN');
    try {
      for (final line in lines.skip(1)) {
        final values = _parseCsvLine(line);
        if (values.length < headers.length) continue;

        final amount = double.tryParse(values[index['amount']!]);
        if (amount == null) continue;

        final type = values[index['type']!].trim();
        if (type != 'income' && type != 'expense') continue;

        LocalStore.db.execute(
          'INSERT OR REPLACE INTO transactions (id, title, amount, category, date, type, account, currency) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            values[index['id']!],
            values[index['title']!],
            amount,
            values[index['category']!],
            values[index['date']!],
            type,
            values[index['account']!],
            values[index['currency']!],
          ],
        );
        imported++;
      }
      LocalStore.db.execute('COMMIT');
    } catch (_) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }

    return imported;
  }

  Future<String> createBackupJson() async {
    final payload = {
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'transactions': _rows('SELECT * FROM transactions'),
      'recurring_transactions': _rows('SELECT * FROM recurring_transactions'),
      'debts': _rows('SELECT * FROM debts'),
      'category_limits': _rows('SELECT * FROM category_limits'),
      'app_meta': _rows('SELECT * FROM app_meta'),
    };

    final file = await _createOutputFile(prefix: 'nexo-backup', extension: '.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file.path;
  }

  Future<void> restoreBackupJson(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('No existe el archivo: $path');
    }

    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Backup inválido');
    }

    List<Map<String, dynamic>> tableRows(String key) {
      final raw = decoded[key];
      if (raw is! List) return <Map<String, dynamic>>[];
      return raw.whereType<Map>().map((e) => e.map((k, v) => MapEntry('$k', v))).toList();
    }

    final tx = tableRows('transactions');
    final recurring = tableRows('recurring_transactions');
    final debts = tableRows('debts');
    final limits = tableRows('category_limits');
    final meta = tableRows('app_meta');

    LocalStore.db.execute('BEGIN');
    try {
      for (final table in ['transactions', 'recurring_transactions', 'debts', 'category_limits', 'app_meta']) {
        LocalStore.db.execute('DELETE FROM $table');
      }

      for (final row in tx) {
        LocalStore.db.execute(
          'INSERT INTO transactions (id, title, amount, category, date, type, account, currency) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            row['id'],
            row['title'],
            row['amount'],
            row['category'],
            row['date'],
            row['type'],
            row['account'] ?? 'Efectivo',
            row['currency'] ?? 'MXN',
          ],
        );
      }

      for (final row in recurring) {
        LocalStore.db.execute(
          'INSERT INTO recurring_transactions (id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            row['id'],
            row['title'],
            row['amount'],
            row['category'],
            row['type'],
            row['frequency'],
            row['day_of_month'],
            row['day_of_week'],
            row['next_due_date'],
            row['active'] ?? 1,
          ],
        );
      }

      for (final row in debts) {
        LocalStore.db.execute(
          'INSERT INTO debts (id, person, concept, amount, kind, due_date, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [
            row['id'],
            row['person'],
            row['concept'],
            row['amount'],
            row['kind'],
            row['due_date'],
            row['status'],
            row['created_at'],
          ],
        );
      }

      for (final row in limits) {
        LocalStore.db.execute(
          'INSERT INTO category_limits (category, limit_amount) VALUES (?, ?)',
          [row['category'], row['limit_amount']],
        );
      }

      for (final row in meta) {
        LocalStore.db.execute(
          'INSERT INTO app_meta (key, value) VALUES (?, ?)',
          [row['key'], row['value']],
        );
      }

      LocalStore.db.execute('COMMIT');
    } catch (_) {
      LocalStore.db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<Map<String, dynamic>> _rows(String sql) {
    final rows = LocalStore.db.select(sql);
    return rows.map((r) => Map<String, dynamic>.from(r)).toList();
  }

  Future<File> _createOutputFile({required String prefix, required String extension}) async {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File(p.join(dir.path, '$prefix-$timestamp$extension'));
    await file.parent.create(recursive: true);
    return file;
  }

  String _csvEscape(String input) {
    final escaped = input.replaceAll('"', '""');
    return '"$escaped"';
  }

  List<String> _parseCsvLine(String line) {
    final values = <String>[];
    final buffer = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];

      if (ch == '"') {
        final nextIsQuote = i + 1 < line.length && line[i + 1] == '"';
        if (inQuotes && nextIsQuote) {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (ch == ',' && !inQuotes) {
        values.add(buffer.toString());
        buffer.clear();
        continue;
      }

      buffer.write(ch);
    }

    values.add(buffer.toString());
    return values;
  }
}
