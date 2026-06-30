import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../accounts/domain/accounts_provider.dart';
import '../../ai/domain/ai_providers.dart';
import '../../capture/domain/merchant_memory.dart';
import '../../categories/domain/categories_provider.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import '../domain/document.dart';
import '../domain/document_reconciler.dart';
import '../domain/document_transaction.dart';
import '../domain/documents_provider.dart';

/// Review + bulk-manage the transactions extracted from one document. The user
/// edits drafts inline, multi-selects, and imports/deletes/bulk-edits them.
class DocumentDetailScreen extends ConsumerStatefulWidget {
  const DocumentDetailScreen({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  bool _busy = false;
  bool _aiBusy = false;
  bool _autoReconcileScheduled = false;

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(documentsProvider);
    NexoDocument? doc;
    for (final d in docs) {
      if (d.id == widget.documentId) {
        doc = d;
        break;
      }
    }
    final drafts = ref.watch(documentTransactionsProvider(widget.documentId));

    if (doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documento')),
        body: const Center(child: Text('Documento no encontrado.')),
      );
    }

    // Auto-run the deterministic reconcile once, when freshly-extracted drafts
    // still have no action, so the screen opens already grouped.
    if (doc.status != DocumentStatus.parsing && !_autoReconcileScheduled) {
      final needs = drafts.any((d) =>
          d.status == DocTxStatus.staged && !d.isDeleteCandidate && d.reconcileAction == null);
      if (needs) {
        _autoReconcileScheduled = true;
        final captured = doc;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(documentReconcilerProvider).reconcile(captured);
        });
      }
    }

    final existingById = {for (final e in ref.watch(transactionsProvider)) e.id: e};

    final applied = drafts.where((d) => d.isImported).toList();
    final pending =
        drafts.where((d) => !d.isImported && d.status != DocTxStatus.discarded).toList();
    final groups = <ReconcileAction, List<DocumentTransaction>>{};
    for (final d in pending) {
      (groups[d.reconcileAction ?? ReconcileAction.add] ??= []).add(d);
    }
    // Applicable = selected pending rows whose action actually does something.
    final selectedApplicable = pending
        .where((d) =>
            d.selected &&
            (d.reconcileAction ?? ReconcileAction.add) != ReconcileAction.identical)
        .toList();

    final aiAvailable = ref.watch(aiServicesProvider) != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (pending.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (v) {
                final notifier = ref.read(documentTransactionsProvider(widget.documentId).notifier);
                if (v == 'all') notifier.setAllSelected(true);
                if (v == 'none') notifier.setAllSelected(false);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'all', child: Text('Seleccionar todo')),
                PopupMenuItem(value: 'none', child: Text('Quitar selección')),
              ],
            ),
        ],
      ),
      body: doc.status == DocumentStatus.parsing
          ? const _ParsingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 140),
              children: [
                _HeaderCard(doc: doc),
                const SizedBox(height: 12),
                _ReconcileControls(
                  doc: doc,
                  aiAvailable: aiAvailable,
                  aiBusy: _aiBusy,
                  onToggleSourceOfTruth: (v) => _toggleSourceOfTruth(doc!, v),
                  onAiReconcile: () => _runAiReconcile(doc!),
                ),
                const SizedBox(height: 12),
                if (pending.isEmpty && applied.isEmpty)
                  _EmptyExtraction(doc: doc)
                else ...[
                  for (final entry in _orderedGroups(groups)) ...[
                    _SectionLabel(text: '${_groupTitle(entry.key)} (${entry.value.length})'),
                    ...entry.value.map((d) => _DraftTile(
                          draft: d,
                          existing: d.matchTxId != null ? existingById[d.matchTxId] : null,
                          onToggle: () => ref
                              .read(documentTransactionsProvider(widget.documentId).notifier)
                              .setSelected(d.id, !d.selected),
                          onEdit: d.isDeleteCandidate ? null : () => _editDraft(d),
                        )),
                    const SizedBox(height: 8),
                  ],
                  if (applied.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _SectionLabel(text: 'Aplicados (${applied.length})'),
                    ...applied.map((d) {
                      // Undo can only truly revert add (remove the created
                      // movement) and delete (re-create it). An update
                      // overwrote the original in place without capturing it, so
                      // offer no misleading undo there.
                      final a = d.reconcileAction ?? ReconcileAction.add;
                      final canUndo =
                          a == ReconcileAction.add || a == ReconcileAction.delete;
                      return _DraftTile(
                        draft: d,
                        existing: d.matchTxId != null ? existingById[d.matchTxId] : null,
                        onToggle: null,
                        onEdit: null,
                        onUndo: canUndo ? () => _undo(d) : null,
                      );
                    }),
                  ],
                ],
              ],
            ),
      bottomNavigationBar: pending.isEmpty
          ? null
          : _ActionBar(
              selectedCount: selectedApplicable.length,
              busy: _busy,
              onImport: selectedApplicable.isEmpty ? null : () => _applyReconciliation(selectedApplicable),
              onDelete: selectedApplicable.isEmpty ? null : () => _discardSelected(selectedApplicable),
              onBulkEdit: selectedApplicable.isEmpty ? null : () => _bulkEdit(selectedApplicable),
            ),
    );
  }

  // ---- actions --------------------------------------------------------------

  /// Applies the selected rows per their reconcile action: `add` creates a new
  /// movement, `update` overwrites the matched existing one (preserving its
  /// kind/goal/paid/createdAt), `delete` removes the matched existing one.
  /// Destructive actions (update/delete) require an explicit confirmation.
  Future<void> _applyReconciliation(List<DocumentTransaction> selected) async {
    final adds = <DocumentTransaction>[];
    final updates = <DocumentTransaction>[];
    final deletes = <DocumentTransaction>[];
    for (final d in selected) {
      switch (d.reconcileAction ?? ReconcileAction.add) {
        case ReconcileAction.add:
          adds.add(d);
        case ReconcileAction.update:
          updates.add(d);
        case ReconcileAction.delete:
          deletes.add(d);
        case ReconcileAction.identical:
          break; // nothing to apply
      }
    }

    if (updates.isNotEmpty || deletes.isNotEmpty) {
      final lines = <String>[
        if (adds.isNotEmpty) '• Agregar ${adds.length}',
        if (updates.isNotEmpty) '• Actualizar ${updates.length} (sobrescribe los existentes)',
        if (deletes.isNotEmpty) '• Borrar ${deletes.length} de tus movimientos',
      ];
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Aplicar conciliación'),
          content: Text('${lines.join('\n')}\n\nEsta acción modifica tus movimientos reales.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Aplicar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    try {
      final txNotifier = ref.read(transactionsProvider.notifier);
      final currentTx = ref.read(transactionsProvider);
      final existingById = {for (final e in currentTx) e.id: e};
      // Hash → committed movement, to drop an `add` that already exists (e.g. an
      // overlapping statement imported since this document was reconciled).
      final committedByHash = <String, String>{};
      for (final e in currentTx) {
        committedByHash.putIfAbsent(
          DocumentTransaction.computeDedupeHash(
              date: e.date, amount: e.amount, title: e.title, type: e.type),
          () => e.id,
        );
      }
      final mem = ref.read(merchantMemoryProvider);

      final entries = <FinanceEntry>[]; // new + updated upserts (idempotent by id)
      final removeIds = <String>[];
      final addUpdatePairs = <(String draftId, String txId)>[];
      final deletePairs = <(String draftId, String txId)>[];
      final dupResolved = <DocumentTransaction>[]; // adds that already exist
      var addedCount = 0;

      for (final d in adds) {
        final hash = d.dedupeHash ??
            DocumentTransaction.computeDedupeHash(
                date: d.date, amount: d.amount, title: d.title, type: d.type);
        final existingId = committedByHash[hash];
        if (existingId != null) {
          // Already a real movement → don't create a duplicate; resolve the
          // draft to that movement as "identical" (undo-safe).
          dupResolved.add(d.copyWith(
            reconcileAction: ReconcileAction.identical,
            matchTxId: existingId,
            status: DocTxStatus.duplicate,
            selected: false,
          ));
          continue;
        }
        final entry = d.toFinanceEntry();
        entries.add(entry);
        addUpdatePairs.add((d.id, entry.id));
        addedCount++;
        mem.learn(d.title, categoryId: d.categoryId, categoryName: d.category);
      }
      for (final d in updates) {
        final ex = d.matchTxId != null ? existingById[d.matchTxId] : null;
        if (ex == null) {
          // The matched movement vanished → create it fresh instead.
          final entry = d.toFinanceEntry();
          entries.add(entry);
          addUpdatePairs.add((d.id, entry.id));
        } else {
          // Overwrite only the statement-known fields; keep kind/goal/paid/etc.
          // Only change account/category when the draft resolved an id, so the
          // visible name never desyncs from the id (which drives balances).
          final keepAccount = d.accountId == null || d.accountId!.isEmpty;
          final keepCategory = d.categoryId == null || d.categoryId!.isEmpty;
          final updated = ex.copyWith(
            title: d.title.trim().isEmpty ? d.category : d.title.trim(),
            amount: d.amount,
            category: keepCategory ? ex.category : d.category,
            categoryId: keepCategory ? ex.categoryId : d.categoryId,
            date: d.date,
            type: d.type,
            account: keepAccount ? ex.account : d.account,
            accountId: keepAccount ? ex.accountId : d.accountId,
            currency: d.currency,
            note: d.note,
            exchangeRate: effectiveMxnRate(d.currency),
          );
          entries.add(updated);
          addUpdatePairs.add((d.id, updated.id));
        }
        mem.learn(d.title, categoryId: d.categoryId, categoryName: d.category);
      }
      for (final d in deletes) {
        final txId = d.matchTxId;
        if (txId != null) {
          removeIds.add(txId);
          deletePairs.add((d.id, txId));
        }
      }

      final docNotifier = ref.read(documentTransactionsProvider(widget.documentId).notifier);
      // Mark add/update drafts imported right after their write (before the
      // destructive remove), so a failure mid-way can't duplicate them on retry.
      if (entries.isNotEmpty) txNotifier.addBatch(entries);
      if (addUpdatePairs.isNotEmpty) docNotifier.markImportedBatch(addUpdatePairs);
      if (removeIds.isNotEmpty) txNotifier.removeBatch(removeIds);
      if (deletePairs.isNotEmpty) docNotifier.markImportedBatch(deletePairs);
      if (dupResolved.isNotEmpty) {
        ref.read(documentTransactionsRepositoryProvider).insertBatch(dupResolved);
        docNotifier.load();
      }

      _refreshDocCounts();
      if (mounted) {
        final parts = <String>[
          if (addedCount > 0) '$addedCount nuevos',
          if (updates.isNotEmpty) '${updates.length} actualizados',
          if (deletes.isNotEmpty) '${deletes.length} borrados',
          if (dupResolved.isNotEmpty) '${dupResolved.length} ya existían',
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(parts.isEmpty ? 'Sin cambios' : 'Aplicado: ${parts.join(' · ')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al aplicar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Enables/disables source-of-truth mode for the document, persisting the
  /// inferred scope (account + date range) and re-running the reconcile so the
  /// delete sweep regenerates (or clears).
  Future<void> _toggleSourceOfTruth(NexoDocument doc, bool enabled) async {
    final reconciler = ref.read(documentReconcilerProvider);
    final docsNotifier = ref.read(documentsProvider.notifier);

    if (!enabled) {
      docsNotifier.setSourceOfTruth(doc.id, false);
      final updated = docsNotifier.byId(doc.id);
      if (updated != null) reconciler.reconcile(updated); // clears delete candidates
      return;
    }

    final drafts = ref.read(documentTransactionsProvider(widget.documentId));
    final scope = DocumentReconciler.inferScope(drafts);
    if (scope.from == null || scope.to == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay movimientos para definir el alcance.')),
        );
      }
      return;
    }
    var accountId = scope.singleAccountId;
    if (accountId == null) {
      accountId = await _pickScopeAccount();
      if (accountId == null) return; // cancelled
    }

    // Bound the range to what the document says about THIS account — not the
    // whole document's span across every account it touches.
    final range = DocumentReconciler.scopeRangeForAccount(drafts, accountId);
    if (range.from == null || range.to == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El documento no tiene movimientos de esa cuenta.')),
        );
      }
      return;
    }

    docsNotifier.setSourceOfTruth(doc.id, true,
        accountId: accountId, from: range.from, to: range.to);
    final updated = docsNotifier.byId(doc.id);
    if (updated != null) reconciler.reconcile(updated);
    if (mounted) {
      final n = ref
          .read(documentTransactionsProvider(widget.documentId))
          .where((d) => d.isDeleteCandidate)
          .length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n == 0
              ? 'Sin movimientos a borrar en el alcance.'
              : '$n movimiento(s) marcados para borrar.'),
        ),
      );
    }
  }

  /// Asks the user which account the document's scope covers when its drafts map
  /// to more than one (or none).
  Future<String?> _pickScopeAccount() async {
    final accounts = ref.read(activeAccountsProvider);
    if (accounts.isEmpty) return null;
    return showDialog<String>(
      context: context,
      builder: (dialogCtx) => SimpleDialog(
        title: const Text('¿De qué cuenta es este documento?'),
        children: [
          for (final a in accounts)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogCtx, a.id),
              child: Text(a.name),
            ),
        ],
      ),
    );
  }

  Future<void> _runAiReconcile(NexoDocument doc) async {
    setState(() => _aiBusy = true);
    try {
      final summary = await ref.read(documentReconcilerProvider).reconcileWithAi(doc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conciliado: ${summary.add} nuevos · '
                '${summary.update} a actualizar · ${summary.delete} a borrar'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al conciliar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  /// Removes the selected rows FROM THE DOCUMENT only (discards drafts / drops a
  /// delete-candidate so the existing movement is kept). Never touches real
  /// movements — that is what [_applyReconciliation] does.
  Future<void> _discardSelected(List<DocumentTransaction> selected) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Quitar del documento'),
        content: Text('¿Quitar ${selected.length} movimientos de la lista? '
            'No se modifican tus movimientos reales.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Quitar')),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(documentTransactionsProvider(widget.documentId).notifier).deleteBatch([for (final d in selected) d.id]);
    _refreshDocCounts();
  }

  Future<void> _bulkEdit(List<DocumentTransaction> selected) async {
    final categories = ref.read(activeCategoriesProvider);
    final accounts = ref.read(activeAccountsProvider);
    final result = await showModalBottomSheet<({String? categoryId, String? categoryName, String? accountId, String? accountName, EntryType? type})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _BulkEditSheet(
        categories: [for (final c in categories) (id: c.id, name: c.name)],
        accounts: [for (final a in accounts) (id: a.id, name: a.name)],
      ),
    );
    if (result == null) return;
    final notifier = ref.read(documentTransactionsProvider(widget.documentId).notifier);
    // Bulk edit only makes sense for the document's own drafts, not for
    // delete-candidate rows (which mirror an existing movement).
    for (final d in selected.where((d) => !d.isDeleteCandidate)) {
      notifier.update(d.copyWith(
        category: result.categoryName,
        categoryId: result.categoryId,
        account: result.accountName,
        accountId: result.accountId,
        type: result.type,
      ));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Actualizados ${selected.where((d) => !d.isDeleteCandidate).length} movimientos')),
      );
    }
  }

  /// Reverts an applied row. `add` removes the created movement; `delete`
  /// re-creates the removed one (best-effort; transfers were never swept).
  /// `update` overwrote the original in place, so it can only be re-staged.
  Future<void> _undo(DocumentTransaction d) async {
    final txNotifier = ref.read(transactionsProvider.notifier);
    switch (d.reconcileAction ?? ReconcileAction.add) {
      case ReconcileAction.add:
        final txId = d.transactionId;
        if (txId != null) txNotifier.remove(txId);
      case ReconcileAction.delete:
        txNotifier.add(d.toFinanceEntry().copyWith(id: d.matchTxId));
      case ReconcileAction.update:
      case ReconcileAction.identical:
        break; // prior values weren't captured; just re-stage below
    }
    ref.read(documentTransactionsProvider(widget.documentId).notifier).setStatus(d.id, DocTxStatus.staged);
    _refreshDocCounts();
  }

  Future<void> _editDraft(DocumentTransaction d) async {
    final categories = ref.read(activeCategoriesProvider);
    final accounts = ref.read(activeAccountsProvider);
    final updated = await showModalBottomSheet<DocumentTransaction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _EditDraftSheet(
        draft: d,
        categories: [for (final c in categories) (id: c.id, name: c.name)],
        accounts: [for (final a in accounts) (id: a.id, name: a.name)],
      ),
    );
    if (updated != null) {
      ref.read(documentTransactionsProvider(widget.documentId).notifier).update(updated);
    }
  }

  /// Recomputes the document's tx/imported counts + status from its drafts.
  /// Delete-candidate rows are synthetic (they mirror existing movements, not
  /// extracted ones) so they don't count toward the document's totals.
  void _refreshDocCounts() {
    final drafts = ref.read(documentTransactionsProvider(widget.documentId));
    final active = drafts
        .where((d) => d.status != DocTxStatus.discarded && !d.isDeleteCandidate)
        .toList();
    final importedCount = active.where((d) => d.isImported).length;
    final repo = ref.read(documentsRepositoryProvider);
    repo.setCounts(widget.documentId, txCount: active.length, importedCount: importedCount);
    final status = active.isEmpty
        ? DocumentStatus.parsed
        : importedCount == active.length
            ? DocumentStatus.imported
            : importedCount > 0
                ? DocumentStatus.partial
                : DocumentStatus.parsed;
    repo.updateStatus(widget.documentId, status);
    ref.read(documentsProvider.notifier).load();
  }
}

