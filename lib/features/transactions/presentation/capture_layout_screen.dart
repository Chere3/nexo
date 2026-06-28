import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/ds_screen_scaffold.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../categories/domain/categories_provider.dart';
import '../domain/capture_layout.dart';
import '../domain/capture_layout_provider.dart';
import '../domain/currency.dart';
import '../domain/transaction.dart';

/// The field-level builder for Quick Add / Batch Add: choose the mode, reorder
/// and show/hide each field, set defaults, pick the document engine and manage
/// saved templates — with a live preview.
class CaptureLayoutScreen extends ConsumerWidget {
  const CaptureLayoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(captureLayoutProvider);
    final notifier = ref.read(captureLayoutProvider.notifier);
    final categories = [for (final c in ref.watch(activeCategoriesProvider)) c.name];
    final accounts = [for (final a in ref.watch(activeAccountsProvider)) a.name];

    return DsScreenScaffold(
      title: 'Captura y layout',
      actions: [
        IconButton(
          tooltip: 'Restablecer',
          icon: const Icon(Icons.restart_alt_rounded),
          onPressed: () => notifier.resetDefaults(),
        ),
      ],
      children: [
        _SectionTitle('Modo de Quick Add'),
        SegmentedButton<QuickAddMode>(
          segments: [
            for (final m in QuickAddMode.values) ButtonSegment(value: m, label: Text(m.label)),
          ],
          selected: {cfg.quickAddMode},
          onSelectionChanged: (s) => notifier.setMode(s.first),
        ),
        const SizedBox(height: 6),
        Text(
          switch (cfg.quickAddMode) {
            QuickAddMode.manual => 'Formulario manual con los campos de abajo.',
            QuickAddMode.ai => 'Escribe o fotografía y la IA crea el movimiento.',
            QuickAddMode.hybrid => 'La IA prellena los campos y tú confirmas.',
          },
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),

        _SectionTitle('Campos de Quick Add'),
        Text('Arrastra para reordenar · interruptor para mostrar/ocultar',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        _FieldReorderList(
          fields: cfg.quickAddFields,
          onReorder: (o, n) => notifier.reorderField(o, n),
          onToggle: (f, v) => notifier.toggleField(f, v),
        ),
        const SizedBox(height: 18),

        _SectionTitle('Vista previa'),
        _PreviewCard(config: cfg),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => context.pushNamed('batch-add'),
          icon: const Icon(Icons.table_rows_rounded),
          label: const Text('Abrir Batch Add'),
        ),
        const SizedBox(height: 18),

        _SectionTitle('Valores por defecto'),
        SegmentedButton<EntryType>(
          segments: const [
            ButtonSegment(value: EntryType.expense, label: Text('Gasto')),
            ButtonSegment(value: EntryType.income, label: Text('Ingreso')),
          ],
          selected: {cfg.defaultType},
          onSelectionChanged: (s) => notifier.setDefaults(type: s.first),
        ),
        const SizedBox(height: 10),
        _DefaultPicker(
          label: 'Categoría por defecto',
          value: cfg.defaultCategoryName,
          options: categories,
          onChanged: (v) => notifier.setDefaults(categoryName: v, clearCategory: v == null),
        ),
        const SizedBox(height: 10),
        _DefaultPicker(
          label: 'Cuenta por defecto',
          value: cfg.defaultAccountName,
          options: accounts,
          onChanged: (v) => notifier.setDefaults(accountName: v, clearAccount: v == null),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: cfg.defaultCurrency,
          items: [for (final c in supportedCurrencies) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (v) => notifier.setDefaults(currency: v),
          decoration: const InputDecoration(labelText: 'Moneda por defecto', prefixIcon: Icon(Icons.currency_exchange_rounded)),
        ),
        const SizedBox(height: 18),

        _SectionTitle('Campos de Batch Add'),
        _FieldReorderList(
          fields: cfg.batchAddFields,
          onReorder: (o, n) => notifier.reorderField(o, n, batch: true),
          onToggle: (f, v) => notifier.toggleField(f, v, batch: true),
        ),
        const SizedBox(height: 18),

        _SectionTitle('Lectura de PDF e imágenes'),
        SegmentedButton<DocumentOcr>(
          showSelectedIcon: false,
          segments: [
            for (final o in DocumentOcr.values) ButtonSegment(value: o, label: Text(o.label)),
          ],
          selected: {cfg.documentOcr},
          onSelectionChanged: (s) => notifier.setDocumentOcr(s.first),
        ),
        const SizedBox(height: 6),
        Text(
          switch (cfg.documentOcr) {
            DocumentOcr.onDeviceOcr =>
              'OCR en el dispositivo (Google ML Kit, gratis y privado): reconoce el texto en el teléfono y luego la IA lo estructura. Recomendado.',
            DocumentOcr.aiVision =>
              'Envía las páginas como imágenes a un proveedor con visión (requiere modelo de visión, p. ej. Codex en el bridge).',
          },
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 18),

        _SectionTitle('Motor de IA para documentos'),
        SegmentedButton<DocumentEngine>(
          showSelectedIcon: false,
          segments: [
            for (final e in DocumentEngine.values) ButtonSegment(value: e, label: Text(e.label)),
          ],
          selected: {cfg.documentEngine},
          onSelectionChanged: (s) => notifier.setDocumentEngine(s.first),
        ),
        const SizedBox(height: 18),

        _SectionTitle('Plantillas'),
        _Templates(notifier: notifier),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

class _FieldReorderList extends StatelessWidget {
  const _FieldReorderList({
    required this.fields,
    required this.onReorder,
    required this.onToggle,
  });

  final List<FieldConfig> fields;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(CaptureField field, bool visible) onToggle;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: onReorder,
      children: [
        for (var i = 0; i < fields.length; i++)
          Card(
            key: ValueKey(fields[i].field.name),
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: i,
                child: const Icon(Icons.drag_indicator_rounded),
              ),
              title: Text(fields[i].field.label),
              trailing: Switch(
                value: fields[i].visible,
                onChanged: (v) => onToggle(fields[i].field, v),
              ),
            ),
          ),
      ],
    );
  }
}

