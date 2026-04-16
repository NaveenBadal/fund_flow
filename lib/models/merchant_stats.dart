class MerchantStats {
  final String merchant;
  final double lifetimeTotal;
  final int transactionCount;
  final DateTime? firstTransactionDate;
  final double averageAmount;
  final List<MonthlyMerchantTotal> monthlyTotals; // 6 entries

  const MerchantStats({
    required this.merchant,
    required this.lifetimeTotal,
    required this.transactionCount,
    this.firstTransactionDate,
    required this.averageAmount,
    required this.monthlyTotals,
  });
}

class MonthlyMerchantTotal {
  final int year;
  final int month;
  final double total;

  const MonthlyMerchantTotal({
    required this.year,
    required this.month,
    required this.total,
  });
}
