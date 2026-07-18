import 'transaction.dart';

class CurrencySummary {
  const CurrencySummary({
    required this.currency,
    required this.incomingMinor,
    required this.outgoingMinor,
    required this.transactionCount,
  });
  final String currency;
  final int incomingMinor;
  final int outgoingMinor;
  final int transactionCount;
  int get netMinor => incomingMinor - outgoingMinor;
}

abstract final class FinanceEngine {
  static List<CurrencySummary> summarize(Iterable<MoneyTransaction> items) {
    final values = <String, (int, int, int)>{};
    for (final item in items) {
      final old = values[item.currency] ?? (0, 0, 0);
      values[item.currency] = item.direction == TransactionDirection.incoming
          ? (old.$1 + item.amountMinor, old.$2, old.$3 + 1)
          : (old.$1, old.$2 + item.amountMinor, old.$3 + 1);
    }
    return values.entries
        .map(
          (e) => CurrencySummary(
            currency: e.key,
            incomingMinor: e.value.$1,
            outgoingMinor: e.value.$2,
            transactionCount: e.value.$3,
          ),
        )
        .toList()
      ..sort((a, b) => a.currency.compareTo(b.currency));
  }
}
