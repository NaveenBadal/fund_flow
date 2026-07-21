import 'package:intl/intl.dart';

import 'transaction.dart';

/// Deterministic findings over the local ledger.
///
/// The same rules already backed the agent's anomaly, duplicate and briefing
/// capabilities, reachable only by asking a question and waiting on a model.
/// Nothing about them needs a model: they are arithmetic over rows the device
/// already holds. Lifting them out lets the app open with something useful on
/// screen in the first frame, at no cost and with no network, and keeps one
/// definition of what counts as a duplicate rather than two that can drift.
abstract final class InsightEngine {
  /// Charges close enough together, and alike enough, to be worth a look.
  ///
  /// Deliberately "candidates": a subscription renewal and a double charge
  /// look identical from the ledger alone, so these are never presented as
  /// proven duplicates and never acted on automatically.
  static List<DuplicateFinding> duplicates(
    Iterable<MoneyTransaction> values, {
    Duration within = const Duration(hours: 48),
  }) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final item in values) {
      final key = [
        item.merchant.trim().toLowerCase(),
        item.amountMinor,
        item.currency,
        item.direction.name,
      ].join('|');
      groups.putIfAbsent(key, () => []).add(item);
    }
    final findings = <DuplicateFinding>[];
    for (final group in groups.values) {
      final sorted = [...group]
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      for (var index = 1; index < sorted.length; index++) {
        final previous = sorted[index - 1];
        final current = sorted[index];
        final gap = current.occurredAt.difference(previous.occurredAt);
        if (gap <= within) {
          findings.add(
            DuplicateFinding(earlier: previous, later: current, apart: gap),
          );
        }
      }
    }
    findings.sort((a, b) => a.apart.compareTo(b.apart));
    return findings;
  }

  /// Charges far above what this merchant usually costs.
  ///
  /// Needs at least [minimumSample] comparable charges before it will call
  /// anything unusual, because two data points cannot establish a normal.
  static List<AnomalyFinding> anomalies(
    Iterable<MoneyTransaction> values, {
    int minimumSample = 3,
    double multiple = 2,
  }) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final item in values) {
      final key = [
        item.merchant.toLowerCase(),
        item.currency,
        item.direction.name,
      ].join('|');
      groups.putIfAbsent(key, () => []).add(item);
    }
    final findings = <AnomalyFinding>[];
    for (final group in groups.values.where(
      (items) => items.length >= minimumSample,
    )) {
      final amounts = group.map((item) => item.amountMinor).toList()..sort();
      final median = amounts[amounts.length ~/ 2];
      if (median <= 0) continue;
      for (final item in group.where(
        (value) => value.amountMinor >= median * multiple,
      )) {
        findings.add(
          AnomalyFinding(
            transaction: item,
            medianMinor: median,
            sampleSize: group.length,
          ),
        );
      }
    }
    findings.sort((a, b) => b.multiple.compareTo(a.multiple));
    return findings;
  }

  /// How this month's spending compares with the same stretch of last month.
  ///
  /// Compared against the same number of elapsed days rather than the whole
  /// previous month, so a month that is a week old is not reported as a
  /// collapse in spending.
  static PaceFinding? pace(Iterable<MoneyTransaction> values, DateTime now) {
    final currency = _dominantCurrency(values);
    if (currency == null) return null;
    final monthStart = DateTime(now.year, now.month);
    final previousStart = DateTime(now.year, now.month - 1);
    final elapsed = now.difference(monthStart);

    int spent(DateTime from, DateTime to) => values
        .where(
          (item) =>
              item.currency == currency &&
              item.direction == TransactionDirection.outgoing &&
              !item.occurredAt.isBefore(from) &&
              item.occurredAt.isBefore(to),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);

    final current = spent(monthStart, now);
    final baseline = spent(previousStart, previousStart.add(elapsed));
    if (baseline <= 0 || current <= 0) return null;
    return PaceFinding(
      currency: currency,
      currentMinor: current,
      baselineMinor: baseline,
    );
  }

  /// The currency most of the ledger is in.
  ///
  /// Insights never mix currencies, and a home screen has room for one
  /// headline, so the rest are left to the questions someone asks directly.
  static String? _dominantCurrency(Iterable<MoneyTransaction> values) {
    final counts = <String, int>{};
    for (final item in values) {
      counts[item.currency] = (counts[item.currency] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final ranked = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return ranked.first.key;
  }

  /// Everything worth surfacing unprompted, most useful first.
  ///
  /// [now] is passed rather than read so this stays a pure function of the
  /// ledger, which is what makes it testable and cheap to call on build.
  static List<Insight> insights(
    Iterable<MoneyTransaction> values,
    DateTime now, {
    Duration recent = const Duration(days: 45),
    int limit = 3,
  }) {
    final window = now.subtract(recent);
    final recentValues = values
        .where((item) => item.occurredAt.isAfter(window))
        .toList();
    final found = <Insight>[];

    for (final duplicate in duplicates(recentValues).take(2)) {
      found.add(
        Insight(
          kind: InsightKind.duplicate,
          title: '${duplicate.later.merchant} charged twice',
          detail: duplicate.apart.inHours < 24
              ? 'Two charges the same size within a day of each other.'
              : 'Two charges the same size ${duplicate.apart.inDays} days apart.',
          question:
              'Are the ${duplicate.later.merchant} charges around '
              '${_day(duplicate.later.occurredAt)} duplicates?',
          transactionIds: [
            if (duplicate.earlier.id != null) duplicate.earlier.id!,
            if (duplicate.later.id != null) duplicate.later.id!,
          ],
          amountMinor: duplicate.later.amountMinor,
          currency: duplicate.later.currency,
        ),
      );
    }

    for (final anomaly in anomalies(recentValues).take(2)) {
      found.add(
        Insight(
          kind: InsightKind.anomaly,
          title: '${anomaly.transaction.merchant} cost more than usual',
          detail:
              '${anomaly.multiple.toStringAsFixed(1)}× its usual amount '
              'across ${anomaly.sampleSize} charges.',
          question:
              'Why was ${anomaly.transaction.merchant} higher than usual?',
          transactionIds: [
            if (anomaly.transaction.id != null) anomaly.transaction.id!,
          ],
          amountMinor: anomaly.transaction.amountMinor,
          currency: anomaly.transaction.currency,
        ),
      );
    }

    final paceFinding = pace(values, now);
    if (paceFinding != null && paceFinding.isNotable) {
      final up = paceFinding.change > 0;
      found.add(
        Insight(
          kind: InsightKind.pace,
          title: up
              ? 'Spending is ahead of last month'
              : 'Spending is behind last month',
          detail:
              '${(paceFinding.change.abs() * 100).round()}% '
              '${up ? 'more' : 'less'} than the same stretch of last month.',
          question: 'How does this month compare with last month?',
          transactionIds: const [],
          amountMinor: paceFinding.currentMinor,
          currency: paceFinding.currency,
        ),
      );
    }

    // A duplicate is money possibly taken twice, so it outranks an unusual
    // amount, which in turn outranks a trend that is merely interesting.
    found.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return found.take(limit).toList();
  }

  /// "13 Jun" rather than "13/6", which reads as either date depending on
  /// where the person learned to write them.
  static String _day(DateTime value) => DateFormat('d MMM').format(value);
}

/// Ordered by how much the person needs to know about it.
enum InsightKind { duplicate, anomaly, pace }

class Insight {
  const Insight({
    required this.kind,
    required this.title,
    required this.detail,
    required this.question,
    required this.transactionIds,
    required this.amountMinor,
    required this.currency,
  });

  final InsightKind kind;
  final String title;
  final String detail;

  /// What tapping this asks the agent, so the instant surface hands off to
  /// the one that can actually explain it.
  final String question;
  final List<int> transactionIds;
  final int amountMinor;
  final String currency;
}

class DuplicateFinding {
  const DuplicateFinding({
    required this.earlier,
    required this.later,
    required this.apart,
  });
  final MoneyTransaction earlier;
  final MoneyTransaction later;
  final Duration apart;
}

class AnomalyFinding {
  const AnomalyFinding({
    required this.transaction,
    required this.medianMinor,
    required this.sampleSize,
  });
  final MoneyTransaction transaction;
  final int medianMinor;
  final int sampleSize;

  double get multiple => transaction.amountMinor / medianMinor;
}

class PaceFinding {
  const PaceFinding({
    required this.currency,
    required this.currentMinor,
    required this.baselineMinor,
  });
  final String currency;
  final int currentMinor;
  final int baselineMinor;

  double get change => (currentMinor - baselineMinor) / baselineMinor;

  /// Small swings are noise, and reporting them unprompted trains people to
  /// ignore the whole surface.
  bool get isNotable => change.abs() >= 0.15;
}
