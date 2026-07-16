class AssistantMessage {
  const AssistantMessage({
    this.id,
    required this.user,
    required this.text,
    required this.timestamp,
    this.sources = 0,
    this.verified = false,
    this.filterDetails = '',
  });

  final int? id;
  final bool user;
  final String text;
  final DateTime timestamp;
  final int sources;
  final bool verified;
  final String filterDetails;

  Map<String, dynamic> toMap() => {
    'id': id,
    'is_user': user ? 1 : 0,
    'text': text,
    'sources': sources,
    'verified': verified ? 1 : 0,
    'filter_details': filterDetails,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AssistantMessage.fromMap(Map<String, dynamic> map) =>
      AssistantMessage(
        id: map['id'] as int?,
        user: (map['is_user'] as int) == 1,
        text: map['text'] as String,
        sources: map['sources'] as int? ?? 0,
        verified: (map['verified'] as int? ?? 0) == 1,
        filterDetails: map['filter_details'] as String? ?? '',
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
}