// ---- widgets ----------------------------------------------------------------

class _ParsingView extends StatelessWidget {
  const _ParsingView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Extrayendo movimientos…'),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.doc});
  final NexoDocument doc;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = doc.txCount - doc.importedCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Stat(label: 'Extraídos', value: '${doc.txCount}'),
                _Stat(label: 'Por importar', value: '$pending'),
                _Stat(label: 'Importados', value: '${doc.importedCount}'),
              ],
            ),
            if (doc.status == DocumentStatus.partial) ...[
              const SizedBox(height: 8),
              Text('Algunas páginas no se pudieron leer por completo.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Text(text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

class _EmptyExtraction extends StatelessWidget {
  const _EmptyExtraction({required this.doc});
  final NexoDocument doc;
  @override
  Widget build(BuildContext context) {
    final failed = doc.status == DocumentStatus.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(failed ? Icons.error_outline_rounded : Icons.search_off_rounded,
                size: 34, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(failed ? 'No se pudo procesar' : 'Sin movimientos detectados',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(failed ? (doc.error ?? 'Inténtalo con otro documento.') : 'No se encontraron movimientos en el documento.',
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    this.existing,
    this.onToggle,
    this.onEdit,
    this.onUndo,
  });

  final DocumentTransaction draft;

  /// The matched existing movement, for showing the before→after on `update`
  /// and the target on `delete`.
  final FinanceEntry? existing;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = draft.type == EntryType.expense;
    final action = draft.reconcileAction ?? ReconcileAction.add;
    final accent = _actionColor(action, scheme);
    final amountColor =
        action == ReconcileAction.delete ? scheme.error : (isExpense ? scheme.error : scheme.primary);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: onToggle == null
            ? Icon(_actionIcon(action), color: accent)
            : Checkbox(value: draft.selected, onChanged: (_) => onToggle!()),
        title: Text(draft.title,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${draft.category} · ${draft.account} · ${DateFormat.yMMMd('es_MX').format(draft.date)}'),
            if (action == ReconcileAction.update && existing != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Antes: ${existing!.title} · '
                  '${formatMoney(existing!.amount, currency: existing!.currency)} · '
                  '${DateFormat.yMMMd('es_MX').format(existing!.date)}',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_actionLabel(action),
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${isExpense ? '-' : '+'}${formatMoney(draft.amount, currency: draft.currency)}',
              style: TextStyle(fontWeight: FontWeight.w900, color: amountColor),
            ),
            if (onEdit != null)
              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit, tooltip: 'Editar')
            else if (onUndo != null)
              IconButton(icon: const Icon(Icons.undo_rounded), onPressed: onUndo, tooltip: 'Deshacer'),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.selectedCount,
    required this.busy,
    required this.onImport,
    required this.onDelete,
    required this.onBulkEdit,
  });

  final int selectedCount;
  final bool busy;
  final VoidCallback? onImport;
  final VoidCallback? onDelete;
  final VoidCallback? onBulkEdit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.playlist_remove_rounded),
                  tooltip: 'Quitar del documento',
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: busy ? null : onBulkEdit,
                  icon: const Icon(Icons.edit_note_rounded),
                  tooltip: 'Editar en lote',
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onImport,
                    icon: busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download_done_rounded),
                    label: Text('Aplicar ($selectedCount)'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

typedef _NamedRef = ({String id, String name});

String? _idForName(List<_NamedRef> list, String? name) {
  if (name == null) return null;
  for (final e in list) {
    if (e.name == name) return e.id;
  }
  return null;
}

/// Orders the reconcile groups for display: actionable first, info last.
List<MapEntry<ReconcileAction, List<DocumentTransaction>>> _orderedGroups(
    Map<ReconcileAction, List<DocumentTransaction>> groups) {
  const order = [
    ReconcileAction.add,
    ReconcileAction.update,
    ReconcileAction.delete,
    ReconcileAction.identical,
  ];
  return [
    for (final a in order)
      if ((groups[a]?.isNotEmpty ?? false)) MapEntry(a, groups[a]!),
  ];
}

String _groupTitle(ReconcileAction a) => switch (a) {
      ReconcileAction.add => 'Nuevos',
      ReconcileAction.update => 'Actualizar',
      ReconcileAction.delete => 'Borrar de la app',
      ReconcileAction.identical => 'Sin cambios',
    };

String _actionLabel(ReconcileAction a) => switch (a) {
      ReconcileAction.add => 'Nuevo movimiento',
      ReconcileAction.update => 'Actualiza un movimiento existente',
      ReconcileAction.delete => 'En la app, no en el documento → borrar',
      ReconcileAction.identical => 'Ya existe (sin cambios)',
    };

IconData _actionIcon(ReconcileAction a) => switch (a) {
      ReconcileAction.add => Icons.add_circle_rounded,
      ReconcileAction.update => Icons.sync_rounded,
      ReconcileAction.delete => Icons.delete_rounded,
      ReconcileAction.identical => Icons.check_circle_rounded,
    };

Color _actionColor(ReconcileAction a, ColorScheme scheme) => switch (a) {
      ReconcileAction.add => scheme.primary,
      ReconcileAction.update => scheme.tertiary,
      ReconcileAction.delete => scheme.error,
      ReconcileAction.identical => scheme.onSurfaceVariant,
    };

/// Source-of-truth toggle + AI reconcile trigger, shown under the header.
class _ReconcileControls extends ConsumerWidget {
  const _ReconcileControls({
    required this.doc,
    required this.aiAvailable,
    required this.aiBusy,
    required this.onToggleSourceOfTruth,
    required this.onAiReconcile,
  });

  final NexoDocument doc;
  final bool aiAvailable;
  final bool aiBusy;
  final ValueChanged<bool> onToggleSourceOfTruth;
  final VoidCallback onAiReconcile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = ref.watch(activeAccountsProvider);
    String? accountName;
    for (final a in accounts) {
      if (a.id == doc.scopeAccountId) {
        accountName = a.name;
        break;
      }
    }
    final hasRange = doc.scopeFrom != null && doc.scopeTo != null;
    final scopeText = (doc.isSourceOfTruth && accountName != null && hasRange)
        ? 'Alcance: $accountName · '
            '${DateFormat.yMMMd('es_MX').format(doc.scopeFrom!)} – '
            '${DateFormat.yMMMd('es_MX').format(doc.scopeTo!)}'
        : 'Si lo activas, los movimientos de esa cuenta y periodo que no estén '
            'en el documento se proponen para borrar.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              value: doc.isSourceOfTruth,
              onChanged: onToggleSourceOfTruth,
              title: const Text('Fuente de la verdad',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(scopeText, style: theme.textTheme.bodySmall),
              secondary: Icon(Icons.verified_rounded,
                  color: doc.isSourceOfTruth ? theme.colorScheme.primary : null),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      aiAvailable
                          ? 'Empareja movimientos parecidos con IA.'
                          : 'Activa la IA en Ajustes para emparejado difuso.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: (aiAvailable && !aiBusy) ? onAiReconcile : null,
                    icon: aiBusy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Conciliar con IA'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditDraftSheet extends StatefulWidget {
  const _EditDraftSheet({required this.draft, required this.categories, required this.accounts});

  final DocumentTransaction draft;
  final List<_NamedRef> categories;
  final List<_NamedRef> accounts;

  @override
  State<_EditDraftSheet> createState() => _EditDraftSheetState();
}

class _EditDraftSheetState extends State<_EditDraftSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _title;
  late final TextEditingController _note;
  late EntryType _type;
  late String _category;
  late String? _categoryId;
  late String _account;
  late String? _accountId;
  late String _currency;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _amount = TextEditingController(text: d.amount.toStringAsFixed(2));
    _title = TextEditingController(text: d.title);
    _note = TextEditingController(text: d.note ?? '');
    _type = d.type;
    _category = d.category;
    _categoryId = d.categoryId;
    _account = d.account;
    _accountId = d.accountId;
    _currency = d.currency;
    _date = d.date;
  }

  @override
  void dispose() {
    _amount.dispose();
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  double? _parseAmount(String input) {
    final raw = input.trim().replaceAll(' ', '');
    if (raw.isEmpty) return null;
    if (raw.contains(',') && raw.contains('.')) return double.tryParse(raw.replaceAll(',', ''));
    if (raw.contains(',')) return double.tryParse(raw.replaceAll(',', '.'));
    return double.tryParse(raw);
  }

  @override
  Widget build(BuildContext context) {
    final categoryNames = {widget.draft.category, for (final c in widget.categories) c.name}.toList();
    final accountNames = {widget.draft.account, for (final a in widget.accounts) a.name}.toList();
    final currencyOptions = {_currency, ...supportedCurrencies}.toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Editar movimiento',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            SegmentedButton<EntryType>(
              segments: const [
                ButtonSegment(value: EntryType.expense, label: Text('Gasto'), icon: Icon(Icons.arrow_upward_rounded)),
                ButtonSegment(value: EntryType.income, label: Text('Ingreso'), icon: Icon(Icons.arrow_downward_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Monto', prefixIcon: Icon(Icons.attach_money_rounded)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Concepto', prefixIcon: Icon(Icons.edit_note_rounded)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              items: [for (final c in categoryNames) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() {
                _category = v ?? _category;
                _categoryId = _idForName(widget.categories, _category);
              }),
              decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.label_outline_rounded)),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _account,
              isExpanded: true,
              items: [for (final a in accountNames) DropdownMenuItem(value: a, child: Text(a))],
              onChanged: (v) => setState(() {
                _account = v ?? _account;
                _accountId = _idForName(widget.accounts, _account);
              }),
              decoration: const InputDecoration(labelText: 'Cuenta', prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    items: [for (final c in currencyOptions) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _currency = v ?? _currency),
                    decoration: const InputDecoration(labelText: 'Moneda'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2015),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => _date = picked);
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(DateFormat.yMMMd('es_MX').format(_date)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Nota (opcional)', prefixIcon: Icon(Icons.sticky_note_2_outlined)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final amount = _parseAmount(_amount.text);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ingresa un monto válido')),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    widget.draft.copyWith(
                      amount: amount,
                      title: _title.text.trim().isEmpty ? _category : _title.text.trim(),
                      type: _type,
                      category: _category,
                      categoryId: _categoryId,
                      account: _account,
                      accountId: _accountId,
                      currency: _currency,
                      date: _date,
                      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                    ),
                  );
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Guardar cambios'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkEditSheet extends StatefulWidget {
  const _BulkEditSheet({required this.categories, required this.accounts});

  final List<_NamedRef> categories;
  final List<_NamedRef> accounts;

  @override
  State<_BulkEditSheet> createState() => _BulkEditSheetState();
}

class _BulkEditSheetState extends State<_BulkEditSheet> {
  String? _category;
  String? _account;
  EntryType? _type;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Editar en lote',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Aplica a todos los seleccionados. Deja en blanco lo que no quieras cambiar.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _category,
            isExpanded: true,
            items: [for (final c in widget.categories) DropdownMenuItem(value: c.name, child: Text(c.name))],
            onChanged: (v) => setState(() => _category = v),
            decoration: const InputDecoration(labelText: 'Categoría', prefixIcon: Icon(Icons.label_outline_rounded)),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _account,
            isExpanded: true,
            items: [for (final a in widget.accounts) DropdownMenuItem(value: a.name, child: Text(a.name))],
            onChanged: (v) => setState(() => _account = v),
            decoration: const InputDecoration(labelText: 'Cuenta', prefixIcon: Icon(Icons.account_balance_wallet_outlined)),
          ),
          const SizedBox(height: 10),
          SegmentedButton<EntryType?>(
            emptySelectionAllowed: true,
            segments: const [
              ButtonSegment(value: EntryType.expense, label: Text('Gasto')),
              ButtonSegment(value: EntryType.income, label: Text('Ingreso')),
            ],
            selected: _type == null ? <EntryType?>{} : {_type},
            onSelectionChanged: (s) => setState(() => _type = s.isEmpty ? null : s.first),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final catId = _idForName(widget.categories, _category);
                final accId = _idForName(widget.accounts, _account);
                Navigator.pop(context, (
                  categoryId: catId,
                  categoryName: _category,
                  accountId: accId,
                  accountName: _account,
                  type: _type,
                ));
              },
              child: const Text('Aplicar'),
            ),
          ),
        ],
      ),
    );
  }
}
