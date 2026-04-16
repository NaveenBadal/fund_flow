import '../models/expense.dart';

/// Detects recurring/subscription transactions from a list of expenses.
class RecurringDetector {
  /// Analyze [expenses] and return a map of expense id → isRecurring flag.
  /// An expense is recurring if the same merchant appears at roughly monthly
  /// or weekly intervals with a similar amount (within ±15%).
  static Map<int, bool> detect(List<Expense> expenses) {
    final result = <int, bool>{};
    final expenseOnly = expenses.where((e) => !e.isIncome).toList();

    // Group by normalized merchant
    final byMerchant = <String, List<Expense>>{};
    for (final e in expenseOnly) {
      final key = (e.normalizedMerchant ?? e.merchant).toLowerCase().trim();
      byMerchant.putIfAbsent(key, () => []).add(e);
    }

    for (final group in byMerchant.values) {
      if (group.length < 2) continue;

      final sorted = [...group]..sort((a, b) => a.date.compareTo(b.date));

      final isRecurring = _isRecurringGroup(sorted);
      if (isRecurring) {
        for (final e in group) {
          if (e.id != null) result[e.id!] = true;
        }
      }
    }

    // Mark expenses NOT in any recurring group as false
    for (final e in expenseOnly) {
      if (e.id != null && !result.containsKey(e.id)) {
        result[e.id!] = false;
      }
    }

    return result;
  }

  static bool _isRecurringGroup(List<Expense> sorted) {
    if (sorted.length < 2) return false;

    int monthlyMatches = 0;
    int weeklyMatches = 0;

    for (int i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final curr = sorted[i];

      final daysDiff = curr.date.difference(prev.date).inDays.abs();
      final amtDiff = (curr.amount - prev.amount).abs();
      final avgAmt = (curr.amount + prev.amount) / 2;
      final amtTolerance = avgAmt * 0.15; // ±15%

      if (amtDiff <= amtTolerance) {
        if (daysDiff >= 25 && daysDiff <= 35) monthlyMatches++;
        if (daysDiff >= 5 && daysDiff <= 9) weeklyMatches++;
      }
    }

    // Recurring if ≥2 monthly matches or ≥3 weekly matches
    return monthlyMatches >= 2 || weeklyMatches >= 3;
  }
}
