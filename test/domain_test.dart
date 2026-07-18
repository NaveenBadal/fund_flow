import 'package:expense_manager/domain/finance_summary.dart';
import 'package:expense_manager/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('finance engine never combines currencies', () {
    final now = DateTime(2026, 7, 18);
    final values = [
      MoneyTransaction(
        amountMinor: 10000,
        currency: 'INR',
        direction: TransactionDirection.incoming,
        merchant: 'Employer',
        category: 'Income',
        occurredAt: now,
        source: TransactionSource.message,
      ),
      MoneyTransaction(
        amountMinor: 2500,
        currency: 'INR',
        direction: TransactionDirection.outgoing,
        merchant: 'Market',
        category: 'Food',
        occurredAt: now,
        source: TransactionSource.manual,
      ),
      MoneyTransaction(
        amountMinor: 500,
        currency: 'USD',
        direction: TransactionDirection.outgoing,
        merchant: 'Service',
        category: 'Bills',
        occurredAt: now,
        source: TransactionSource.message,
      ),
    ];
    final result = FinanceEngine.summarize(values);
    expect(result, hasLength(2));
    expect(result.first.currency, 'INR');
    expect(result.first.netMinor, 7500);
    expect(result.last.netMinor, -500);
  });
}
