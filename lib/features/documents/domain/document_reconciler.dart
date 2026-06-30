import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/util/ids.dart';
import '../../ai/domain/ai_providers.dart';
import '../../ai/domain/ai_services.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/domain/transactions_provider.dart';
import 'document.dart';
import 'document_transaction.dart';
import 'documents_provider.dart';

/// The slice of data a document covers, used to bound a source-of-truth delete
/// sweep. Inferred from the document's drafts (resolved accounts + date range).
class DocScope {
  const DocScope({required this.accountIds, this.from, this.to});

  final Set<String> accountIds;
  final DateTime? from;
  final DateTime? to;

  /// Non-null only when the document maps to exactly one account — the
  /// requirement for an automatic delete sweep (a statement = one account).
  String? get singleAccountId => accountIds.length == 1 ? accountIds.first : null;

  /// True when the scope is unambiguous enough to bound a delete sweep.
  bool get isComplete => singleAccountId != null && from != null && to != null;
}

/// Tally of what the reconciler decided, surfaced to the UI.
class ReconcileSummary {
  const ReconcileSummary({this.add = 0, this.update = 0, this.identical = 0, this.delete = 0});

  final int add;
  final int update;
  final int identical;
  final int delete;

  int get total => add + update + identical + delete;
}

/// The full outcome of a deterministic (optionally AI-refined) reconcile: the
/// document's drafts re-stamped with their action, the synthetic delete
/// candidates, and a tally. Pure data — [DocumentReconciler.planDeterministic]
/// builds it without touching the database, so it is unit-testable.
class ReconcilePlan {
  ReconcilePlan({
    required this.updatedDrafts,
    required this.deleteCandidates,
    required this.summary,
  });

  /// The pending drafts with `reconcileAction`/`matchTxId` assigned.
  final List<DocumentTransaction> updatedDrafts;

  /// Synthetic rows for in-scope existing movements no draft matched.
  final List<DocumentTransaction> deleteCandidates;

  final ReconcileSummary summary;
}

/// Matches a document's extracted drafts against the movements already in the
/// app and classifies each as add / update / identical, then (when the document
/// is the source of truth) flags existing movements inside its scope that no
/// draft matched as deletion candidates. Deterministic first; an optional AI
/// pass resolves the fuzzy residue. Mirrors [DocumentParser]: it writes through
/// the staging repo and reloads the watching providers.
class DocumentReconciler {
  DocumentReconciler(this.ref);

  final Ref ref;

  /// How many days apart two movements may be and still match deterministically.
  static const _nearDays = 3;

  /// Extra days around the scope to consider existing movements as AI match
  /// candidates (bounds tokens without missing a movement posted a few days off).
  static const _candidateMarginDays = 5;

  /// Infers the scope (accounts + date range) the [drafts] cover. Delete
  /// candidates and already-imported drafts are ignored — only the document's
  /// own pending movements define scope.
  static DocScope inferScope(List<DocumentTransaction> drafts) {
    final accountIds = <String>{};
    DateTime? from;
    DateTime? to;
    for (final d in drafts) {
      if (d.isDeleteCandidate || d.isImported) continue;
      final acc = d.accountId;
      if (acc != null && acc.isNotEmpty) accountIds.add(acc);
      final day = _dateOnly(d.date);
      if (from == null || day.isBefore(from)) from = day;
      if (to == null || day.isAfter(to)) to = day;
    }
    return DocScope(accountIds: accountIds, from: from, to: to);
  }

  /// The date range the [drafts] of a single [accountId] cover, used to bound a
  /// source-of-truth sweep to exactly what the document says about that account
  /// (not the whole document's span across all accounts).
  static ({DateTime? from, DateTime? to}) scopeRangeForAccount(
      List<DocumentTransaction> drafts, String accountId) {
    DateTime? from;
    DateTime? to;
    for (final d in drafts) {
      if (d.isDeleteCandidate || d.isImported) continue;
      if (d.accountId != accountId) continue;
      final day = _dateOnly(d.date);
      if (from == null || day.isBefore(from)) from = day;
      if (to == null || day.isAfter(to)) to = day;
    }
    return (from: from, to: to);
  }

