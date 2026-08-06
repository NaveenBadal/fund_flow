import 'package:intl/intl.dart';

import '../domain/transaction.dart';

/// Presentation-side derivations over the ledger.
///
/// Kept out of the widgets so a screen reads as layout, and out of the domain
/// so nothing here can be mistaken for a rule the data obeys.

/// "HDFCBK-VISA" is what a bank sends; "Hdfcbk-Visa" is what a person reads.
/// Only all-caps names are recased — anything with mixed case was written by
/// someone who meant it.
String readableMerchant(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Unknown';
  if (trimmed != trimmed.toUpperCase()) return trimmed;
  return trimmed
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map(
        (part) =>
            part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

/// Today and yesterday are named; everything else is dated. Nobody counts back
/// from "2 days ago", and nobody needs the year for last Tuesday.
String dayLabel(DateTime day, {DateTime? now}) {
  final today = DateUtilsLite.startOfDay(now ?? DateTime.now());
  final target = DateUtilsLite.startOfDay(day);
  if (target == today) return 'Today';
  if (target == today.subtract(const Duration(days: 1))) return 'Yesterday';
  if (target.year == today.year) return DateFormat('EEEE d MMMM').format(target);
  return DateFormat('d MMMM yyyy').format(target);
}

abstract final class DateUtilsLite {
  static DateTime startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// The currency most of a set is in, so one screen never mixes two.
String dominantCurrency(Iterable<MoneyTransaction> values, String fallback) {
  if (values.isEmpty) return fallback;
  final counts = <String, int>{};
  for (final value in values) {
    counts[value.currency] = (counts[value.currency] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

int sumOf(
  Iterable<MoneyTransaction> values,
  TransactionDirection direction,
  String currency,
) => values
    .where((t) => t.direction == direction && t.currency == currency)
    .fold(0, (sum, t) => sum + t.amountMinor);

/// Outgoing totals per day of the month, indexed from day one.
List<int> dailyTotals(
  Iterable<MoneyTransaction> values,
  String currency,
  int days,
) {
  final totals = List.filled(days, 0);
  for (final item in values) {
    if (item.currency != currency) continue;
    if (item.direction != TransactionDirection.outgoing) continue;
    final index = item.occurredAt.day - 1;
    if (index >= 0 && index < days) totals[index] += item.amountMinor;
  }
  return totals;
}

/// Spending over the same stretch of the previous month.
///
/// Compared against elapsed days rather than the whole month, so a month that
/// is three days old is not reported as a collapse in spending.
int previousComparable(
  Iterable<MoneyTransaction> values,
  DateTime now,
  String currency,
) {
  final monthStart = DateTime(now.year, now.month);
  final previousStart = DateTime(now.year, now.month - 1);
  final elapsed = now.difference(monthStart);
  return values
      .where(
        (t) =>
            t.currency == currency &&
            t.direction == TransactionDirection.outgoing &&
            !t.occurredAt.isBefore(previousStart) &&
            t.occurredAt.isBefore(previousStart.add(elapsed)),
      )
      .fold(0, (sum, t) => sum + t.amountMinor);
}

/// Groups transactions by calendar day, newest first.
List<(DateTime, List<MoneyTransaction>)> byDay(
  List<MoneyTransaction> values,
) {
  final groups = <DateTime, List<MoneyTransaction>>{};
  for (final item in values) {
    groups
        .putIfAbsent(DateUtilsLite.startOfDay(item.occurredAt), () => [])
        .add(item);
  }
  final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final key in keys) (key, groups[key]!)];
}

String sourceLabel(TransactionSource source) => switch (source) {
  TransactionSource.message => 'Payment message',
  TransactionSource.notification => 'Payment notification',
  TransactionSource.manual => 'Added by you',
};

/// A file size someone can hold in their head.
String byteSize(int bytes) {
  if (bytes <= 0) return '—';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
