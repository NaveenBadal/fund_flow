enum MessageAuthor { person, assistant }

class ConversationMessage {
  const ConversationMessage({
    this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.verified = false,
    this.supportingTransactionIds = const [],
  });
  final int? id;
  final MessageAuthor author;
  final String text;
  final DateTime createdAt;
  final bool verified;
  final List<int> supportingTransactionIds;

  Map<String, Object?> toMap() => {
    'id': id,
    'author': author.name,
    'text': text,
    'created_at': createdAt.toUtc().toIso8601String(),
    'verified': verified ? 1 : 0,
    'supporting_ids': supportingTransactionIds.join(','),
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
      );
}