  /// Pure deterministic plan. Does not touch the database — used by [reconcile]
  /// and by tests.
  static ReconcilePlan planDeterministic({
    required NexoDocument doc,
    required List<DocumentTransaction> drafts,
    required List<FinanceEntry> existing,
  }) {
    final det = _classify(doc, drafts, existing);
    return _buildPlan(doc, det);
  }

  /// Deterministic reconcile against the live providers. Returns the tally and
  /// persists the plan.
  ReconcileSummary reconcile(NexoDocument doc) {
    final repo = ref.read(documentTransactionsRepositoryProvider);
    final drafts = repo.forDocument(doc.id);
    final existing = ref.read(transactionsProvider);
    final det = _classify(doc, drafts, existing);
    final plan = _buildPlan(doc, det);
    _persistPlan(doc, plan);
    return plan.summary;
  }

  /// Runs the deterministic pass, then asks the AI to resolve the drafts still
  /// classified as `add` against the unmatched existing movements (catching
  /// renamed merchants / shifted dates / rounded amounts). Falls back to the
  /// deterministic result if the AI is unavailable or errors.
  Future<ReconcileSummary> reconcileWithAi(NexoDocument doc) async {
    final repo = ref.read(documentTransactionsRepositoryProvider);
    final drafts = repo.forDocument(doc.id);
    final existing = ref.read(transactionsProvider);

    final det = _classify(doc, drafts, existing);

    final ai = ref.read(aiServicesProvider);
    if (ai != null) {
      try {
        await _aiRefine(det, ai);
      } catch (_) {
        // Keep the deterministic result on any AI failure.
      }
    }
    final plan = _buildPlan(doc, det);
    _persistPlan(doc, plan);
    return plan.summary;
  }

  // ---- core -----------------------------------------------------------------

  static _ClassifyResult _classify(
    NexoDocument doc,
    List<DocumentTransaction> drafts,
    List<FinanceEntry> existing,
  ) {
    // The document's own, not-yet-applied movements get (re)classified. We
    // include the `duplicate` state too so a re-run re-derives identical
    // matches (and re-claims their existing movement) instead of leaving it
    // orphaned — otherwise a previously-matched movement could wrongly resurface
    // as a delete candidate.
    final pending = [
      for (final d in drafts)
        if ((d.status == DocTxStatus.staged || d.status == DocTxStatus.duplicate) &&
            !d.isDeleteCandidate)
          d,
    ];

    // Existing movements eligible to be matched: realized standard movements
    // (not goal/transfer, not planned). Matching a posted statement row to a
    // planned (paid=false) entry would leave the real posting out of balances,
    // so planned entries are excluded here exactly like in the delete sweep.
    final matchable = [
      for (final e in existing)
        if (e.kind == EntryKind.standard && e.goalId == null && e.paid) e,
    ];
    final existingByHash = <String, List<FinanceEntry>>{};
    for (final e in matchable) {
      final h = DocumentTransaction.computeDedupeHash(
        date: e.date,
        amount: e.amount,
        title: e.title,
        type: e.type,
      );
      (existingByHash[h] ??= []).add(e);
    }

    final used = <String>{}; // existing ids already claimed by a draft
    // Movements this document already accounts for via an applied row (an added
    // movement it created, or one it updated) must never be swept as "missing".
    for (final d in drafts) {
      if (d.isDeleteCandidate || d.status != DocTxStatus.imported) continue;
      final tx = d.transactionId;
      if (tx != null && tx.isNotEmpty) used.add(tx);
      final mt = d.matchTxId;
      if (mt != null && mt.isNotEmpty) used.add(mt);
    }

    // Remember the user's keep/select decision on existing delete candidates so
    // a re-run doesn't silently re-select a movement they chose to keep.
    final priorDeleteSelection = <String, bool>{};
    for (final d in drafts) {
      if (d.isDeleteCandidate && d.status == DocTxStatus.staged && d.matchTxId != null) {
        priorDeleteSelection[d.matchTxId!] = d.selected;
      }
    }

    final decisions = <String, _Decision>{}; // draftId → decision

    for (final d in pending) {
      final hash = d.dedupeHash ??
          DocumentTransaction.computeDedupeHash(
            date: d.date,
            amount: d.amount,
            title: d.title,
            type: d.type,
          );

      // 1) Exact match → identical (already in the app, nothing to change).
      //    Account-aware: a same-amount/date movement on a *different* account
      //    is a different movement, so only match within the draft's account
      //    when it resolved one.
      final exact = _firstMatching(existingByHash[hash], used, d.accountId);
      if (exact != null) {
        used.add(exact.id);
        decisions[d.id] = _Decision(ReconcileAction.identical, exact.id);
        continue;
      }

      // 2) Near match (same amount + type, date within a few days, same account
      //    when the draft resolved one) → update.
      final near = _nearMatch(d, matchable, used);
      if (near != null) {
        used.add(near.id);
        decisions[d.id] = _Decision(ReconcileAction.update, near.id);
        continue;
      }

      // 3) Otherwise it's new (the AI pass may still rescue it into an update).
      decisions[d.id] = const _Decision(ReconcileAction.add, null);
    }

    return _ClassifyResult(
      pending: pending,
      matchable: matchable,
      used: used,
      decisions: decisions,
      priorDeleteSelection: priorDeleteSelection,
    );
  }

