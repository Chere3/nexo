import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/local_store.dart';
import 'recurring_transaction.dart';
import 'transaction.dart';

class RecurringTransactionsNotifier extends StateNotifier<List<RecurringTransaction>> {
  RecurringTransactionsNotifier() : super([]) {
    load();
  }

  void load() {
    final rows = LocalStore.db.select('''
      SELECT id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active
      FROM recurring_transactions
      WHERE active = 1
      ORDER BY next_due_date ASC
    ''');

    state = rows
        .map(
          (r) => RecurringTransaction(
            id: r['id'] as String,
            title: r['title'] as String,
            amount: (r['amount'] as num).toDouble(),
            category: r['category'] as String,
            type: (r['type'] as String) == 'income' ? EntryType.income : EntryType.expense,
            frequency: (r['frequency'] as String) == 'weekly'
                ? RecurringFrequency.weekly
                : RecurringFrequency.monthly,
            dayOfMonth: r['day_of_month'] as int?,
            dayOfWeek: r['day_of_week'] as int?,
            nextDueDate: DateTime.parse(r['next_due_date'] as String),
            active: (r['active'] as int) == 1,
          ),
        )
        .toList();

    if (state.isEmpty) {
      _seedDefaults();
      load();
    }
  }

  void _seedDefaults() {
    final now = DateTime.now();
    final phoneDay = now.day <= 28 ? now.day : 28;

    LocalStore.db.execute(
      '''
      INSERT OR IGNORE INTO recurring_transactions
      (id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'rec-spotify',
        'Spotify Premium',
        129.0,
        'Ocio',
        'expense',
        'monthly',
        phoneDay,
        null,
        DateTime(now.year, now.month, phoneDay).toIso8601String(),
        1,
      ],
    );

    final weeklyDate = now.add(Duration(days: (8 - now.weekday) % 7));
    LocalStore.db.execute(
      '''
      INSERT OR IGNORE INTO recurring_transactions
      (id, title, amount, category, type, frequency, day_of_month, day_of_week, next_due_date, active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'rec-weekly-gym',
        'Gym',
        180.0,
        'Salud',
        'expense',
        'weekly',
        null,
        DateTime.monday,
        DateTime(weeklyDate.year, weeklyDate.month, weeklyDate.day).toIso8601String(),
        1,
      ],
    );
  }
}

final recurringTransactionsProvider =
    StateNotifierProvider<RecurringTransactionsNotifier, List<RecurringTransaction>>(
  (ref) => RecurringTransactionsNotifier(),
);

final upcomingPaymentsProvider = Provider<List<UpcomingPayment>>((ref) {
  final recurring = ref.watch(recurringTransactionsProvider);
  final now = DateTime.now();
  final end = now.add(const Duration(days: 30));

  final upcoming = <UpcomingPayment>[];

  for (final r in recurring) {
    DateTime date = DateTime(r.nextDueDate.year, r.nextDueDate.month, r.nextDueDate.day);

    while (!date.isAfter(end)) {
      if (!date.isBefore(DateTime(now.year, now.month, now.day))) {
        upcoming.add(
          UpcomingPayment(
            id: '${r.id}-${date.toIso8601String()}',
            title: r.title,
            amount: r.amount,
            category: r.category,
            type: r.type,
            dueDate: date,
            frequency: r.frequency,
          ),
        );
      }

      if (r.frequency == RecurringFrequency.weekly) {
        date = date.add(const Duration(days: 7));
      } else {
        final nextMonth = DateTime(date.year, date.month + 1, 1);
        final dom = r.dayOfMonth ?? date.day;
        final safeDay = dom > 28 ? 28 : dom;
        date = DateTime(nextMonth.year, nextMonth.month, safeDay);
      }
    }
  }

  upcoming.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return upcoming.take(6).toList();
});
