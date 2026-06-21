import '../../../core/ai/anthropic_client.dart';
import '../../transactions/domain/transaction.dart';

/// A structured draft produced by the AI from natural language or a receipt.
/// Names (category/account) are resolved against the user's catalog by the UI.
class ParsedTransaction {
  ParsedTransaction({
    required this.amount,
    required this.type,
    required this.title,
    this.categoryName,
    this.accountName,
    this.currency = 'MXN',
    this.date,
    this.note,
    this.confidence,
  });

  final double amount;
  final EntryType type;
  final String title;
  final String? categoryName;
  final String? accountName;
  final String currency;
  final DateTime? date;
  final String? note;
  final double? confidence;
}

class AiServices {
  AiServices(this.client);
  final AnthropicClient client;

  static String _today() => DateTime.now().toIso8601String().split('T').first;

  static const _txSchema = <String, dynamic>{
    'type': 'object',
    'properties': {
      'amount': {'type': 'number', 'description': 'Monto positivo'},
      'type': {
        'type': 'string',
        'enum': ['expense', 'income'],
      },
      'title': {'type': 'string', 'description': 'Concepto corto'},
      'category': {'type': 'string', 'description': 'Nombre de categoría de la lista provista'},
      'account': {'type': 'string', 'description': 'Nombre de cuenta de la lista provista'},
      'currency': {
        'type': 'string',
        'enum': ['MXN', 'USD', 'EUR'],
      },
      'date_iso': {'type': 'string', 'description': 'Fecha ISO 8601 (YYYY-MM-DD)'},
      'note': {'type': 'string'},
    },
    'required': ['amount', 'type', 'title'],
  };

  ParsedTransaction _fromInput(Map<String, dynamic> input) {
    final amount = (input['amount'] as num?)?.toDouble() ?? 0;
    final type = (input['type'] as String?) == 'income' ? EntryType.income : EntryType.expense;
    DateTime? date;
    final dIso = input['date_iso'] as String?;
    if (dIso != null) date = DateTime.tryParse(dIso);
    return ParsedTransaction(
      amount: amount.abs(),
      type: type,
      title: (input['title'] as String?)?.trim().isNotEmpty == true ? input['title'] as String : 'Movimiento',
      categoryName: (input['category'] as String?)?.trim(),
      accountName: (input['account'] as String?)?.trim(),
      currency: (input['currency'] as String?) ?? 'MXN',
      date: date,
      note: (input['note'] as String?)?.trim(),
    );
  }

  /// Parses free text like "café 45 ayer con débito" into a draft transaction.
  Future<ParsedTransaction> parseNaturalLanguage(
    String text, {
    required List<String> categories,
    required List<String> accounts,
  }) async {
    final input = await client.extractStructured(
      system:
          'Eres un asistente de finanzas para usuarios en México. Conviertes texto en lenguaje natural '
          'en un movimiento financiero estructurado. La fecha de hoy es ${_today()}; resuelve fechas '
          'relativas como "ayer" o "el lunes" a una fecha ISO. La moneda por defecto es MXN. '
          'Elige category y account SOLO de estas listas cuando apliquen.\n'
          'Categorías: ${categories.join(", ")}\n'
          'Cuentas: ${accounts.join(", ")}',
      userText: text,
      toolName: 'registrar_movimiento',
      toolDescription: 'Registra un movimiento financiero estructurado a partir del texto del usuario.',
      inputSchema: _txSchema,
    );
    return _fromInput(input);
  }

  /// Suggests the best category name for a transaction title.
  Future<String?> suggestCategory(String title, {required List<String> categories}) async {
    if (categories.isEmpty) return null;
    final input = await client.extractStructured(
      system: 'Clasificas movimientos de gasto en una de las categorías dadas. Responde con la más adecuada.',
      userText: 'Concepto: "$title".\nCategorías disponibles: ${categories.join(", ")}.',
      toolName: 'clasificar',
      toolDescription: 'Elige la categoría más adecuada para el concepto.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'category': {
            'type': 'string',
            'enum': categories,
          },
          'confidence': {'type': 'number'},
        },
        'required': ['category'],
      },
      maxTokens: 256,
    );
    return input['category'] as String?;
  }

  /// Parses a receipt photo into a draft transaction (vision).
  Future<ParsedTransaction> parseReceipt(
    AiImage image, {
    required List<String> categories,
  }) async {
    final input = await client.extractStructured(
      system:
          'Extraes los datos de un ticket/recibo de compra. Devuelve el total pagado como amount, '
          'el comercio como title, la fecha si aparece, y la categoría más probable de la lista. '
          'La fecha de hoy es ${_today()}. Categorías: ${categories.join(", ")}',
      userText: 'Extrae el movimiento de este recibo.',
      images: [image],
      toolName: 'extraer_recibo',
      toolDescription: 'Extrae el total, comercio, fecha y categoría de un recibo.',
      inputSchema: _txSchema,
      model: 'claude-haiku-4-5',
      maxTokens: 1024,
    );
    final parsed = _fromInput(input);
    return ParsedTransaction(
      amount: parsed.amount,
      type: EntryType.expense,
      title: parsed.title,
      categoryName: parsed.categoryName,
      accountName: parsed.accountName,
      currency: parsed.currency,
      date: parsed.date,
      note: parsed.note,
    );
  }

  /// Generates short, actionable spending insights from a textual summary.
  Future<List<String>> generateInsights(String summary, {String? model}) async {
    final input = await client.extractStructured(
      system:
          'Eres un coach financiero para usuarios en México. A partir del resumen de gastos, das de 2 a 4 '
          'observaciones breves, concretas y accionables en español, cada una de una frase. Sé directo y útil, '
          'sin relleno. Usa cifras del resumen cuando ayuden.',
      userText: summary,
      toolName: 'dar_observaciones',
      toolDescription: 'Devuelve una lista de observaciones financieras breves.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'insights': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['insights'],
      },
      model: model ?? 'claude-sonnet-4-6',
      maxTokens: 700,
    );
    final list = (input['insights'] as List?) ?? const [];
    return list.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
  }
}
