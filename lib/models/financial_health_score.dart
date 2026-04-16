class FinancialHealthScore {
  final int score; // 0–100
  final double savingsRate; // 0.0–1.0
  final double budgetAdherence; // 0.0–1.0
  final double trendScore; // 0.0–1.0 (lower spend trend = higher score)

  const FinancialHealthScore({
    required this.score,
    required this.savingsRate,
    required this.budgetAdherence,
    required this.trendScore,
  });

  String get grade {
    if (score >= 85) return 'A';
    if (score >= 70) return 'B';
    if (score >= 55) return 'C';
    if (score >= 40) return 'D';
    return 'F';
  }

  String get gradeLabel {
    return switch (grade) {
      'A' => 'Excellent',
      'B' => 'Good',
      'C' => 'Fair',
      'D' => 'Needs work',
      _ => 'Critical',
    };
  }

  factory FinancialHealthScore.compute({
    required double totalIncome,
    required double totalExpense,
    required List<Map<String, dynamic>> budgetProgress,
    required double previousMonthExpense,
  }) {
    // Savings rate: (income - expense) / income, clamped 0–1
    final savingsRate = totalIncome > 0
        ? ((totalIncome - totalExpense) / totalIncome).clamp(0.0, 1.0)
        : 0.0;

    // Budget adherence: fraction of categories within budget
    final budgetAdherence = budgetProgress.isEmpty
        ? 0.5
        : budgetProgress
                .where((b) =>
                    (b['spent'] as num).toDouble() <=
                    (b['limit_amount'] as num).toDouble())
                .length /
            budgetProgress.length;

    // Trend score: lower expense vs previous month = better
    final trendScore = previousMonthExpense > 0 && totalExpense < previousMonthExpense
        ? 1.0
        : previousMonthExpense > 0
            ? (1.0 - ((totalExpense - previousMonthExpense) / previousMonthExpense).clamp(0.0, 1.0))
            : 0.5;

    final score = ((savingsRate * 40) + (budgetAdherence * 35) + (trendScore * 25)).round().clamp(0, 100);

    return FinancialHealthScore(
      score: score,
      savingsRate: savingsRate,
      budgetAdherence: budgetAdherence,
      trendScore: trendScore,
    );
  }
}
