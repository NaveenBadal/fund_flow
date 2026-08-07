/// A monthly ceiling on one category.
///
/// Monthly and per-category only, deliberately. A budgeting system with
/// arbitrary periods, envelopes and rollover is a second product; what makes
/// "how am I doing?" answerable is a target to measure against, and one number
/// per category does that. Anything more elaborate is unset in practice.
class CategoryBudget {
  const CategoryBudget({
    required this.category,
    required this.limitMinor,
    required this.currency,
    required this.createdAt,
  });

  final String category;
  final int limitMinor;
  final String currency;
  final DateTime createdAt;

  CategoryBudget copyWith({int? limitMinor, String? currency}) =>
      CategoryBudget(
        category: category,
        limitMinor: limitMinor ?? this.limitMinor,
        currency: currency ?? this.currency,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
    'category': category,
    'limit_minor': limitMinor,
    'currency': currency,
    'created_at': createdAt.toUtc().toIso8601String(),
  };

  factory CategoryBudget.fromMap(Map<String, Object?> map) => CategoryBudget(
    category: map['category'] as String,
    limitMinor: map['limit_minor'] as int,
    currency: map['currency'] as String,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
  );
}

/// A budget with this month's spending measured against it.
class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.spentMinor,
    required this.transactionCount,
  });

  final CategoryBudget budget;
  final int spentMinor;
  final int transactionCount;

  String get category => budget.category;
  int get limitMinor => budget.limitMinor;
  String get currency => budget.currency;
  int get remainingMinor => budget.limitMinor - spentMinor;

  double get fraction =>
      budget.limitMinor <= 0 ? 0 : spentMinor / budget.limitMinor;

  bool get over => spentMinor > budget.limitMinor;

  /// Close enough to the limit to be worth saying so before it is passed.
  bool get close => !over && fraction >= 0.85;

  /// What the month is on course to reach at the current rate.
  ///
  /// Straight-line projection from days elapsed. Not a forecast of behaviour —
  /// it answers "if nothing changes", which is the only projection the ledger
  /// can actually support.
  int projectedMinor(DateTime now) {
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final elapsed = now.day;
    if (elapsed <= 0) return spentMinor;
    return (spentMinor / elapsed * daysInMonth).round();
  }
}
