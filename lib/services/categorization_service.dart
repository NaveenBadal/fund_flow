import '../models/expense.dart';
import '../models/ai_log.dart';
import '../models/ai_provider.dart';
import 'database_helper.dart';
import 'ollama_cloud_service.dart';

/// Result of a batch parse: extracted expenses + per-body skip reasons.
class SmsBatchResult {
  const SmsBatchResult({required this.expenses, required this.skipReasons});

  final List<Expense> expenses;

  /// Maps SMS body text → reason string (e.g. "otp", "promotional",
  /// "balance_alert", "not_financial", "no_response", "parse_error").
  /// Only populated for messages that did NOT produce an expense.
  final Map<String, String> skipReasons;
}

/// Parses financial SMS into [Expense]s using the Ollama Cloud model.
class CategorizationService {
  const CategorizationService({
    required this.apiKey,
    this.baseUrl = defaultOllamaBaseUrl,
    this.model = defaultOllamaModel,
    this.currency = 'INR',
  });

  final String apiKey;
  final String baseUrl;
  final String model;
  final String currency;

  Future<SmsBatchResult> parseSmsBatch(
    List<Map<String, dynamic>> smsList,
  ) async {
    if (smsList.isEmpty) {
      return const SmsBatchResult(expenses: [], skipReasons: {});
    }

    final cloud = OllamaCloudService(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
    );

    if (!cloud.hasKey) {
      final reasons = {
        for (final s in smsList) s['body'] as String: 'no_api_key',
      };
      await _logResult(
        batchSize: smsList.length,
        expenses: 0,
        skipped: smsList.length,
        status: 'Error: Ollama Cloud API key not set',
      );
      cloud.close();
      return SmsBatchResult(expenses: [], skipReasons: reasons);
    }

    final expenses = <Expense>[];
    final skipReasons = <String, String>{};
    int expenseCount = 0;
    int skipCount = 0;
    String status = 'Success';

    Map<String, String> learnedMap = const {};
    try {
      learnedMap = await DatabaseHelper.instance.getMerchantCategoryMap();
    } catch (_) {}

    void accept(Map<String, dynamic> sms, OllamaParseResult result) {
      final body = sms['body'] as String;
      try {
        if (!result.isFinancial) {
          skipReasons[body] = result.type;
          skipCount++;
          return;
        }

        final amount = result.amount;
        if (amount == null || amount <= 0) {
          skipReasons[body] = 'zero_amount';
          skipCount++;
          return;
        }

        final extractedCounterparty = result.merchant?.trim();
        final merchant =
            extractedCounterparty == null || extractedCounterparty.isEmpty
            ? 'Unknown'
            : extractedCounterparty;

        String category = result.category ?? 'Others';
        final learned = learnedMap[merchant.toLowerCase()];
        if (learned != null && learned.isNotEmpty) category = learned;
        final merchantKnown = merchant.toLowerCase() != 'unknown';
        final categoryKnown = category != 'Others';
        final confidence = !merchantKnown
            ? 0.55
            : categoryKnown
            ? 0.90
            : 0.75;

        expenses.add(
          Expense(
            amount: amount,
            currency: currency,
            merchant: merchant,
            normalizedMerchant: null,
            category: category,
            date: DateTime.parse(sms['date'] as String),
            originalSms: body,
            type: switch (result.type) {
              'income' => 'income',
              'transfer' => 'transfer',
              _ => 'expense',
            },
            status: confidence < 0.7 ? 'needs_review' : 'settled',
            source: 'sms',
            confidence: confidence,
          ),
        );
        expenseCount++;
      } catch (error) {
        status = 'Error: $error';
        skipReasons[body] = 'parse_error';
        skipCount++;
      }
    }

    Future<void> parseChunk(List<Map<String, dynamic>> chunk) async {
      try {
        final results = await cloud.parseBatch([
          for (final sms in chunk) sms['body'] as String,
        ]);
        for (var index = 0; index < chunk.length; index++) {
          final result = results[index];
          if (result != null) {
            accept(chunk[index], result);
          } else {
            skipReasons[chunk[index]['body'] as String] = 'parse_error';
            skipCount++;
          }
        }
      } catch (error) {
        // Preserve throughput for healthy messages when a malformed response
        // poisons a batch. Recursive splitting is only used on failure.
        if (chunk.length > 1) {
          final middle = chunk.length ~/ 2;
          await Future.wait([
            parseChunk(chunk.sublist(0, middle)),
            parseChunk(chunk.sublist(middle)),
          ]);
          return;
        }
        status = 'Error: $error';
        skipReasons[chunk.first['body'] as String] = 'parse_error';
        skipCount++;
      }
    }

    final chunks = <List<Map<String, dynamic>>>[];
    for (
      var index = 0;
      index < smsList.length;
      index += OllamaCloudService.maxBatchSize
    ) {
      chunks.add(
        smsList.sublist(
          index,
          (index + OllamaCloudService.maxBatchSize).clamp(0, smsList.length),
        ),
      );
    }
    // Two large requests in flight outperform many tiny calls without causing
    // the queue pressure and 429/503 errors of unbounded concurrency.
    for (var index = 0; index < chunks.length; index += 2) {
      await Future.wait(
        chunks
            .sublist(index, (index + 2).clamp(0, chunks.length))
            .map(parseChunk),
      );
    }

    await _logResult(
      batchSize: smsList.length,
      expenses: expenseCount,
      skipped: skipCount,
      status: status,
    );
    cloud.close();
    return SmsBatchResult(expenses: expenses, skipReasons: skipReasons);
  }

  Future<void> _logResult({
    required int batchSize,
    required int expenses,
    required int skipped,
    required String status,
  }) async {
    try {
      await DatabaseHelper.instance.insertAiLog(
        AiLog(
          requestPrompt:
              '[Ollama Cloud · $model @ $baseUrl]\n$batchSize SMS messages processed',
          responseBody: 'Extracted $expenses expenses, skipped $skipped',
          timestamp: DateTime.now(),
          status: status,
        ),
      );
    } catch (_) {}
  }
}