  /// Asks the AI to pair the still-`add` drafts with unmatched existing
  /// movements in the scope window, mutating [det] in place.
  Future<void> _aiRefine(_ClassifyResult det, AiServices ai) async {
    final residualDrafts = [
      for (final d in det.pending)
        if (det.decisions[d.id]?.action == ReconcileAction.add) d,
    ];
    if (residualDrafts.isEmpty) return;

    final scope = inferScope(det.pending);
    final candidates = [
      for (final e in det.matchable)
        if (!det.used.contains(e.id) && _inCandidateWindow(e, scope)) e,
    ];
    if (candidates.isEmpty) return;

    final matches = await ai.reconcileStatement(
      drafts: [
        for (final d in residualDrafts)
          ReconcileItem(
            title: d.title,
            amount: d.amount,
            type: d.type,
            dateIso: _isoDay(d.date),
          ),
      ],
      existing: [
        for (final e in candidates)
          ReconcileItem(
            title: e.title,
            amount: e.amount,
            type: e.type,
            dateIso: _isoDay(e.date),
          ),
      ],
    );

    for (final m in matches) {
      if (m.draftIndex < 0 || m.draftIndex >= residualDrafts.length) continue;
      if (m.verdict == ReconcileVerdict.isNew) continue;
      final ei = m.existingIndex;
      if (ei == null || ei < 0 || ei >= candidates.length) continue;
      final existingId = candidates[ei].id;
      if (det.used.contains(existingId)) continue; // don't double-claim
      det.used.add(existingId);
      final draft = residualDrafts[m.draftIndex];
      final action = m.verdict == ReconcileVerdict.same
          ? ReconcileAction.identical
          : ReconcileAction.update;
      det.decisions[draft.id] = _Decision(action, existingId, confidence: m.confidence);
    }
  }

