import 'dart:convert';
import 'package:crypto/crypto.dart';

class MessageCandidate {
  const MessageCandidate({
    required this.body,
    required this.receivedAt,
    this.sender,
  });
  final String body;
  final DateTime receivedAt;
  final String? sender;
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          '${sender ?? ''}|${receivedAt.toUtc().toIso8601String()}|$body',
        ),
      )
      .toString();
}

abstract final class CandidateGate {
  static final _money = RegExp(
    r'(?:₹|rs\.?|inr|usd|eur|aed|gbp|\$|€|£)\s*[\d,]+(?:\.\d{1,2})?',
    caseSensitive: false,
  );
  static final _transaction = RegExp(
    r'\b(?:debited|credited|spent|paid|received|purchase|txn|transaction|withdrawn|deposited|sent)\b',
    caseSensitive: false,
  );
  static final _reject = RegExp(
    r'\b(?:otp|one time password|verification code|offer|sale|discount|cashback offer)\b',
    caseSensitive: false,
  );

  static bool accepts(String body) =>
      !_reject.hasMatch(body) &&
      _money.hasMatch(body) &&
      _transaction.hasMatch(body);
}
