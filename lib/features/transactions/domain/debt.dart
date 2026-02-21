enum DebtKind { lent, borrowed }

enum DebtStatus { pending, settled }

class DebtEntry {
  DebtEntry({
    required this.id,
    required this.person,
    required this.concept,
    required this.amount,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.dueDate,
  });

  final String id;
  final String person;
  final String concept;
  final double amount;
  final DebtKind kind;
  final DebtStatus status;
  final DateTime createdAt;
  final DateTime? dueDate;
}
