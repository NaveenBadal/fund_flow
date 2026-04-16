import '../models/expense.dart';
import '../models/spending_insight.dart';
import 'package:flutter/material.dart';

/// Detects spending anomalies by comparing current week vs 4-week rolling average.
class AnomalyDetector {
  static List<SpendingInsight> detect(List<Expense> expenses) {
    final insights = <SpendingInsight>[];
    final now = DateTime.now();
    final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
    final thisWeekStartDay = DateTime(thisWeekStart.year, thisWeekStart.month, thisWeekStart.day);

    // Current week expenses (expenses only, no income)
    final thisWeek = expenses.where((e) =>
        !e.isIncome &&
        !e.date.isBefore(thisWeekStartDay)).toList();

    // Past 4 weeks (excluding current week)
    final past4WeeksStart = thisWeekStartDay.subtract(const Duration(days: 28));
    final past4Weeks = expenses.where((e) =>
        !e.isIncome &&
        e.date.isAfter(past4WeeksStart) &&
        e.date.isBefore(thisWeekStartDay)).toList();

    if (past4Weeks.isEmpty) return insights;

    // Group by merchant
    final thisWeekByMerchant = <String, double>{};
    for (final e in thisWeek) {
      final key = (e.normalizedMerchant ?? e.merchant).trim();
      thisWeekByMerchant.update(key, (v) => v + e.amount, ifAbsent: () => e.amount);
    }

    final past4ByMerchant = <String, double>{};
    for (final e in past4Weeks) {
      final key = (e.normalizedMerchant ?? e.merchant).trim();
      past4ByMerchant.update(key, (v) => v + e.amount, ifAbsent: () => e.amount);
    }

    for (final entry in thisWeekByMerchant.entries) {
      final merchant = entry.key;
      final thisWeekAmt = entry.value;
      final past4Total = past4ByMerchant[merchant] ?? 0;
      if (past4Total == 0) continue;

      final weeklyAvg = past4Total / 4;
      if (thisWeekAmt > weeklyAvg * 1.5) {
        final multiplier = (thisWeekAmt / weeklyAvg).toStringAsFixed(1);
        insights.add(SpendingInsight(
          type: SpendingInsightType.anomaly,
          title: 'High spending at $merchant',
          body: '₹${thisWeekAmt.toStringAsFixed(0)} this week — ${multiplier}× your usual ₹${weeklyAvg.toStringAsFixed(0)}',
          icon: Icons.warning_amber_rounded,
          isWarning: true,
        ));
      }
    }

    return insights;
  }
}
