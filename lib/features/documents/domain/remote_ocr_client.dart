import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

/// Thrown when the remote OCR endpoint fails or returns an unusable response.
class RemoteOcrException implements Exception {
  RemoteOcrException(this.message);
  final String message;
  @override
  String toString() => 'RemoteOcrException: $message';
}

/// Calls a **Mistral-OCR-compatible** endpoint (`POST {baseUrl}/ocr`) to turn a
/// document/image into markdown text, which is then handed to the AI text
/// extractor. Works with Mistral's cloud API and any self-hosted server that
/// speaks the same contract (e.g. a Mistral OCR 4 container, or a thin wrapper
/// in front of dots.ocr / Marker). The response is parsed leniently: page
/// markdown is preferred, with `text`/`content`/`markdown` fallbacks.
class RemoteOcrClient {
  const RemoteOcrClient();

  Future<String> recognize({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$root/ocr');
    final dataUri = 'data:$mimeType;base64,${base64Encode(bytes)}';
    final isPdf = mimeType.contains('pdf');
    final document = isPdf
        ? {'type': 'document_url', 'document_url': dataUri}
        : {'type': 'image_url', 'image_url': dataUri};

    final http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (apiKey.trim().isNotEmpty) 'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode({
              'model': model.trim().isEmpty ? 'mistral-ocr-latest' : model.trim(),
              'document': document,
              'include_image_base64': false,
            }),
          )
          .timeout(const Duration(seconds: 120));
    } catch (e) {
      throw RemoteOcrException('No se pudo contactar el endpoint OCR: $e');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw RemoteOcrException('OCR remoto respondió ${res.statusCode}: ${_trim(res.body)}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (_) {
      // Some servers return plain text/markdown directly.
      return res.body;
    }
    return _extractText(decoded);
  }

  /// Pulls markdown/text out of common OCR response shapes.
  String _extractText(Object? decoded) {
    if (decoded is String) return decoded;
    if (decoded is Map) {
      final pages = decoded['pages'];
      if (pages is List && pages.isNotEmpty) {
        final buf = StringBuffer();
        for (final pg in pages) {
          if (pg is Map) {
            final t = pg['markdown'] ?? pg['text'] ?? pg['content'];
            if (t is String && t.trim().isNotEmpty) buf.writeln(t);
          } else if (pg is String) {
            buf.writeln(pg);
          }
        }
        if (buf.isNotEmpty) return buf.toString();
      }
      final direct = decoded['markdown'] ?? decoded['text'] ?? decoded['content'];
      if (direct is String) return direct;
    }
    throw RemoteOcrException('Respuesta OCR sin texto reconocible.');
  }

  static String _trim(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;
}

final remoteOcrClientProvider = Provider<RemoteOcrClient>((ref) => const RemoteOcrClient());
