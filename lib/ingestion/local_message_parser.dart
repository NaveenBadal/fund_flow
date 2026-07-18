import '../domain/transaction.dart';
import 'message_candidate.dart';

class LocalMessageParser {
  static final _amount = RegExp(
    r'(₹|rs\.?|inr|usd|eur|aed|gbp|\$|€|£)\s*([\d,]+(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  MoneyTransaction? parse(MessageCandidate candidate) {
    if (!CandidateGate.accepts(candidate.body)) return null;
    final match = _amount.firstMatch(candidate.body);
    if (match == null) return null;
    final number = double.tryParse(match.group(2)!.replaceAll(',', ''));
    if (number == null || number <= 0) return null;
    final lower = candidate.body.toLowerCase();
    final incoming = RegExp(
      r'\b(?:credited|received|deposited)\b',
    ).hasMatch(lower);
    final currency = switch (match.group(1)!.toLowerCase()) {
      '₹' || 'rs' || 'rs.' || 'inr' => 'INR',
      r'$' || 'usd' => 'USD',
      '€' || 'eur' => 'EUR',
      '£' || 'gbp' => 'GBP',
      'aed' => 'AED',
      _ => 'INR',
    };
    final merchant =
        _merchant(candidate.body) ??
        candidate.sender ??
        (incoming ? 'Money received' : 'Transaction');
    return MoneyTransaction(
      amountMinor: (number * 100).round(),
      currency: currency,
      direction: incoming
          ? TransactionDirection.incoming
          : TransactionDirection.outgoing,
      merchant: merchant,
      category: _category(lower),
      occurredAt: candidate.receivedAt,
      source: TransactionSource.message,
      reviewState: ReviewState.needsReview,
      confidence: .62,
      sourceText: candidate.body,
    );
  }

  String? _merchant(String body) {
    final patterns = [
      RegExp(
        r'\b(?:at|to|from)\s+([A-Za-z][A-Za-z0-9 &._-]{2,28})',
        caseSensitive: false,
      ),
      RegExp(
        r'\bmerchant\s*[:\-]\s*([A-Za-z][A-Za-z0-9 &._-]{2,28})',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final value = pattern.firstMatch(body)?.group(1)?.trim();
      if (value != null) {
        return value
            .replaceFirst(
              RegExp(r'\s+(?:on|using|ref).*$', caseSensitive: false),
              '',
            )
            .trim();
      }
    }
    return null;
  }

  String _category(String lower) {
    if (RegExp(r'food|restaurant|swiggy|zomato|cafe').hasMatch(lower)) {
      return 'Food';
    }
    if (RegExp(r'uber|ola|fuel|petrol|metro').hasMatch(lower)) {
      return 'Transport';
    }
    if (RegExp(r'electric|utility|bill|recharge').hasMatch(lower)) {
      return 'Bills';
    }
    if (RegExp(r'salary|payroll').hasMatch(lower)) {
      return 'Income';
    }
    return 'Other';
  }
}
