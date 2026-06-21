import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/local_store.dart';
import 'anthropic_client.dart';

/// Fast/cheap default — classification & extraction are simple, latency-sensitive.
const kDefaultAiModel = 'claude-haiku-4-5';

/// Stronger model for harder, less frequent reasoning (insights, coaching).
const kInsightsAiModel = 'claude-sonnet-4-6';

const kAiModelOptions = <String>[
  'claude-haiku-4-5',
  'claude-sonnet-4-6',
  'claude-opus-4-8',
];

class AiConfig {
  const AiConfig({this.apiKey = '', this.model = kDefaultAiModel, this.enabled = false});

  final String apiKey;
  final String model;
  final bool enabled;

  bool get isReady => enabled && apiKey.trim().isNotEmpty;

  AiConfig copyWith({String? apiKey, String? model, bool? enabled}) {
    return AiConfig(
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
    );
  }
}

class AiConfigNotifier extends StateNotifier<AiConfig> {
  AiConfigNotifier() : super(const AiConfig()) {
    _load();
  }

  String _meta(String key, String fallback) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  void _load() {
    state = AiConfig(
      apiKey: _meta('ai_api_key', ''),
      model: _meta('ai_model', kDefaultAiModel),
      enabled: _meta('ai_enabled', 'false') == 'true',
    );
  }

  void setApiKey(String key) {
    _set('ai_api_key', key.trim());
    // Enabling implicitly when a key is provided keeps the opt-in simple.
    _set('ai_enabled', key.trim().isEmpty ? 'false' : 'true');
    state = state.copyWith(apiKey: key.trim(), enabled: key.trim().isNotEmpty);
  }

  void setModel(String model) {
    _set('ai_model', model);
    state = state.copyWith(model: model);
  }

  void setEnabled(bool enabled) {
    _set('ai_enabled', enabled ? 'true' : 'false');
    state = state.copyWith(enabled: enabled);
  }
}

final aiConfigProvider = StateNotifierProvider<AiConfigNotifier, AiConfig>(
  (ref) => AiConfigNotifier(),
);

/// The configured client, or null when AI is not set up. Recomputed on changes.
final anthropicClientProvider = Provider<AnthropicClient?>((ref) {
  final cfg = ref.watch(aiConfigProvider);
  if (!cfg.isReady) return null;
  return AnthropicClient(apiKey: cfg.apiKey, defaultModel: cfg.model);
});

final aiReadyProvider = Provider<bool>((ref) => ref.watch(aiConfigProvider).isReady);
