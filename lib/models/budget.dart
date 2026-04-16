class Budget {
  final int? id;
  final String category;
  final double limitAmount;
  final String currency;

  const Budget({
    this.id,
    required this.category,
    required this.limitAmount,
    this.currency = 'INR',
  });

  Budget copyWith({
    int? id,
    String? category,
    double? limitAmount,
    String? currency,
  }) =>
      Budget(
        id: id ?? this.id,
        category: category ?? this.category,
        limitAmount: limitAmount ?? this.limitAmount,
        currency: currency ?? this.currency,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category,
        'limit_amount': limitAmount,
        'currency': currency,
      };

  factory Budget.fromMap(Map<String, dynamic> map) => Budget(
        id: map['id'] as int?,
        category: map['category'] as String,
        limitAmount: (map['limit_amount'] as num).toDouble(),
        currency: map['currency'] as String? ?? 'INR',
      );
}
