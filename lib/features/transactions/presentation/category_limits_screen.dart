import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/components/ds_card.dart';
import '../../../design_system/components/ds_feature_header.dart';
import '../domain/category_limits_provider.dart';

class CategoryLimitsScreen extends ConsumerWidget {
  const CategoryLimitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limits = ref.watch(categoryLimitsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Límites por categoría')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const DsFeatureHeader(
            title: 'Límites por categoría',
            subtitle: 'Configura topes mensuales y detecta desvíos antes de que escalen.',
            icon: Icons.speed_rounded,
          ),
          const SizedBox(height: 12),
          DsCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Define un límite mensual por categoría para activar alertas visuales.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),
          ...limits.entries.map(
            (entry) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('Límite actual: ${entry.value.toStringAsFixed(0)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editLimit(context, ref, entry.key, entry.value),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editLimit(BuildContext context, WidgetRef ref, String category, double current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));

    final value = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Límite · $category'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Nuevo límite mensual'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(ctrl.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(context, parsed);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    ctrl.dispose();

    if (value != null) {
      ref.read(categoryLimitsProvider.notifier).setLimit(category, value);
    }
  }
}
