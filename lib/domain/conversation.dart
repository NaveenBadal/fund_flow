import 'dart:convert';

import '../agent/agent_presentation.dart';

enum MessageAuthor { person, assistant }

class ConversationMessage {
  const ConversationMessage({
    this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.verified = false,
    this.supportingTransactionIds = const [],
    this.parts = const [],
    this.unstructured = false,
  });
  final int? id;
  final MessageAuthor author;
  final String text;
  final DateTime createdAt;
  final bool verified;
  final List<int> supportingTransactionIds;
  final List<AgentPart> parts;
  final bool unstructured;

  /// What the provider should see when this message is replayed as history.
  ///
  /// Falls back to [text] for anything without structured parts, such as the
  /// person's own questions.
  String get providerContent {
    if (parts.isEmpty) return text;
    final lines = parts
        .map((part) => part.historyLine)
        .whereType<String>()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.isEmpty ? text : lines.join('\n');
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'author': author.name,
    'text': text,
    'created_at': createdAt.toUtc().toIso8601String(),
    'verified': verified ? 1 : 0,
    'supporting_ids': supportingTransactionIds.join(','),
    'parts_json': jsonEncode(parts.map((part) => part.toJson()).toList()),
    'unstructured': unstructured ? 1 : 0,
  };
  factory ConversationMessage.fromMap(Map<String, Object?> map) =>
      ConversationMessage(
        id: map['id'] as int?,
        author: MessageAuthor.values.byName(map['author'] as String),
        text: map['text'] as String,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        verified: map['verified'] == 1,
        supportingTransactionIds: (map['supporting_ids'] as String)
            .split(',')
            .where((e) => e.isNotEmpty)
            .map(int.parse)
            .toList(),
        parts: ((jsonDecode(map['parts_json'] as String? ?? '[]') as List))
            .map((value) => AgentPart.fromJson(value as Map<Object?, Object?>))
            .toList(),
        unstructured: map['unstructured'] == 1,
      );
}
