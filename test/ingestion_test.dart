import 'package:expense_manager/ingestion/local_message_parser.dart';
import 'package:expense_manager/ingestion/message_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('candidate gate rejects OTP and accepts financial activity', () {
    expect(
      CandidateGate.accepts('OTP 123456 for INR 900 transaction'),
      isFalse,
    );
    expect(
      CandidateGate.accepts('INR 1,249.50 debited at MARKET on card'),
      isTrue,
    );
  });
  test('local parser preserves minor units and requires review', () {
    final item = LocalMessageParser().parse(
      MessageCandidate(
        body: 'INR 1,249.50 debited at MARKET on card',
        receivedAt: DateTime(2026, 7, 18),
      ),
    )!;
    expect(item.amountMinor, 124950);
    expect(item.merchant, 'MARKET');
    expect(item.confidence, lessThan(1));
  });
}