  static ReconcilePlan _buildPlan(NexoDocument doc, _ClassifyResult det) {
    // Within a source-of-truth scope, reclassify an `add` draft as an `update`
    // when an unmatched existing movement on the same account has the same
    // amount + type (any date in range). Otherwise the same real movement would
    // be both inserted (as new) and proposed for deletion — a near-duplicate.
    _looseScopedMatch(doc, det);

    final updated = <DocumentTransaction>[];
    for (final d in det.pending) {
      final dec = det.decisions[d.id] ?? const _Decision(ReconcileAction.add, null);
      updated.add(d.copyWith(
        reconcileAction: dec.action,
        matchTxId: dec.matchTxId,
        matchConfidence: dec.confidence,
        // Identical movements need no action → deselect. For the rest, preserve
        // the user's prior checkbox state across re-runs instead of forcing it
        // back on (which would silently re-include things they deselected).
        selected: dec.action == ReconcileAction.identical ? false : d.selected,
        status: dec.action == ReconcileAction.identical
            ? DocTxStatus.duplicate
            : DocTxStatus.staged,
      ));
    }

    final deletes = _deleteCandidates(doc, det);

    final summary = ReconcileSummary(
      add: det.decisions.values.where((d) => d.action == ReconcileAction.add).length,
      update: det.decisions.values.where((d) => d.action == ReconcileAction.update).length,
      identical: det.decisions.values.where((d) => d.action == ReconcileAction.identical).length,
      delete: deletes.length,
    );

    return ReconcilePlan(updatedDrafts: updated, deleteCandidates: deletes, summary: summary);
  }

  void _persistPlan(NexoDocument doc, ReconcilePlan plan) {
    final repo = ref.read(documentTransactionsRepositoryProvider);
    repo.clearPendingDeleteCandidates(doc.id);
    if (plan.updatedDrafts.isNotEmpty) repo.insertBatch(plan.updatedDrafts);
    if (plan.deleteCandidates.isNotEmpty) repo.insertBatch(plan.deleteCandidates);
    // Only the drafts changed (reconcile never touches the `documents` table),
    // so reload just this document's draft family — not `documentsProvider`,
    // which the documents-list route depends on and which, if mutated while
    // that route is transitioning out, trips a framework assertion.
    ref.read(documentTransactionsProvider(doc.id).notifier).load();
  }

  /// Existing movements inside the document's persisted scope that no draft
  /// matched — only when the document is flagged the source of truth and the
  /// scope is fully resolved.
  static List<DocumentTransaction> _deleteCandidates(NexoDocument doc, _ClassifyResult det) {
    if (!doc.isSourceOfTruth) return const [];
    final accountId = doc.scopeAccountId;
    final from = doc.scopeFrom;
    final to = doc.scopeTo;
    if (accountId == null || from == null || to == null) return const [];

    final now = DateTime.now();
    final fromDay = _dateOnly(from);
    final toDay = _dateOnly(to);
    final out = <DocumentTransaction>[];
    for (final e in det.matchable) {
      if (!e.paid) continue; // never sweep planned/unrealized movements
      if (e.accountId != accountId) continue;
      if (det.used.contains(e.id)) continue;
      final day = _dateOnly(e.date);
      if (day.isBefore(fromDay) || day.isAfter(toDay)) continue;
      out.add(DocumentTransaction(
        id: newId('dtx'),
        documentId: doc.id,
        title: e.title,
        amount: e.amount,
        category: e.category,
        categoryId: e.categoryId,
        date: e.date,
        type: e.type,
        account: e.account,
        accountId: e.accountId,
        currency: e.currency,
        note: e.note,
        confidence: 0,
        // Destructive by nature: default to NOT selected so a delete only
        // happens when the user explicitly opts in. Preserve their prior
        // choice across re-runs.
        selected: det.priorDeleteSelection[e.id] ?? false,
        status: DocTxStatus.staged,
        reconcileAction: ReconcileAction.delete,
        matchTxId: e.id,
        dedupeHash: DocumentTransaction.computeDedupeHash(
          date: e.date,
          amount: e.amount,
          title: e.title,
          type: e.type,
        ),
        createdAt: now,
      ));
    }
    return out;
  }

