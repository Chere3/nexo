import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../../../design_system/components/ds_screen_scaffold.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  late final TextEditingController _key;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _key = TextEditingController(text: ref.read(aiConfigProvider).apiKey);
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(aiConfigProvider);
    final theme = Theme.of(context);

    return DsScreenScaffold(
      title: 'Inteligencia artificial',
      children: [
        const DsFeatureHeader(
          title: 'IA en Nexo',
          subtitle: 'Captura por lenguaje natural, escaneo de recibos, autocategorización e insights.',
          icon: Icons.auto_awesome_rounded,
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('API key de Anthropic', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'La key se guarda solo en este dispositivo y se usa para llamar a la API de Claude.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'sk-ant-...',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () {
                    ref.read(aiConfigProvider.notifier).setApiKey(_key.text);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Configuración guardada')),
                    );
                  },
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        DsCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Modelo', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Haiku es rápido y económico (recomendado para captura). Sonnet/Opus son más capaces.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: kAiModelOptions.contains(cfg.model) ? cfg.model : kDefaultAiModel,
                items: kAiModelOptions.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => ref.read(aiConfigProvider.notifier).setModel(v ?? kDefaultAiModel),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('IA activada'),
          subtitle: Text(cfg.isReady ? 'Lista para usar' : 'Falta configurar la API key'),
          value: cfg.enabled,
          onChanged: cfg.apiKey.trim().isEmpty ? null : (v) => ref.read(aiConfigProvider.notifier).setEnabled(v),
        ),
        const SizedBox(height: 8),
        Text(
          'Privacidad: al usar la IA, el texto o la imagen del movimiento se envía a la API de Anthropic. '
          'El resto de tus datos permanece en el dispositivo.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
