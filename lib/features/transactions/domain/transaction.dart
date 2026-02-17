enum EntryType { expense, income }

class FinanceEntry {
  FinanceEntry({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    required this.type,
  });

  final String id;
  final String title;
  final double amount;
  final String category;
  final DateTime date;
  final EntryType type;
}
