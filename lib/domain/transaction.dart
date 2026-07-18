enum TransactionDirection { incoming, outgoing }

enum TransactionSource { message, notification, manual }

enum ReviewState { confirmed, needsReview }

class MoneyTransaction {
  const MoneyTransaction({
    this.id,
    required this.amountMinor,
    required this.currency,
    required this.direction,
    required this.merchant,
    required this.category,
    required this.occurredAt,
    required this.source,
    this.reviewState = ReviewState.confirmed,
    this.confidence = 1,
    this.account,
    this.note,
    this.sourceText,
  });

  final int? id;
  final int amountMinor;
  final String currency;
  final TransactionDirection direction;
  final String merchant;
  final String category;
  final DateTime occurredAt;
  final TransactionSource source;
  final ReviewState reviewState;
  final double confidence;
  final String? account;
  final String? note;
  final String? sourceText;

  int get signedMinor =>
      direction == TransactionDirection.incoming ? amountMinor : -amountMinor;

  MoneyTransaction copyWith({
    int? id,
    int? amountMinor,
    String? currency,
    TransactionDirection? direction,
    String? merchant,
    String? category,
    DateTime? occurredAt,
    TransactionSource? source,
    ReviewState? reviewState,
    double? confidence,
    String? account,
    String? note,
    String? sourceText,
  }) => MoneyTransaction(
    id: id ?? this.id,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    direction: direction ?? this.direction,
    merchant: merchant ?? this.merchant,
    category: category ?? this.category,
    occurredAt: occurredAt ?? this.occurredAt,
    source: source ?? this.source,
    reviewState: reviewState ?? this.reviewState,
    confidence: confidence ?? this.confidence,
    account: account ?? this.account,
    note: note ?? this.note,
    sourceText: sourceText ?? this.sourceText,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'amount_minor': amountMinor,
    'currency': currency,
    'direction': direction.name,
    'merchant': merchant,
    'category': category,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
    'source': source.name,
    'review_state': reviewState.name,
    'confidence': confidence,
    'account': account,
    'note': note,
    'source_text': sourceText,
  };

  factory MoneyTransaction.fromMap(Map<String, Object?> map) =>
      MoneyTransaction(
        id: map['id'] as int?,
        amountMinor: map['amount_minor'] as int,
        currency: map['currency'] as String,
        direction: TransactionDirection.values.byName(
          map['direction'] as String,
        ),
        merchant: map['merchant'] as String,
        category: map['category'] as String,
        occurredAt: DateTime.parse(map['occurred_at'] as String).toLocal(),
        source: TransactionSource.values.byName(map['source'] as String),
        reviewState: ReviewState.values.byName(map['review_state'] as String),
        confidence: (map['confidence'] as num).toDouble(),
        account: map['account'] as String?,
        note: map['note'] as String?,
        sourceText: map['source_text'] as String?,
      );
}
