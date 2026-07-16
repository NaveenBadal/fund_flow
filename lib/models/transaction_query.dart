import 'expense.dart';

class TransactionQuery {
  const TransactionQuery({
    this.label = 'primary',
    this.from,
    this.to,
    this.merchant,
    this.category,
    this.direction,
    this.currency,
    this.text,
    this.minimumAmount,
    this.maximumAmount,
    this.limit = 100,
  });

  final String label;
  final DateTime? from;
  final DateTime? to;
  final String? merchant;
  final String? category;
  final String? direction;
  final String? currency;
  final String? text;
  final double? minimumAmount;
  final double? maximumAmount;
  final int limit;

  factory TransactionQuery.fromJson(Map<String, dynamic> json) {
    String? clean(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    DateTime? date(String key) {
      final value = clean(key);
      if (value == null) return null;
      // Transaction dates are stored as device-local wall-clock values. Keep
      // the planner's calendar fields and deliberately ignore a supplied UTC
      // offset so a request for "20 June" cannot shift to the previous day.
      final match = RegExp(
        r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?)?',
      ).firstMatch(value);
      if (match == null) return null;
      final fraction = (match.group(7) ?? '').padRight(6, '0');
      return DateTime(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.tryParse(match.group(4) ?? '') ?? 0,
        int.tryParse(match.group(5) ?? '') ?? 0,
        int.tryParse(match.group(6) ?? '') ?? 0,
        fraction.isEmpty ? 0 : int.parse(fraction.substring(0, 3)),
        fraction.isEmpty ? 0 : int.parse(fraction.substring(3, 6)),
      );
    }

    double? number(String key) {
      final value = json[key];
      return value is num ? value.toDouble() : double.tryParse('$value');
    }

    final rawDirection = clean('direction')?.toLowerCase();
    final safeDirection = rawDirection == 'income' || rawDirection == 'expense'
        ? rawDirection
        : null;
    final rawLimit = json['limit'] is num
        ? (json['limit'] as num).toInt()
        : int.tryParse('${json['limit']}');
    return TransactionQuery(
      label: clean('label') ?? 'primary',
      from: date('from'),
      to: date('to'),
      merchant: clean('merchant'),
      category: clean('category'),
      direction: safeDirection,
      currency: clean('currency')?.toUpperCase(),
      text: clean('text'),
      minimumAmount: number('minimum_amount'),
      maximumAmount: number('maximum_amount'),
      limit: (rawLimit ?? 100).clamp(1, 200),
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    if (from != null) 'from': from!.toIso8601String(),
    if (to != null) 'to': to!.toIso8601String(),
    if (merchant != null) 'merchant': merchant,
    if (category != null) 'category': category,
    if (direction != null) 'direction': direction,
    if (currency != null) 'currency': currency,
    if (text != null) 'text': text,
    if (minimumAmount != null) 'minimum_amount': minimumAmount,
    if (maximumAmount != null) 'maximum_amount': maximumAmount,
    'limit': limit,
  };

  bool matches(Expense expense) {
    final haystack =
        '${expense.merchant} ${expense.displayMerchant} '
                '${expense.category} ${expense.tags}'
            .toLowerCase();
    return (from == null || !expense.date.isBefore(from!)) &&
        (to == null || !expense.date.isAfter(to!)) &&
        (merchant == null ||
            expense.merchant.toLowerCase().contains(merchant!.toLowerCase()) ||
            expense.displayMerchant.toLowerCase().contains(
              merchant!.toLowerCase(),
            )) &&
        (category == null ||
            expense.category.toLowerCase() == category!.toLowerCase()) &&
        (direction == null || expense.type == direction) &&
        (currency == null || expense.currency.toUpperCase() == currency) &&
        (text == null || haystack.contains(text!.toLowerCase())) &&
        (minimumAmount == null || expense.amount >= minimumAmount!) &&
        (maximumAmount == null || expense.amount <= maximumAmount!);
  }
}

class MoneyQueryPlan {
  const MoneyQueryPlan({
    required this.intent,
    required this.queries,
    this.needsClarification = false,
    this.clarification,
  });

  final String intent;
  final List<TransactionQuery> queries;
  final bool needsClarification;
  final String? clarification;

  factory MoneyQueryPlan.fromJson(Map<String, dynamic> json) {
    final rawQueries = json['queries'] as List<dynamic>? ?? const [];
    final queries = rawQueries
        .whereType<Map>()
        .map(
          (value) => TransactionQuery.fromJson(value.cast<String, dynamic>()),
        )
        .take(2)
        .toList();
    final rawIntent = json['intent']?.toString().trim().toLowerCase();
    const allowed = {'transactions', 'summary', 'comparison', 'app_help'};
    return MoneyQueryPlan(
      intent: allowed.contains(rawIntent) ? rawIntent! : 'transactions',
      queries: queries,
      needsClarification: json['needs_clarification'] == true,
      clarification: json['clarification']?.toString().trim(),
    );
  }

  Map<String, dynamic> toJson() => {
    'intent': intent,
    'needs_clarification': needsClarification,
    if (clarification != null) 'clarification': clarification,
    'queries': queries.map((query) => query.toJson()).toList(),
  };
}
