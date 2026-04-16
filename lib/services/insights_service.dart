import 'package:flutter/material.dart';
import '../models/expense.dart';
import '../models/spending_insight.dart';

/// Computes local spending insights from expense history.
class InsightsService {
  static List<SpendingInsight> compute(List<Expense> expenses) {
    final insights = <SpendingInsight>[];
    final expensesOnly = expenses.where((e) => !e.isIncome).toList();
    if (expensesOnly.isEmpty) return insights;

    // Weekend vs weekday ratio
    final weekend = expensesOnly.where((e) => e.date.weekday >= 6).fold(0.0, (s, e) => s + e.amount);
    final weekday = expensesOnly.where((e) => e.date.weekday < 6).fold(0.0, (s, e) => s + e.amount);
    if (weekday > 0) {
      final ratio = weekend / weekday;
      if (ratio > 0.5) {
        insights.add(SpendingInsight(
          type: SpendingInsightType.weekendSpender,
          title: 'Weekend spender',
          body: 'You spend ${(ratio * 100).toStringAsFixed(0)}% as much on weekends vs weekdays.',
          icon: Icons.weekend_rounded,
        ));
      }
    }

    // Peak spending hour
    final hourTotals = <int, double>{};
    for (final e in expensesOnly) {
      hourTotals.update(e.date.hour, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    if (hourTotals.isNotEmpty) {
      final peakHour = hourTotals.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      final label = _formatHour(peakHour);
      insights.add(SpendingInsight(
        type: SpendingInsightType.peakHour,
        title: 'Peak spending at $label',
        body: 'Most of your transactions happen around $label.',
        icon: Icons.schedule_rounded,
      ));
    }

    // Day of week overspend
    final dowTotals = <int, double>{};
    for (final e in expensesOnly) {
      dowTotals.update(e.date.weekday, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    if (dowTotals.isNotEmpty) {
      final maxEntry = dowTotals.entries.reduce((a, b) => a.value > b.value ? a : b);
      final dayName = _dayName(maxEntry.key);
      insights.add(SpendingInsight(
        type: SpendingInsightType.overspendDay,
        title: '$dayName is your top spend day',
        body: '₹${maxEntry.value.toStringAsFixed(0)} total on ${dayName}s.',
        icon: Icons.today_rounded,
      ));
    }

    // Fastest growing category (last 30 days vs 30 days before)
    final now = DateTime.now();
    final cutoff30 = now.subtract(const Duration(days: 30));
    final cutoff60 = now.subtract(const Duration(days: 60));

    final recent = expensesOnly.where((e) => e.date.isAfter(cutoff30));
    final older = expensesOnly.where((e) => e.date.isAfter(cutoff60) && !e.date.isAfter(cutoff30));

    final recentByCategory = <String, double>{};
    for (final e in recent) {
      recentByCategory.update(e.category, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    final olderByCategory = <String, double>{};
    for (final e in older) {
      olderByCategory.update(e.category, (v) => v + e.amount, ifAbsent: () => e.amount);
    }

    String? fastestCat;
    double maxGrowth = 0.2; // minimum 20% growth to surface
    for (final entry in recentByCategory.entries) {
      final prev = olderByCategory[entry.key] ?? 0;
      if (prev > 0) {
        final growth = (entry.value - prev) / prev;
        if (growth > maxGrowth) {
          maxGrowth = growth;
          fastestCat = entry.key;
        }
      }
    }
    if (fastestCat != null) {
      insights.add(SpendingInsight(
        type: SpendingInsightType.growingCategory,
        title: '$fastestCat spending up ${(maxGrowth * 100).toStringAsFixed(0)}%',
        body: 'Compared to the previous 30 days.',
        icon: Icons.trending_up_rounded,
        isWarning: true,
      ));
    }

    return insights;
  }

  static String _formatHour(int h) {
    if (h == 0) return '12 AM';
    if (h < 12) return '$h AM';
    if (h == 12) return '12 PM';
    return '${h - 12} PM';
  }

  static String _dayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(weekday - 1).clamp(0, 6)];
  }
}
