import 'dart:convert';

import 'package:fund_flow/domain/transaction.dart';
import 'package:fund_flow/ingestion/ai_message_ingestion.dart';
import 'package:fund_flow/ingestion/message_candidate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final candidate = MessageCandidate(
    body: 'Your account was charged ₹1,250 at River Books.',
    sender: 'BANK',
    receivedAt: DateTime(2026, 7, 18, 9),
  );

  test('AI ingestion accepts typed integer-minor-unit extraction', () {
    final batch = AiIngestionBatch.parse(
      content: jsonEncode({
        'results': [
          {
            'id': candidate.fingerprint,
            'decision': 'transaction',
            'reason': 'Completed card purchase',
            'amountMinor': 125000,
            'currency': 'INR',
            'direction': 'outgoing',
            'merchant': 'River Books',
            'category': 'Shopping',
            'occurredAt': '2026-07-18T09:00:00+05:30',
            'confidence': 0.96,
          },
        ],
      }),
      candidates: [candidate],
      source: TransactionSource.message,
      now: DateTime(2026, 7, 18, 12),
    );
    final transaction = batch.results.single.transaction!;
    expect(transaction.amountMinor, 125000);
    expect(transaction.merchant, 'River Books');
    expect(transaction.reviewState, ReviewState.needsReview);
    expect(transaction.sourceText, candidate.body);
  });

  test(
    'AI can classify a message as non-transaction without local heuristics',
    () {
      final batch = AiIngestionBatch.parse(
        content: jsonEncode({
          'results': [
            {
              'id': candidate.fingerprint,
              'decision': 'not_transaction',
              'reason': 'This is a promotional message.',
            },
          ],
        }),
        candidates: [candidate],
        source: TransactionSource.message,
        now: DateTime(2026, 7, 18, 12),
      );
      expect(batch.results.single.transaction, isNull);
      expect(batch.results.single.decision, IngestionDecision.notTransaction);
    },
  );

  test('missing or invented message IDs reject the entire batch', () {
    expect(
      () => AiIngestionBatch.parse(
        content: jsonEncode({
          'results': [
            {'id': 'invented', 'decision': 'uncertain', 'reason': 'Unknown'},
          ],
        }),
        candidates: [candidate],
        source: TransactionSource.message,
        now: DateTime(2026, 7, 18, 12),
      ),
      throwsA(isA<IngestionSchemaException>()),
    );
  });

  test('floating point money is rejected', () {
    expect(
      () => AiIngestionBatch.parse(
        content: jsonEncode({
          'results': [
            {
              'id': candidate.fingerprint,
              'decision': 'transaction',
              'reason': 'Purchase',
              'amountMinor': 12.5,
              'currency': 'INR',
              'direction': 'outgoing',
              'merchant': 'River Books',
              'category': 'Shopping',
              'occurredAt': '2026-07-18T09:00:00+05:30',
              'confidence': 0.9,
            },
          ],
        }),
        candidates: [candidate],
        source: TransactionSource.message,
        now: DateTime(2026, 7, 18, 12),
      ),
      throwsA(isA<IngestionSchemaException>()),
    );
  });
}
