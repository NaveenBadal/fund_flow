import 'dart:convert';

import '../models/expense.dart';
import 'ollama_cloud_service.dart';

class MoneyChatAnswer {
  const MoneyChatAnswer({required this.text, required this.sources});
  final String text;
  final List<Expense> sources;
}

/// Grounds every copilot answer in a bounded, explicit transaction snapshot.
class MoneyChatService {
  const MoneyChatService(this.cloud);
  final OllamaCloudService cloud;

  Future<MoneyChatAnswer> ask(String question, List<Expense> all) async {
    final relevant = all.take(220).toList();
    final monthly = <String, Map<String, double>>{};
    final categories = <String, double>{};
    final merchants = <String, double>{};
    for (final e in all) {
      final month = '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      final bucket = monthly.putIfAbsent(
        month,
        () => {'income': 0, 'expense': 0},
      );
      final direction = e.isIncome ? 'income' : 'expense';
      bucket[direction] = (bucket[direction] ?? 0) + e.amount;
      if (!e.isIncome) {
        categories.update(
          e.category,
          (value) => value + e.amount,
          ifAbsent: () => e.amount,
        );
        merchants.update(
          e.displayMerchant,
          (value) => value + e.amount,
          ifAbsent: () => e.amount,
        );
      }
    }
    final records = [
      for (final e in relevant)
        {
          'id': e.id,
          'date': e.date.toIso8601String(),
          'amount': e.amount,
          'currency': e.currency,
          'direction': e.type,
          'merchant': e.displayMerchant,
          'category': e.category,
          'tags': e.tagList,
          'recurring': e.isRecurring,
        },
    ];
    final answer = await cloud.answer(
      systemPrompt:
          'You are Flow, a precise private financial analyst. Answer only from '
          'the supplied transaction snapshot. Calculate carefully. State the '
          'date range and currency when relevant. If data is insufficient, say '
          'exactly what is missing. Never invent balances, transactions, or '
          'future certainty. Be concise, conversational, and actionable. Do not '
          'expose raw SMS content. Today is ${DateTime.now().toIso8601String()}.',
      userPrompt:
          'QUESTION: $question\n'
          'COMPLETE_DATASET_RECORD_COUNT: ${all.length}\n'
          'COMPLETE_MONTHLY_TOTALS: ${jsonEncode(monthly)}\n'
          'COMPLETE_CATEGORY_TOTALS: ${jsonEncode(categories)}\n'
          'COMPLETE_MERCHANT_TOTALS: ${jsonEncode(merchants)}\n'
          'MOST_RECENT_TRANSACTION_RECORDS: ${jsonEncode(records)}',
    );
    return MoneyChatAnswer(text: answer, sources: relevant);
  }
}