  /// Within a fully-resolved source-of-truth scope, reclassify `add` drafts as
  /// `update` of an unmatched existing movement on the same account with the
  /// same amount + type (any date inside the range). Prevents the delete sweep
  /// from proposing to remove a movement that an `add` draft re-creates.
  static void _looseScopedMatch(NexoDocument doc, _ClassifyResult det) {
    if (!doc.isSourceOfTruth) return;
    final accountId = doc.scopeAccountId;
    final from = doc.scopeFrom;
    final to = doc.scopeTo;
    if (accountId == null || from == null || to == null) return;
    final fromDay = _dateOnly(from);
    final toDay = _dateOnly(to);

    final inScope = [
      for (final e in det.matchable)
        if (e.accountId == accountId &&
            !det.used.contains(e.id) &&
            !_dateOnly(e.date).isBefore(fromDay) &&
            !_dateOnly(e.date).isAfter(toDay))
          e,
    ];
    if (inScope.isEmpty) return;

    for (final d in det.pending) {
      if (det.decisions[d.id]?.action != ReconcileAction.add) continue;
      if (d.accountId != accountId) continue;
      final amount = roundMoney(d.amount);
      for (final e in inScope) {
        if (det.used.contains(e.id)) continue;
        if (e.type != d.type) continue;
        if (roundMoney(e.amount) != amount) continue;
        det.used.add(e.id);
        det.decisions[d.id] = _Decision(ReconcileAction.update, e.id);
        break;
      }
    }
  }

  // ---- helpers --------------------------------------------------------------

  static FinanceEntry? _nearMatch(DocumentTransaction d, List<FinanceEntry> matchable, Set<String> used) {
    final amount = roundMoney(d.amount);
    FinanceEntry? best;
    int? bestDelta;
    for (final e in matchable) {
      if (used.contains(e.id)) continue;
      if (e.type != d.type) continue;
      if (roundMoney(e.amount) != amount) continue;
      if (d.accountId != null && d.accountId!.isNotEmpty && e.accountId != d.accountId) continue;
      final delta = _dateOnly(e.date).difference(_dateOnly(d.date)).inDays.abs();
      if (delta > _nearDays) continue;
      if (bestDelta == null || delta < bestDelta) {
        best = e;
        bestDelta = delta;
      }
    }
    return best;
  }

  static bool _inCandidateWindow(FinanceEntry e, DocScope scope) {
    if (scope.accountIds.isNotEmpty &&
        (e.accountId == null || !scope.accountIds.contains(e.accountId))) {
      return false;
    }
    final from = scope.from;
    final to = scope.to;
    if (from == null || to == null) return true;
    final day = _dateOnly(e.date);
    return !day.isBefore(_dateOnly(from).subtract(const Duration(days: _candidateMarginDays))) &&
        !day.isAfter(_dateOnly(to).add(const Duration(days: _candidateMarginDays)));
  }

  /// First unused entry that also matches [accountId] when the draft resolved
  /// one (null accountId on the draft falls back to any account).
  static FinanceEntry? _firstMatching(
      List<FinanceEntry>? list, Set<String> used, String? accountId) {
    if (list == null) return null;
    for (final e in list) {
      if (used.contains(e.id)) continue;
      if (accountId != null && accountId.isNotEmpty && e.accountId != accountId) continue;
      return e;
    }
    return null;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _isoDay(DateTime d) => _dateOnly(d).toIso8601String().split('T').first;
}

class _Decision {
  const _Decision(this.action, this.matchTxId, {this.confidence});
  final ReconcileAction action;
  final String? matchTxId;
  final double? confidence;
}

class _ClassifyResult {
  _ClassifyResult({
    required this.pending,
    required this.matchable,
    required this.used,
    required this.decisions,
    required this.priorDeleteSelection,
  });

  final List<DocumentTransaction> pending;
  final List<FinanceEntry> matchable;
  final Set<String> used;
  final Map<String, _Decision> decisions;

  /// Existing-movement id → whether the user had the delete candidate selected
  /// before this re-run, so we don't clobber their keep/select choice.
  final Map<String, bool> priorDeleteSelection;
}

final documentReconcilerProvider =
    Provider<DocumentReconciler>((ref) => DocumentReconciler(ref));
