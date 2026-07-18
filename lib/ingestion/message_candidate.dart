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
