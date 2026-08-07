import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/analytics.dart';
import '../domain/budget.dart';
import '../domain/insight_engine.dart';
import '../domain/transaction.dart';
import 'app_controller.dart';
import 'budgets_controller.dart';

/// Everything Home draws, computed in one pass.
///
/// One snapshot rather than six providers: the flow card, the attention strip,
/// the donut and the rings all describe the same month, and computing them
/// separately let them disagree — a total that included a currency the
/// breakdown below it excluded. Deriving them together makes that impossible.
class HomeSnapshot {
  const HomeSnapshot({
    required this.currency,
    required this.month,
    required this.previousMonth,
    required this.categories,
    required this.daily,
    required this.insights,
    required this.upcoming,
    required this.budgets,
    required this.reviewCount,
    required this.duplicateCount,
    required this.elapsedFraction,
    required this.spendChange,
    required this.empty,
  });

  final String currency;
  final PeriodOverview month;

  /// The same stretch of last month, not the whole of it — comparing a
  /// six-day-old month against a finished one reports every month as a
  /// collapse in spending until the 28th.
  final PeriodOverview previousMonth;

  final List<CategoryTotal> categories;
  final List<DailyTotal> daily;
  final List<Insight> insights;
  final List<RecurringCharge> upcoming;
  final List<BudgetStatus> budgets;
  final int reviewCount;
  final int duplicateCount;
  final double elapsedFraction;

  /// Signed change in spending against the comparable stretch of last month.
  /// Null when there is no baseline to compare against.
  final double? spendChange;

  final bool empty;

  int get totalSpendMinor => month.outgoingMinor;
}

/// Recomputed whenever the ledger or the budget list changes.
///
/// `DateTime.now()` is read here rather than injected because the whole point is
/// a value that reflects the moment the screen is built; the pure functions it
/// calls all take the timestamp as an argument, which is what keeps them
/// reasonable to reason about.
final homeSnapshotProvider = Provider<HomeSnapshot>((ref) {
  final app = ref.watch(appControllerProvider).value;
  final budgetList = ref.watch(budgetsProvider).value ?? const [];
  final transactions = app?.transactions ?? const <MoneyTransaction>[];
  final now = DateTime.now();
  final fallbackCurrency = app?.preferences.currency ?? 'INR';
  final currency = Analytics.dominantCurrency(transactions) ?? fallbackCurrency;

  final (monthFrom, monthTo) = Analytics.monthOf(now);
  final month = Analytics.overview(
    transactions: transactions,
    from: monthFrom,
    to: monthTo,
    currency: currency,
  );

  final elapsed = now.difference(monthFrom);
  final previousFrom = DateTime(now.year, now.month - 1);
  final previous = Analytics.overview(
    transactions: transactions,
    from: previousFrom,
    to: previousFrom.add(elapsed),
    currency: currency,
  );

  final categories = Analytics.byCategory(
    transactions: transactions,
    from: monthFrom,
    to: monthTo,
    currency: currency,
  );

  final spentByCategory = {
    for (final row in categories) row.category.toLowerCase(): row,
  };

  final budgets = [
    for (final budget in budgetList)
      BudgetStatus(
        budget: budget,
        spentMinor:
            spentByCategory[budget.category.toLowerCase()]?.amountMinor ?? 0,
        transactionCount:
            spentByCategory[budget.category.toLowerCase()]?.transactionCount ??
            0,
      ),
  ]..sort((a, b) => b.fraction.compareTo(a.fraction));

  final recurring = Analytics.recurring(transactions: transactions, now: now);

  return HomeSnapshot(
    currency: currency,
    month: month,
    previousMonth: previous,
    categories: categories,
    // Only the days that have happened. Running the series to the end of the
    // month drew a long flat line across dates in the future, which reads as a
    // week of zero spending rather than as a month still in progress.
    daily: Analytics.daily(
      transactions: transactions,
      from: monthFrom,
      to: DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
      currency: currency,
    ),
    insights: InsightEngine.insights(transactions, now),
    // Only what is actually coming up: a subscriptions list belongs on its own
    // page, but Home is about the next fortnight.
    upcoming: recurring
        .where((charge) {
          final days = charge.daysUntilNext(now);
          return days >= 0 && days <= 14;
        })
        .take(4)
        .toList(),
    budgets: budgets,
    reviewCount: transactions
        .where((item) => item.reviewState == ReviewState.needsReview)
        .length,
    duplicateCount: InsightEngine.duplicates(
      transactions
          .where(
            (item) =>
                item.occurredAt.isAfter(now.subtract(const Duration(days: 45))),
          )
          .toList(),
    ).length,
    elapsedFraction: month.elapsedFraction(now),
    spendChange: previous.outgoingMinor <= 0
        ? null
        : (month.outgoingMinor - previous.outgoingMinor) /
              previous.outgoingMinor,
    empty: transactions.isEmpty,
  );
});

/// Every recurring charge, for the Subscriptions page.
final recurringProvider = Provider<List<RecurringCharge>>((ref) {
  final app = ref.watch(appControllerProvider).value;
  return Analytics.recurring(
    transactions: app?.transactions ?? const [],
    now: DateTime.now(),
  );
});

/// Transactions the extraction was not confident about, oldest first.
///
/// Oldest first on purpose: the review queue is a backlog, and clearing the
/// oldest item is what makes the number go down in a way that feels like
/// progress rather than an endless stream of new arrivals.
final reviewQueueProvider = Provider<List<MoneyTransaction>>((ref) {
  final app = ref.watch(appControllerProvider).value;
  final items =
      (app?.transactions ?? const <MoneyTransaction>[])
          .where((item) => item.reviewState == ReviewState.needsReview)
          .toList()
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  return items;
});
