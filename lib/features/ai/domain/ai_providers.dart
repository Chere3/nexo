import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_config.dart';
import '../../../core/util/ids.dart';
import '../../accounts/domain/account.dart';
import '../../accounts/domain/accounts_provider.dart';
import '../../categories/domain/categories_provider.dart';
import '../../categories/domain/category.dart';
import '../../transactions/domain/currency.dart';
import '../../transactions/domain/transaction.dart';
import 'ai_mode.dart';
import 'ai_services.dart';

final aiServicesProvider = Provider<AiServices?>((ref) {
  final client = ref.watch(llmClientProvider);
  if (client == null) return null;
  return AiServices(client, persona: ref.watch(aiPersonaProvider));
});

/// Resolves a parsed AI draft into a persistable [FinanceEntry], matching
/// category/account names against the user's catalog (case-insensitive) and
/// stamping the currency conversion rate at entry time.
FinanceEntry entryFromParsed(
  ParsedTransaction p, {
  required List<Category> categories,
  required List<Account> accounts,
}) {
  Category? cat;
  if (p.categoryName != null) {
    final target = p.categoryName!.toLowerCase();
    for (final c in categories) {
      if (c.name.toLowerCase() == target) {
        cat = c;
        break;
      }
    }
  }
  Account? acc;
  if (p.accountName != null) {
    final target = p.accountName!.toLowerCase();
    for (final a in accounts) {
      if (a.name.toLowerCase() == target) {
        acc = a;
        break;
      }
    }
  }

  return FinanceEntry(
    id: newId('tx'),
    title: p.title,
    amount: p.amount,
    category: cat?.name ?? p.categoryName ?? 'Sin categoría',
    categoryId: cat?.id,
    date: p.date ?? DateTime.now(),
    type: p.type,
    account: acc?.name ?? p.accountName ?? 'Efectivo',
    accountId: acc?.id,
    currency: p.currency,
    note: p.note,
    exchangeRate: effectiveMxnRate(p.currency),
    createdAt: DateTime.now(),
  );
}

/// Convenience aggregate of the catalogs the AI flows need.
final aiCatalogProvider = Provider((ref) {
  return (
    categories: ref.watch(activeCategoriesProvider),
    accounts: ref.watch(activeAccountsProvider),
  );
});
