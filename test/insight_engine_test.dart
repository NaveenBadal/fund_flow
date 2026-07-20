import 'package:flutter_test/flutter_test.dart';

import 'package:fund_flow/domain/insight_engine.dart';
import 'package:fund_flow/domain/transaction.dart';

void main() {
  test('two identical charges a day apart are duplicate candidates', () {
    final findings = InsightEngine.duplicates([
      _at(DateTime(2026, 7, 7), merchant: 'Adobe', amountMinor: 169900),
      _at(DateTime(2026, 7, 8), merchant: 'Adobe', amountMinor: 169900),
    ]);
    expect(findings, hasLength(1));
    expect(findings.single.apart, const Duration(days: 1));
  });

  test('a monthly subscription is not a duplicate candidate', () {
    // Same merchant and amount, a month apart: a renewal, not a double
    // charge, and calling it one would train people to ignore the surface.
    final findings = InsightEngine.duplicates([
      _at(DateTime(2026, 6, 8), merchant: 'Adobe', amountMinor: 169900),
      _at(DateTime(2026, 7, 8), merchant: 'Adobe', amountMinor: 169900),
    ]);
    expect(findings, isEmpty);
  });

  test('an unusual amount needs a baseline to be unusual against', () {
    // Two charges cannot establish what normal is.
    expect(
      InsightEngine.anomalies([
        _at(DateTime(2026, 7, 1), merchant: 'Zomato', amountMinor: 20000),
        _at(DateTime(2026, 7, 2), merchant: 'Zomato', amountMinor: 90000),
      ]),
      isEmpty,
    );
  });

  test('a charge far above the merchant median is flagged', () {
    final findings = InsightEngine.anomalies([
      _at(DateTime(2026, 7, 1), merchant: 'Zomato', amountMinor: 20000),
      _at(DateTime(2026, 7, 2), merchant: 'Zomato', amountMinor: 21000),
      _at(DateTime(2026, 7, 3), merchant: 'Zomato', amountMinor: 19000),
      _at(DateTime(2026, 7, 4), merchant: 'Zomato', amountMinor: 90000),
    ]);
    expect(findings, hasLength(1));
    expect(findings.single.transaction.amountMinor, 90000);
    expect(findings.single.multiple, greaterThan(4));
  });

  test('pace compares the same stretch of the previous month', () {
    // On the 10th, the whole of last month would make any month look like a
    // collapse; only the first 10 days are a fair comparison.
    final finding = InsightEngine.pace([
      _at(DateTime(2026, 6, 5), amountMinor: 10000),
      _at(DateTime(2026, 6, 25), amountMinor: 500000),
      _at(DateTime(2026, 7, 5), amountMinor: 20000),
    ], DateTime(2026, 7, 10));
    expect(finding, isNotNull);
    expect(finding!.baselineMinor, 10000);
    expect(finding.currentMinor, 20000);
    expect(finding.change, 1.0);
  });

  test('a small swing is not worth interrupting anyone about', () {
    final finding = InsightEngine.pace([
      _at(DateTime(2026, 6, 5), amountMinor: 100000),
      _at(DateTime(2026, 7, 5), amountMinor: 105000),
    ], DateTime(2026, 7, 10));
    expect(finding!.isNotable, isFalse);
  });

  test('duplicates outrank unusual amounts, which outrank a trend', () {
    final insights = InsightEngine.insights([
      _at(DateTime(2026, 7, 18), merchant: 'Adobe', amountMinor: 169900, id: 1),
      _at(DateTime(2026, 7, 19), merchant: 'Adobe', amountMinor: 169900, id: 2),
      _at(DateTime(2026, 7, 1), merchant: 'Zomato', amountMinor: 20000, id: 3),
      _at(DateTime(2026, 7, 2), merchant: 'Zomato', amountMinor: 21000, id: 4),
      _at(DateTime(2026, 7, 3), merchant: 'Zomato', amountMinor: 19000, id: 5),
      _at(DateTime(2026, 7, 4), merchant: 'Zomato', amountMinor: 90000, id: 6),
    ], DateTime(2026, 7, 20));
    expect(insights.first.kind, InsightKind.duplicate);
    expect(insights.any((item) => item.kind == InsightKind.anomaly), isTrue);
    // Every card must be able to hand off to the agent.
    expect(insights.every((item) => item.question.isNotEmpty), isTrue);
    expect(insights.first.transactionIds, [1, 2]);
  });

  test('an empty ledger notices nothing rather than inventing something', () {
    expect(InsightEngine.insights(const [], DateTime(2026, 7, 20)), isEmpty);
  });

  test('stale findings are not surfaced as news', () {
    // A duplicate from eight months ago is not what "noticed" means.
    expect(
      InsightEngine.insights([
        _at(DateTime(2025, 11, 7), merchant: 'Adobe', amountMinor: 169900),
        _at(DateTime(2025, 11, 8), merchant: 'Adobe', amountMinor: 169900),
      ], DateTime(2026, 7, 20)),
      isEmpty,
    );
  });
}

MoneyTransaction _at(
  DateTime occurredAt, {
  String merchant = 'Cafe River',
  int amountMinor = 25000,
  int? id,
}) => MoneyTransaction(
  id: id,
  amountMinor: amountMinor,
  currency: 'INR',
  direction: TransactionDirection.outgoing,
  merchant: merchant,
  category: 'Food',
  occurredAt: occurredAt,
  source: TransactionSource.message,
);
