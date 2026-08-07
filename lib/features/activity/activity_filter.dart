// StateProvider moved to the legacy entrypoint in Riverpod 3. These two hold a
// single value that anything in the app may set; a full Notifier per value would
// be ceremony around one assignment.
import 'package:flutter_riverpod/legacy.dart';

import '../../domain/transaction.dart';

enum ActivityPeriod { thisMonth, lastMonth, last90, all }

enum ReviewOnly { any, needsReview }

/// What the ledger is currently showing.
///
/// Held outside the page so Home can open Activity already narrowed to a
/// category — tapping a donut slice and landing on an unfiltered list is the
/// difference between a chart being an answer and being decoration.
class ActivityFilter {
  const ActivityFilter({
    this.query = '',
    this.period = ActivityPeriod.thisMonth,
    this.direction,
    this.category,
    this.review = ReviewOnly.any,
    this.merchant,
  });

  final String query;
  final ActivityPeriod period;
  final TransactionDirection? direction;
  final String? category;
  final ReviewOnly review;
  final String? merchant;

  bool get isNarrowed =>
      query.isNotEmpty ||
      period != ActivityPeriod.thisMonth ||
      direction != null ||
      category != null ||
      review != ReviewOnly.any ||
      merchant != null;

  ActivityFilter copyWith({
    String? query,
    ActivityPeriod? period,
    TransactionDirection? direction,
    bool clearDirection = false,
    String? category,
    bool clearCategory = false,
    ReviewOnly? review,
    String? merchant,
    bool clearMerchant = false,
  }) => ActivityFilter(
    query: query ?? this.query,
    period: period ?? this.period,
    direction: clearDirection ? null : direction ?? this.direction,
    category: clearCategory ? null : category ?? this.category,
    review: review ?? this.review,
    merchant: clearMerchant ? null : merchant ?? this.merchant,
  );

  (DateTime?, DateTime?) get range {
    final now = DateTime.now();
    return switch (period) {
      ActivityPeriod.thisMonth => (
        DateTime(now.year, now.month),
        DateTime(now.year, now.month + 1),
      ),
      ActivityPeriod.lastMonth => (
        DateTime(now.year, now.month - 1),
        DateTime(now.year, now.month),
      ),
      ActivityPeriod.last90 => (
        now.subtract(const Duration(days: 90)),
        now.add(const Duration(days: 1)),
      ),
      ActivityPeriod.all => (null, null),
    };
  }

  String get periodLabel => switch (period) {
    ActivityPeriod.thisMonth => 'This month',
    ActivityPeriod.lastMonth => 'Last month',
    ActivityPeriod.last90 => 'Last 90 days',
    ActivityPeriod.all => 'All time',
  };

  bool matches(MoneyTransaction item) {
    final (from, to) = range;
    if (from != null && item.occurredAt.isBefore(from)) return false;
    // `to` is exclusive, so a transaction stamped exactly at midnight on the
    // first belongs to the next period, not to both.
    if (to != null && !item.occurredAt.isBefore(to)) return false;
    if (direction != null && item.direction != direction) return false;
    if (category != null &&
        item.category.toLowerCase() != category!.toLowerCase()) {
      return false;
    }
    if (merchant != null &&
        item.merchant.trim().toLowerCase() != merchant!.trim().toLowerCase()) {
      return false;
    }
    if (review == ReviewOnly.needsReview &&
        item.reviewState != ReviewState.needsReview) {
      return false;
    }
    if (query.isNotEmpty) {
      final needle = query.toLowerCase();
      final haystack = [
        item.merchant,
        item.category,
        item.account ?? '',
        item.note ?? '',
      ].join(' ').toLowerCase();
      if (!haystack.contains(needle)) return false;
    }
    return true;
  }
}

final activityFilterProvider = StateProvider<ActivityFilter>(
  (ref) => const ActivityFilter(),
);

/// Transactions grouped into days, newest first.
///
/// Grouping in the provider rather than the list builder keeps the day header
/// and its subtotal derived from exactly the rows shown beneath it, so a filter
/// can never leave a header claiming a total that includes rows it hid.
class DaySection {
  const DaySection({
    required this.day,
    required this.items,
    required this.netMinor,
    required this.currency,
  });
  final DateTime day;
  final List<MoneyTransaction> items;
  final int netMinor;
  final String currency;
}

List<DaySection> groupByDay(List<MoneyTransaction> items) {
  final buckets = <DateTime, List<MoneyTransaction>>{};
  for (final item in items) {
    final day = DateTime(
      item.occurredAt.year,
      item.occurredAt.month,
      item.occurredAt.day,
    );
    buckets.putIfAbsent(day, () => []).add(item);
  }
  final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final day in days)
      () {
        final rows = buckets[day]!
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        // A day's subtotal is only meaningful in one currency. Where a day
        // mixes them, the dominant one is summed and the header says nothing
        // about the rest rather than adding them together.
        final counts = <String, int>{};
        for (final row in rows) {
          counts[row.currency] = (counts[row.currency] ?? 0) + 1;
        }
        final currency =
            (counts.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value)))
                .first
                .key;
        final net = rows
            .where((row) => row.currency == currency)
            .fold<int>(0, (sum, row) => sum + row.signedMinor);
        return DaySection(
          day: day,
          items: rows,
          netMinor: net,
          currency: currency,
        );
      }(),
  ];
}
