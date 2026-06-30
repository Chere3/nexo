import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/features/documents/domain/document.dart';
import 'package:nexo/features/documents/domain/document_reconciler.dart';
import 'package:nexo/features/documents/domain/document_transaction.dart';
import 'package:nexo/features/transactions/domain/transaction.dart';

FinanceEntry _tx({
  required String id,
  required double amount,
  required DateTime date,
  String title = 'Mov',
  EntryType type = EntryType.expense,
  String accountId = 'accB',
  EntryKind kind = EntryKind.standard,
  String? goalId,
  bool paid = true,
}) {
  return FinanceEntry(
    id: id,
    title: title,
    amount: amount,
    category: 'Cat',
    date: date,
    type: type,
    account: accountId,
    accountId: accountId,
    kind: kind,
    goalId: goalId,
    paid: paid,
  );
}

DocumentTransaction _draft({
  required String id,
  required double amount,
  required DateTime date,
  String title = 'Mov',
  EntryType type = EntryType.expense,
  String accountId = 'accB',
}) {
  return DocumentTransaction(
    id: id,
    documentId: 'doc1',
    title: title,
    amount: amount,
    date: date,
    type: type,
    account: accountId,
    accountId: accountId,
    createdAt: date,
  );
}

NexoDocument _doc({
  bool sourceOfTruth = false,
  String? scopeAccountId,
  DateTime? from,
  DateTime? to,
}) {
  final t = from ?? DateTime(2026, 5, 1);
  return NexoDocument(
    id: 'doc1',
    title: 'Estado de cuenta',
    sourceType: DocumentSourceType.pdf,
    isSourceOfTruth: sourceOfTruth,
    scopeAccountId: scopeAccountId,
    scopeFrom: from,
    scopeTo: to,
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  group('DocumentReconciler.planDeterministic', () {
    test('classifies identical / update / add', () {
      final d1 = DateTime(2026, 5, 3);
      final existing = [
        _tx(id: 'e1', amount: 120, date: d1, title: 'Uber'),
        _tx(id: 'e2', amount: 200, date: DateTime(2026, 5, 10), title: 'Renta'),
      ];
      final drafts = [
        _draft(id: 'd1', amount: 120, date: d1, title: 'Uber'), // exact → identical
        _draft(id: 'd2', amount: 200, date: DateTime(2026, 5, 11), title: 'Renta mayo'), // near → update
        _draft(id: 'd3', amount: 55, date: DateTime(2026, 5, 12), title: 'Café'), // none → add
      ];

      final plan = DocumentReconciler.planDeterministic(
        doc: _doc(),
        drafts: drafts,
        existing: existing,
      );
      final byId = {for (final u in plan.updatedDrafts) u.id: u};

      expect(byId['d1']!.reconcileAction, ReconcileAction.identical);
      expect(byId['d1']!.matchTxId, 'e1');
      expect(byId['d2']!.reconcileAction, ReconcileAction.update);
      expect(byId['d2']!.matchTxId, 'e2');
      expect(byId['d3']!.reconcileAction, ReconcileAction.add);
      expect(byId['d3']!.matchTxId, isNull);

      expect(plan.summary.identical, 1);
      expect(plan.summary.update, 1);
      expect(plan.summary.add, 1);
      expect(plan.deleteCandidates, isEmpty); // not source of truth
    });

    test('a draft on a different account does not match an existing one', () {
      final date = DateTime(2026, 5, 3);
      final existing = [_tx(id: 'e1', amount: 120, date: date, accountId: 'accB')];
      final drafts = [_draft(id: 'd1', amount: 120, date: date, accountId: 'accC')];

      final plan = DocumentReconciler.planDeterministic(
        doc: _doc(),
        drafts: drafts,
        existing: existing,
      );
      expect(plan.updatedDrafts.single.reconcileAction, ReconcileAction.add);
    });

    test('source-of-truth sweep is bounded by account + range and excludes '
        'transfers, unpaid and other accounts', () {
      final from = DateTime(2026, 5, 1);
      final to = DateTime(2026, 5, 31);
      final existing = [
        _tx(id: 'e1', amount: 120, date: DateTime(2026, 5, 3), title: 'Uber'), // matched → kept
        _tx(id: 'e2', amount: 999, date: DateTime(2026, 5, 15), title: 'Fantasma'), // unmatched, in scope → DELETE
        _tx(id: 'e3', amount: 50, date: DateTime(2026, 5, 15), accountId: 'accCash'), // other account → kept
        _tx(id: 'e4', amount: 300, date: DateTime(2026, 5, 20), kind: EntryKind.transfer), // transfer → kept
        _tx(id: 'e5', amount: 80, date: DateTime(2026, 5, 22), paid: false), // unpaid → kept
        _tx(id: 'e6', amount: 77, date: DateTime(2026, 6, 2)), // out of range → kept
      ];
      final drafts = [_draft(id: 'd1', amount: 120, date: DateTime(2026, 5, 3), title: 'Uber')];

      final plan = DocumentReconciler.planDeterministic(
        doc: _doc(sourceOfTruth: true, scopeAccountId: 'accB', from: from, to: to),
        drafts: drafts,
        existing: existing,
      );

      expect(plan.deleteCandidates.map((d) => d.matchTxId).toSet(), {'e2'});
      expect(plan.summary.delete, 1);
      expect(plan.updatedDrafts.single.reconcileAction, ReconcileAction.identical);
      for (final c in plan.deleteCandidates) {
        expect(c.reconcileAction, ReconcileAction.delete);
        expect(c.isDeleteCandidate, isTrue);
      }
    });

    test('movements the document already imported are not swept on re-run', () {
      final from = DateTime(2026, 5, 1);
      final to = DateTime(2026, 5, 31);
      final existing = [_tx(id: 'e1', amount: 120, date: DateTime(2026, 5, 3), title: 'Uber')];
      // A draft that was already applied as a new movement (transaction_id e1).
      final importedDraft = DocumentTransaction(
        id: 'd1',
        documentId: 'doc1',
        title: 'Uber',
        amount: 120,
        date: DateTime(2026, 5, 3),
        type: EntryType.expense,
        account: 'accB',
        accountId: 'accB',
        status: DocTxStatus.imported,
        reconcileAction: ReconcileAction.add,
        transactionId: 'e1',
        createdAt: DateTime(2026, 5, 3),
      );

      final plan = DocumentReconciler.planDeterministic(
        doc: _doc(sourceOfTruth: true, scopeAccountId: 'accB', from: from, to: to),
        drafts: [importedDraft],
        existing: existing,
      );
      expect(plan.deleteCandidates, isEmpty);
    });

    test('a posted draft does not match a planned (unpaid) movement', () {
      final date = DateTime(2026, 6, 1);
      final existing = [_tx(id: 'e1', amount: 8000, date: date, title: 'Renta', paid: false)];
      final drafts = [_draft(id: 'd1', amount: 8000, date: date, title: 'Renta')];
      final plan = DocumentReconciler.planDeterministic(
        doc: _doc(),
        drafts: drafts,
        existing: existing,
      );
      // The planned entry isn't matchable, so the real posting is a new movement.
      expect(plan.updatedDrafts.single.reconcileAction, ReconcileAction.add);
    });

    test('source-of-truth loosely matches add→update by account+amount, '
        'so the same movement is not both added and deleted', () {
      final from = DateTime(2026, 5, 1);
      final to = DateTime(2026, 5, 31);
      // Existing movement and a draft for the same movement that differ enough
      // (10 days apart, renamed) that deterministic near-matching fails.
      final existing = [_tx(id: 'e1', amount: 100, date: DateTime(2026, 5, 10), title: 'Comercio X')];
      final drafts = [_draft(id: 'd1', amount: 100, date: DateTime(2026, 5, 20), title: 'COMERCIO X SA')];

      final plan = DocumentReconciler.planDeterministic(
        doc: _doc(sourceOfTruth: true, scopeAccountId: 'accB', from: from, to: to),
        drafts: drafts,
        existing: existing,
      );
      expect(plan.updatedDrafts.single.reconcileAction, ReconcileAction.update);
      expect(plan.updatedDrafts.single.matchTxId, 'e1');
      expect(plan.deleteCandidates, isEmpty); // e1 claimed → never proposed for deletion
    });

    test('delete candidates default to deselected and preserve prior keep choice', () {
      final from = DateTime(2026, 5, 1);
      final to = DateTime(2026, 5, 31);
      final existing = [
        _tx(id: 'e2', amount: 999, date: DateTime(2026, 5, 15), title: 'Fantasma'),
        _tx(id: 'e3', amount: 50, date: DateTime(2026, 5, 16), title: 'Otro'),
      ];
      final doc = _doc(sourceOfTruth: true, scopeAccountId: 'accB', from: from, to: to);

      final plan1 = DocumentReconciler.planDeterministic(doc: doc, drafts: const [], existing: existing);
      expect(plan1.deleteCandidates.length, 2);
      expect(plan1.deleteCandidates.every((c) => c.selected == false), isTrue);

      // User selects the e2 candidate; re-run must keep that and e3's deselection.
      final priorE2 = plan1.deleteCandidates.firstWhere((c) => c.matchTxId == 'e2').copyWith(selected: true);
      final priorE3 = plan1.deleteCandidates.firstWhere((c) => c.matchTxId == 'e3');
      final plan2 = DocumentReconciler.planDeterministic(
        doc: doc,
        drafts: [priorE2, priorE3],
        existing: existing,
      );
      final byMatch = {for (final c in plan2.deleteCandidates) c.matchTxId: c};
      expect(byMatch['e2']!.selected, isTrue);
      expect(byMatch['e3']!.selected, isFalse);
    });

    test('a manually deselected add stays deselected on re-run', () {
      final existing = <FinanceEntry>[];
      final firstPass = DocumentReconciler.planDeterministic(
        doc: _doc(),
        drafts: [_draft(id: 'd1', amount: 30, date: DateTime(2026, 5, 5), title: 'Café')],
        existing: existing,
      );
      expect(firstPass.updatedDrafts.single.selected, isTrue);
      // User unchecks it, then a re-run happens.
      final deselected = firstPass.updatedDrafts.single.copyWith(selected: false);
      final secondPass = DocumentReconciler.planDeterministic(
        doc: _doc(),
        drafts: [deselected],
        existing: existing,
      );
      expect(secondPass.updatedDrafts.single.selected, isFalse);
    });

    test('no sweep when source of truth but scope is incomplete', () {
      final existing = [_tx(id: 'e2', amount: 999, date: DateTime(2026, 5, 15))];
      final plan = DocumentReconciler.planDeterministic(
        doc: _doc(sourceOfTruth: true, scopeAccountId: null, from: null, to: null),
        drafts: const [],
        existing: existing,
      );
      expect(plan.deleteCandidates, isEmpty);
    });
  });

  group('DocumentReconciler.inferScope', () {
    test('single account + date range', () {
      final scope = DocumentReconciler.inferScope([
        _draft(id: 'd1', amount: 1, date: DateTime(2026, 5, 3), accountId: 'accB'),
        _draft(id: 'd2', amount: 1, date: DateTime(2026, 5, 20), accountId: 'accB'),
      ]);
      expect(scope.singleAccountId, 'accB');
      expect(scope.from, DateTime(2026, 5, 3));
      expect(scope.to, DateTime(2026, 5, 20));
      expect(scope.isComplete, isTrue);
    });

    test('multiple accounts → ambiguous (no single account)', () {
      final scope = DocumentReconciler.inferScope([
        _draft(id: 'd1', amount: 1, date: DateTime(2026, 5, 3), accountId: 'accB'),
        _draft(id: 'd2', amount: 1, date: DateTime(2026, 5, 4), accountId: 'accC'),
      ]);
      expect(scope.singleAccountId, isNull);
      expect(scope.isComplete, isFalse);
    });
  });

  group('update apply contract', () {
    test('overwriting a matched movement preserves kind / goal / paid', () {
      // Mirrors _applyReconciliation: copyWith only the statement-known fields.
      final existing = _tx(id: 'e1', amount: 100, date: DateTime(2026, 5, 1), paid: false);
      final withGoal = existing.copyWith(goalId: 'g1');
      final updated = withGoal.copyWith(
        title: 'Nuevo',
        amount: 150,
        category: 'Otra',
        date: DateTime(2026, 5, 2),
        type: EntryType.income,
        account: 'Nu',
        accountId: 'accN',
        currency: 'USD',
        exchangeRate: 17.0,
      );
      expect(updated.id, 'e1'); // same row → INSERT OR REPLACE overwrites
      expect(updated.amount, 150);
      expect(updated.kind, EntryKind.standard); // untouched
      expect(updated.goalId, 'g1'); // untouched
      expect(updated.paid, isFalse); // untouched
    });
  });
}
