import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when an Anthropic API call fails or returns an unusable response.
class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => 'AiException: $message';
}

/// An image to attach to a vision request (e.g. a receipt photo).
class AiImage {
  AiImage({required this.base64Data, this.mediaType = 'image/jpeg'});
  final String base64Data;
  final String mediaType;
}

/// Minimal raw-HTTP client for the Anthropic Messages API.
///
/// Dart has no official Anthropic SDK, so this talks to `POST /v1/messages`
/// directly. Structured output is obtained via forced tool use: we declare a
/// single tool with the desired JSON Schema and set tool_choice to that tool,
/// then read the validated `input` object back from the tool_use block.
class AnthropicClient {
  AnthropicClient({required this.apiKey, this.defaultModel = 'claude-haiku-4-5'});

  final String apiKey;
  final String defaultModel;

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _version = '2023-06-01';

  /// Forces Claude to return a JSON object matching [inputSchema] via tool use.
  /// Returns the parsed tool input. Optional [images] enable vision (receipts).
  Future<Map<String, dynamic>> extractStructured({
    required String system,
    required String userText,
    required String toolName,
    required String toolDescription,
    required Map<String, dynamic> inputSchema,
    List<AiImage> images = const [],
    String? model,
    int maxTokens = 1024,
  }) async {
    final content = <Map<String, dynamic>>[
      for (final img in images)
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': img.mediaType, 'data': img.base64Data},
        },
      {'type': 'text', 'text': userText},
    ];

    final body = {
      'model': model ?? defaultModel,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': content},
      ],
      'tools': [
        {'name': toolName, 'description': toolDescription, 'input_schema': inputSchema},
      ],
      'tool_choice': {'type': 'tool', 'name': toolName},
    };

    final json = await _post(body);

    final blocks = (json['content'] as List?) ?? const [];
    for (final block in blocks) {
      if (block is Map && block['type'] == 'tool_use' && block['name'] == toolName) {
        final input = block['input'];
        if (input is Map<String, dynamic>) return input;
        if (input is Map) return Map<String, dynamic>.from(input);
      }
    }
    throw AiException('La respuesta no incluyó datos estructurados.');
  }

  /// Plain text completion (used for free-form insights).
  Future<String> complete({
    required String system,
    required String userText,
    String? model,
    int maxTokens = 1024,
  }) async {
    final body = {
      'model': model ?? defaultModel,
      'max_tokens': maxTokens,
      'system': system,
      'messages': [
        {'role': 'user', 'content': userText},
      ],
    };
    final json = await _post(body);
    final blocks = (json['content'] as List?) ?? const [];
    final buffer = StringBuffer();
    for (final block in blocks) {
      if (block is Map && block['type'] == 'text') buffer.write(block['text']);
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) throw AiException('Respuesta vacía del modelo.');
    return text;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'content-type': 'application/json',
              'x-api-key': apiKey,
              'anthropic-version': _version,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 40));
    } catch (e) {
      throw AiException('No se pudo conectar con la IA: $e');
    }

    if (res.statusCode == 401) throw AiException('API key inválida (401).');
    if (res.statusCode == 429) throw AiException('Límite de uso alcanzado (429). Intenta más tarde.');
    if (res.statusCode >= 400) {
      String detail = res.body;
      try {
        final err = jsonDecode(res.body);
        detail = (err['error']?['message'] ?? detail).toString();
      } catch (_) {}
      throw AiException('Error de IA (${res.statusCode}): $detail');
    }

    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      throw AiException('Respuesta ilegible de la IA.');
    }
  }
}
