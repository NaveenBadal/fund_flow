import 'transaction.dart';

/// Everything the Home screen shows, computed from the local ledger.
///
/// No model call, no network, no cache to invalidate: this is arithmetic over
/// rows the device already holds, so the screen can be correct in its first
/// frame. The previous version of this app could only produce these numbers by
/// asking a language model and waiting, which meant opening the app showed
/// nothing until a round trip finished.
///
/// Everything here is currency-safe by construction: a period is summarised in
/// one currency, chosen as the dominant one, and the rest are reachable through
/// the ledger and the agent. Adding rupees to dollars to make a single headline
/// is the one arithmetic mistake a money app must never make.
abstract final class Analytics {
  /// The currency most of the ledger is denominated in.
  static String? dominantCurrency(Iterable<MoneyTransaction> values) {
    final counts = <String, int>{};
    for (final item in values) {
      counts[item.currency] = (counts[item.currency] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first.key;
  }

  static bool inPeriod(MoneyTransaction item, DateTime from, DateTime to) =>
      !item.occurredAt.isBefore(from) && item.occurredAt.isBefore(to);

  static (DateTime from, DateTime to) monthOf(DateTime now) =>
      (DateTime(now.year, now.month), DateTime(now.year, now.month + 1));

  static PeriodOverview overview({
    required Iterable<MoneyTransaction> transactions,
    required DateTime from,
    required DateTime to,
    required String currency,
  }) {
    var incoming = 0;
    var outgoing = 0;
    var count = 0;
    for (final item in transactions) {
      if (item.currency != currency) continue;
      if (!inPeriod(item, from, to)) continue;
      count++;
      if (item.direction == TransactionDirection.incoming) {
        incoming += item.amountMinor;
      } else {
        outgoing += item.amountMinor;
      }
    }
    return PeriodOverview(
      currency: currency,
      from: from,
      to: to,
      incomingMinor: incoming,
      outgoingMinor: outgoing,
      transactionCount: count,
    );
  }

  /// Spending per category over a period, largest first.
  static List<CategoryTotal> byCategory({
    required Iterable<MoneyTransaction> transactions,
    required DateTime from,
    required DateTime to,
    required String currency,
    TransactionDirection direction = TransactionDirection.outgoing,
  }) {
    final totals = <String, (int, int)>{};
    for (final item in transactions) {
      if (item.currency != currency || item.direction != direction) continue;
      if (!inPeriod(item, from, to)) continue;
      final previous = totals[item.category] ?? (0, 0);
      totals[item.category] = (previous.$1 + item.amountMinor, previous.$2 + 1);
    }
    final rows =
        totals.entries
            .map(
              (entry) => CategoryTotal(
                category: entry.key,
                amountMinor: entry.value.$1,
                transactionCount: entry.value.$2,
              ),
            )
            .toList()
          ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    return rows;
  }

  /// One value per day across a period, for the bar series.
  ///
  /// Days with no spending are present with a zero rather than omitted — a
  /// missing bar reads as missing data, and a quiet Sunday is information.
  static List<DailyTotal> daily({
    required Iterable<MoneyTransaction> transactions,
    required DateTime from,
    required DateTime to,
    required String currency,
    TransactionDirection direction = TransactionDirection.outgoing,
  }) {
    final buckets = <DateTime, int>{};
    for (
      var day = DateTime(from.year, from.month, from.day);
      day.isBefore(to);
      day = day.add(const Duration(days: 1))
    ) {
      buckets[day] = 0;
    }
    for (final item in transactions) {
      if (item.currency != currency || item.direction != direction) continue;
      if (!inPeriod(item, from, to)) continue;
      final day = DateTime(
        item.occurredAt.year,
        item.occurredAt.month,
        item.occurredAt.day,
      );
      buckets[day] = (buckets[day] ?? 0) + item.amountMinor;
    }
    final days = buckets.keys.toList()..sort();
    return [
      for (final day in days)
        DailyTotal(day: day, amountMinor: buckets[day] ?? 0),
    ];
  }

  /// Repeat charges that look like a subscription.
  ///
  /// Deliberately conservative: three or more charges at one merchant, similar
  /// in amount, roughly a month apart. "Candidates", never asserted as facts —
  /// a monthly rent transfer and a gym membership are indistinguishable from
  /// the ledger, and telling someone they have a subscription they do not have
  /// is worse than staying quiet.
  static List<RecurringCharge> recurring({
    required Iterable<MoneyTransaction> transactions,
    required DateTime now,
    int minimumOccurrences = 3,
  }) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final item in transactions) {
      if (item.direction != TransactionDirection.outgoing) continue;
      final key = '${item.merchant.trim().toLowerCase()}|${item.currency}';
      groups.putIfAbsent(key, () => []).add(item);
    }

    final found = <RecurringCharge>[];
    for (final group in groups.values) {
      if (group.length < minimumOccurrences) continue;
      final sorted = [...group]
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

      final gaps = <int>[];
      for (var index = 1; index < sorted.length; index++) {
        gaps.add(
          sorted[index].occurredAt
              .difference(sorted[index - 1].occurredAt)
              .inDays,
        );
      }
      if (gaps.isEmpty) continue;
      final averageGap = gaps.reduce((a, b) => a + b) / gaps.length;
      // 21–45 days covers a monthly cycle billed on a date rather than an
      // interval, without swallowing weekly or quarterly charges.
      if (averageGap < 21 || averageGap > 45) continue;

      final amounts = sorted.map((item) => item.amountMinor).toList();
      final average = amounts.reduce((a, b) => a + b) / amounts.length;
      if (average <= 0) continue;
      // A merchant charged three wildly different amounts is a shop someone
      // visits monthly, not a subscription.
      final spread = amounts
          .map((amount) => (amount - average).abs() / average)
          .reduce((a, b) => a > b ? a : b);
      if (spread > 0.25) continue;

      final last = sorted.last;
      found.add(
        RecurringCharge(
          merchant: last.merchant,
          currency: last.currency,
          typicalMinor: average.round(),
          occurrences: sorted.length,
          averageGapDays: averageGap.round(),
          lastCharged: last.occurredAt,
          category: last.category,
          transactionIds: [
            for (final item in sorted)
              if (item.id != null) item.id!,
          ],
        ),
      );
    }
    found.sort((a, b) => a.nextExpected.compareTo(b.nextExpected));
    return found;
  }
}

