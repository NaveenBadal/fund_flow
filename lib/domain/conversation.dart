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

/// One conversation in the history list.
///
/// Threads are created only when a question is actually sent, so an opened
/// and abandoned chat never leaves an empty row behind.
class ConversationThread {
  const ConversationThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
    this.preview,
  });

  final int id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  /// Opening of the most recent message, for the history row.
  final String? preview;

  factory ConversationThread.fromMap(Map<String, Object?> map) =>
      ConversationThread(
        id: map['id']! as int,
        title: map['title'] as String? ?? 'Untitled chat',
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(map['updated_at'] as String).toLocal(),
        messageCount: (map['message_count'] as int?) ?? 0,
        preview: (map['preview'] as String?)?.trim(),
      );

  /// Derives a title from the question that started the thread.
  ///
  /// Uses the person's own words rather than asking the model for a title:
  /// a title is worth no round trip, and their phrasing is what they will
  /// recognise when scanning the list later.
  static String titleFrom(String question) {
    final text = question.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return 'New chat';
    if (text.length <= 60) return text;
    // Prefer a word boundary so the title does not end mid-word.
    final cut = text.lastIndexOf(' ', 60);
    return '${text.substring(0, cut > 24 ? cut : 60).trimRight()}…';
  }
}
