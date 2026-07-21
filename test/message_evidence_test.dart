import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/ingestion/message_evidence.dart';

/// Message shapes below mirror real Indian bank/card SMS templates observed
/// in a 3,253 message inbox. Amounts, merchants and digits are synthetic.
void main() {
  group('amountLiteralsIn', () {
    test('reads rupee amounts with separators and decimals', () {
      final values = amountLiteralsIn('Spent Rs 2,870.50 on card', 'INR');
      expect(values.map((e) => e.minorUnits), contains(287050));
    });

    test('reads amounts with no currency marker', () {
      // HDFC UPI reversal template writes a bare decimal.
      final values = amountLiteralsIn(
        'Your UPI transaction of 250.00 has been reversed',
        'INR',
      );
      expect(values.map((e) => e.minorUnits), contains(25000));
    });

    test('reads amounts with a Dr./Cr. infix', () {
      // Axis statement template: "Total amt: INR Dr. 543.10".
      final values = amountLiteralsIn('Total amt: INR Dr. 543.10', 'INR');
      expect(values.map((e) => e.minorUnits), contains(54310));
    });

    test('reads the rupee symbol', () {
      final values = amountLiteralsIn('₹1,234 debited', 'INR');
      expect(values.map((e) => e.minorUnits), contains(123400));
    });

    test('honours currencies without minor units', () {
      final values = amountLiteralsIn('Paid JPY 1500', 'JPY');
      expect(values.map((e) => e.minorUnits), contains(1500));
    });

    test('marks balance context', () {
      final values = amountLiteralsIn(
        'Rs 500.00 debited. Avl Bal Rs 12,340.00',
        'INR',
      );
      final balance = values.firstWhere((e) => e.minorUnits == 1234000);
      final spend = values.firstWhere((e) => e.minorUnits == 50000);
      expect(balance.looksLikeBalance, isTrue);
      expect(spend.looksLikeBalance, isFalse);
    });
  });

  group('isAuthorizationOnly', () {
    test('flags OTP authorisation carrying an amount', () {
      // The single largest double-counting source in the sampled inbox.
      expect(
        isAuthorizationOnly(
          '729341 is the OTP for trxn of INR 450.00 at Amazon Pay '
          'with your HDFC Bank Card ending 1234',
        ),
        isTrue,
      );
    });

    test('does not flag a completed debit that also warns about OTP', () {
      expect(
        isAuthorizationOnly(
          'Rs 450.00 debited from a/c XX1234. Never share your OTP with '
          'anyone. - HDFC Bank',
        ),
        isFalse,
      );
    });

    test('does not flag an ordinary transaction alert', () {
      expect(
        isAuthorizationOnly('Spent Rs 320.00 on HDFC Bank Card at Zomato'),
        isFalse,
      );
    });
  });

  group('verifyExtractedAmount', () {
    test('accepts an amount present in the body', () {
      expect(
        verifyExtractedAmount(
          body: 'Txn Rs 640.00 on HDFC Bank Card 1234 at VYAPAR by UPI',
          amountMinor: 64000,
          currency: 'INR',
        ),
        isNull,
      );
    });

    test('rejects a hallucinated amount', () {
      expect(
        verifyExtractedAmount(
          body: 'Txn Rs 640.00 on HDFC Bank Card 1234 at VYAPAR by UPI',
          amountMinor: 99900,
          currency: 'INR',
        ),
        EvidenceFailure.amountNotInMessage,
      );
    });

    test('rejects an amount taken from the balance', () {
      expect(
        verifyExtractedAmount(
          body: 'Rs 500.00 debited. Avl Bal Rs 12,340.00',
          amountMinor: 1234000,
          currency: 'INR',
        ),
        EvidenceFailure.amountIsBalance,
      );
    });

    test('accepts the movement amount from the same message', () {
      expect(
        verifyExtractedAmount(
          body: 'Rs 500.00 debited. Avl Bal Rs 12,340.00',
          amountMinor: 50000,
          currency: 'INR',
        ),
        isNull,
      );
    });

    test('accepts an amount repeated as both movement and balance', () {
      // Same figure in both roles must not be rejected.
      expect(
        verifyExtractedAmount(
          body: 'Rs 500.00 debited from a/c. Avl Bal Rs 500.00',
          amountMinor: 50000,
          currency: 'INR',
        ),
        isNull,
      );
    });

    test('rejects an OTP authorisation even when the amount matches', () {
      expect(
        verifyExtractedAmount(
          body: '729341 is the OTP for trxn of INR 450.00 at Amazon Pay',
          amountMinor: 45000,
          currency: 'INR',
        ),
        EvidenceFailure.authorizationOnly,
      );
    });

    test('accepts a reversal, which is a real movement', () {
      expect(
        verifyExtractedAmount(
          body:
              'HDFC Bank : Your UPI transaction of 250.00 has been '
              'reversed in your account due to technical problem',
          amountMinor: 25000,
          currency: 'INR',
        ),
        isNull,
      );
    });
  });
}