class PeriodOverview {
  const PeriodOverview({
    required this.currency,
    required this.from,
    required this.to,
    required this.incomingMinor,
    required this.outgoingMinor,
    required this.transactionCount,
  });

  final String currency;
  final DateTime from;
  final DateTime to;
  final int incomingMinor;
  final int outgoingMinor;
  final int transactionCount;

  int get netMinor => incomingMinor - outgoingMinor;
  bool get empty => transactionCount == 0;

  /// How far through the period we are, so a spend figure can be read against
  /// the time that produced it.
  double elapsedFraction(DateTime now) {
    final total = to.difference(from).inMinutes;
    if (total <= 0) return 1;
    final done = now.difference(from).inMinutes;
    return (done / total).clamp(0, 1);
  }
}

class CategoryTotal {
  const CategoryTotal({
    required this.category,
    required this.amountMinor,
    required this.transactionCount,
  });
  final String category;
  final int amountMinor;
  final int transactionCount;
}

class DailyTotal {
  const DailyTotal({required this.day, required this.amountMinor});
  final DateTime day;
  final int amountMinor;
}

class RecurringCharge {
  const RecurringCharge({
    required this.merchant,
    required this.currency,
    required this.typicalMinor,
    required this.occurrences,
    required this.averageGapDays,
    required this.lastCharged,
    required this.category,
    required this.transactionIds,
  });

  final String merchant;
  final String currency;
  final int typicalMinor;
  final int occurrences;
  final int averageGapDays;
  final DateTime lastCharged;
  final String category;
  final List<int> transactionIds;

  DateTime get nextExpected => lastCharged.add(Duration(days: averageGapDays));

  int daysUntilNext(DateTime now) =>
      nextExpected.difference(DateTime(now.year, now.month, now.day)).inDays;
}
