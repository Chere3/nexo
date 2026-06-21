import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/local_store.dart';
import 'ai_provider_catalog.dart';
import 'anthropic_client.dart';
import 'llm_client.dart';
import 'on_device_gemma_client.dart';
import 'openai_compatible_client.dart';

/// Multi-provider AI configuration.
///
/// Holds one [AiProviderProfile] per known provider (Anthropic + every
/// OpenAI-compatible backend, cloud and local), the id of the active one, and
/// the master on/off switch. Each provider remembers its own key/model/URL, so
/// the user can keep several configured and switch between them.
class AiConfig {
  const AiConfig({
    required this.profiles,
    required this.activeId,
    this.enabled = false,
  });

  final List<AiProviderProfile> profiles;
  final String activeId;
  final bool enabled;

  AiProviderProfile get active =>
      profiles.firstWhere((p) => p.id == activeId, orElse: () => profiles.first);

  AiProviderProfile profile(String id) =>
      profiles.firstWhere((p) => p.id == id, orElse: () => presetById(id).toProfile());

  bool get isReady => enabled && active.isConfigured;

  AiConfig copyWith({List<AiProviderProfile>? profiles, String? activeId, bool? enabled}) {
    return AiConfig(
      profiles: profiles ?? this.profiles,
      activeId: activeId ?? this.activeId,
      enabled: enabled ?? this.enabled,
    );
  }
}

class AiConfigNotifier extends StateNotifier<AiConfig> {
  AiConfigNotifier() : super(_seed()) {
    _load();
  }

  static AiConfig _seed() => AiConfig(
        profiles: kAiProviderPresets.map((p) => p.toProfile()).toList(),
        activeId: kAiProviderPresets.first.id,
      );

  String _meta(String key, String fallback) {
    final rows = LocalStore.db.select('SELECT value FROM app_meta WHERE key = ?', [key]);
    return rows.isEmpty ? fallback : rows.first['value'] as String;
  }

  void _set(String key, String value) {
    LocalStore.db.execute('INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, ?)', [key, value]);
  }

  /// Fresh preset profiles overlaid with any saved user values (key/url/model).
  List<AiProviderProfile> _buildProfiles(Map<String, AiProviderProfile> saved) {
    return kAiProviderPresets.map((preset) {
      final s = saved[preset.id];
      final base = preset.toProfile();
      if (s == null) return base;
      return base.copyWith(apiKey: s.apiKey, baseUrl: s.baseUrl, model: s.model);
    }).toList();
  }

  void _load() {
    final raw = _meta('ai_providers', '');
    final Map<String, AiProviderProfile> saved = {};
    var migratedLegacy = false;

    if (raw.trim().isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        for (final j in list) {
          final p = AiProviderProfile.fromJson(j);
          saved[p.id] = p;
        }
      } catch (_) {/* corrupt blob → fall back to presets */}
    } else {
      // One-time migration from the single-provider (Anthropic-only) config.
      final legacyKey = _meta('ai_api_key', '');
      if (legacyKey.trim().isNotEmpty) {
        final legacyModel = _meta('ai_model', 'claude-haiku-4-5');
        saved['anthropic'] = presetById('anthropic')
            .toProfile()
            .copyWith(apiKey: legacyKey, model: legacyModel);
        migratedLegacy = true;
      }
    }

    final profiles = _buildProfiles(saved);
    final activeId = _meta('ai_active_id', 'anthropic');
    final enabled = _meta('ai_enabled', 'false') == 'true';
    final cfg = AiConfig(
      profiles: profiles,
      activeId: profiles.any((p) => p.id == activeId) ? activeId : profiles.first.id,
      enabled: enabled,
    );
    state = cfg;

    // Finalize the migration: write the canonical blob once and delete the
    // legacy plaintext key rows so they don't linger in the DB or in backups.
    if (migratedLegacy) {
      _persist(cfg);
      LocalStore.db.execute("DELETE FROM app_meta WHERE key IN ('ai_api_key', 'ai_model')");
    }
  }

  void _persist(AiConfig cfg) {
    _set('ai_providers', jsonEncode(cfg.profiles.map((p) => p.toJson()).toList()));
    _set('ai_active_id', cfg.activeId);
    _set('ai_enabled', cfg.enabled ? 'true' : 'false');
  }

  List<AiProviderProfile> _replace(String id, AiProviderProfile updated) {
    return [for (final p in state.profiles) if (p.id == id) updated else p];
  }

  /// Saves key/baseUrl/model for one provider at once.
  void updateProvider(String id, {String? apiKey, String? baseUrl, String? model}) {
    final current = state.profile(id);
    final updated = current.copyWith(apiKey: apiKey, baseUrl: baseUrl, model: model);
    final cfg = state.copyWith(profiles: _replace(id, updated));
    _persist(cfg);
    state = cfg;
  }

  void selectProvider(String id) {
    final cfg = state.copyWith(activeId: id);
    _persist(cfg);
    state = cfg;
  }

  void setEnabled(bool enabled) {
    final cfg = state.copyWith(enabled: enabled);
    _persist(cfg);
    state = cfg;
  }
}

final aiConfigProvider = StateNotifierProvider<AiConfigNotifier, AiConfig>(
  (ref) => AiConfigNotifier(),
);

/// The configured client for the active provider, or null when AI is not ready.
final llmClientProvider = Provider<LlmClient?>((ref) {
  final cfg = ref.watch(aiConfigProvider);
  if (!cfg.isReady) return null;
  return clientForProfile(cfg.active);
});

/// Builds the right transport for a provider profile.
LlmClient clientForProfile(AiProviderProfile p) {
  switch (p.kind) {
    case AiProviderKind.anthropic:
      return AnthropicClient(apiKey: p.apiKey.trim(), defaultModel: p.model.trim());
    case AiProviderKind.openai:
      return OpenAiCompatibleClient(
        baseUrl: p.baseUrl.trim(),
        apiKey: p.apiKey.trim(),
        defaultModel: p.model.trim(),
        label: p.label,
        isLocal: p.isLocal,
      );
    case AiProviderKind.onDevice:
      return OnDeviceGemmaClient(modelId: p.model.trim());
  }
}

final aiReadyProvider = Provider<bool>((ref) => ref.watch(aiConfigProvider).isReady);