class _DefaultPicker extends StatelessWidget {
  const _DefaultPicker({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = {if (value != null) value!, ...options}.toList();
    return DropdownButtonFormField<String?>(
      initialValue: value,
      isExpanded: true,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Automático')),
        for (final o in items) DropdownMenuItem<String?>(value: o, child: Text(o)),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.star_outline_rounded)),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.config});
  final CaptureLayoutConfig config;

  IconData _iconFor(CaptureField f) => switch (f) {
        CaptureField.type => Icons.swap_vert_rounded,
        CaptureField.amount => Icons.attach_money_rounded,
        CaptureField.title => Icons.edit_note_rounded,
        CaptureField.category => Icons.label_outline_rounded,
        CaptureField.account => Icons.account_balance_wallet_outlined,
        CaptureField.currency => Icons.currency_exchange_rounded,
        CaptureField.date => Icons.event_rounded,
        CaptureField.note => Icons.sticky_note_2_outlined,
        CaptureField.paid => Icons.task_alt_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = config.visibleQuickFields;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Quick add', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const Spacer(),
                if (config.quickAddMode != QuickAddMode.manual)
                  Chip(
                    avatar: const Icon(Icons.auto_awesome_rounded, size: 14),
                    label: Text(config.quickAddMode.label),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (config.quickAddMode != QuickAddMode.manual)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Entrada con IA', style: Theme.of(context).textTheme.bodyMedium)),
                  ],
                ),
              ),
            if (config.quickAddMode != QuickAddMode.ai)
              for (final f in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(_iconFor(f), size: 18, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 38,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(f.label, style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ),
                    ],
                  ),
                ),
            if (config.quickAddMode == QuickAddMode.ai)
              Text('Solo entrada con IA — sin campos manuales.',
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Templates extends ConsumerWidget {
  const _Templates({required this.notifier});
  final CaptureLayoutNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the config so the template list rebuilds after save/apply/delete.
    ref.watch(captureLayoutProvider);
    final templates = notifier.templates();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (templates.isEmpty)
          Text('Guarda la configuración actual como plantilla para reutilizarla.',
              style: Theme.of(context).textTheme.bodySmall)
        else
          for (final t in templates)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: Text(t.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(onPressed: () => notifier.applyTemplate(t.id), child: const Text('Aplicar')),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => notifier.deleteTemplate(t.id),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 6),
        FilledButton.tonalIcon(
          onPressed: () => _saveTemplate(context),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar como plantilla'),
        ),
      ],
    );
  }

  Future<void> _saveTemplate(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Nombre de la plantilla'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ej. "Captura rápida", "Detallado"'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, controller.text.trim()), child: const Text('Guardar')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) notifier.saveTemplate(name);
  }
}
