import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/ai_provider.dart';
import '../models/expense.dart';
import '../models/ai_log.dart';
import 'database_helper.dart';
import 'flutter_gemma_service.dart';
import 'merchant_normalizer.dart';
import 'offline_model_service.dart';

/// Result of a batch parse: extracted expenses + per-body skip reasons.
class SmsBatchResult {
  const SmsBatchResult({
    required this.expenses,
    required this.skipReasons,
  });

  final List<Expense> expenses;

  /// Maps SMS body text → reason string (e.g. "otp", "promotional",
  /// "balance_alert", "not_financial", "no_response", "parse_error").
  /// Only populated for messages that did NOT produce an expense.
  final Map<String, String> skipReasons;
}

const defaultGeminiApiVersion = 'v1beta';

class CategorizationService {
  final String apiKey;
  final AiProviderType provider;
  final String modelName;
  final int onDeviceMaxTokens;
  GenerativeModel? _geminiModel;
  final OfflineModelService _offlineModelService = const OfflineModelService();
  final FlutterGemmaService _flutterGemmaService = const FlutterGemmaService();

  CategorizationService(
    this.apiKey, {
    required this.provider,
    required this.modelName,
    this.onDeviceMaxTokens = 4096,
  }) {
    if (provider == AiProviderType.gemini) {
      _geminiModel = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        requestOptions: const RequestOptions(apiVersion: defaultGeminiApiVersion),
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
        ),
      );
    }
  }

  // On-device models have a small context window; chunk SMS to stay within it.
  static const _onDeviceChunkSize = 20;

  Future<SmsBatchResult> parseSmsBatch(List<Map<String, dynamic>> smsList) async {
    if (smsList.isEmpty) {
      return const SmsBatchResult(expenses: [], skipReasons: {});
    }

    final isOnDevice = provider == AiProviderType.offline ||
        provider == AiProviderType.flutterGemma;

    if (isOnDevice && smsList.length > _onDeviceChunkSize) {
      final allExpenses = <Expense>[];
      final allReasons = <String, String>{};
      for (var i = 0; i < smsList.length; i += _onDeviceChunkSize) {
        final chunk = smsList.sublist(
          i,
          (i + _onDeviceChunkSize).clamp(0, smsList.length),
        );
        final result = await _parseSingleBatch(chunk, globalOffset: i);
        allExpenses.addAll(result.expenses);
        allReasons.addAll(result.skipReasons);
      }
      return SmsBatchResult(expenses: allExpenses, skipReasons: allReasons);
    }

    return _parseSingleBatch(smsList, globalOffset: 0);
  }

  Future<SmsBatchResult> _parseSingleBatch(
    List<Map<String, dynamic>> smsList, {
    required int globalOffset,
  }) async {
    final smsDataString = smsList.asMap().entries.map((e) {
      return 'ID: ${e.key} | Date: ${e.value['date']} | Msg: ${e.value['body']}';
    }).join('\n');

    final prompt = '''
Analyze these SMS messages. You MUST return one entry for EVERY message ID (0 to ${smsList.length - 1}). Do not omit any ID.

For each message:
- If it is a financial transaction (debit, credit, transfer, payment): type = "expense" or "income"
  Include: ID, type, amount (number), currency, merchant, category
- If it is NOT a transaction: type = "skip"
  Include: ID, type, reason (one of: "otp", "promotional", "balance_alert", "statement", "not_financial")

Return JSON with key "transactions" containing the list. Every ID 0–${smsList.length - 1} must appear.
Valid categories: Food, Transport, Utilities, Entertainment, Shopping, Health, Others.

SMS List:
$smsDataString
''';

    String responseText = '';
    String status = 'Success';

    try {
      responseText = switch (provider) {
        AiProviderType.gemini => await _parseWithGemini(prompt),
        AiProviderType.sarvam => await _parseWithSarvam(prompt),
        AiProviderType.offline => await _parseWithOfflineModel(prompt),
        AiProviderType.flutterGemma => await _parseWithFlutterGemma(prompt),
      };

      responseText = _sanitizeModelResponse(responseText);

      final decoded = _extractJson(responseText);
      final List<dynamic> batchData;

      if (decoded is Map && decoded.containsKey('transactions')) {
        batchData = decoded['transactions'];
      } else if (decoded is List) {
        batchData = decoded;
      } else {
        status = 'Error: No valid JSON found in response';
        final reasons = {for (final s in smsList) s['body'] as String: 'parse_error'};
        return SmsBatchResult(expenses: [], skipReasons: reasons);
      }

      final expenses = <Expense>[];
      final skipReasons = <String, String>{};
      final seenIds = <int>{};

      for (final entry in batchData) {
        try {
          final int localId;
          final String type;

          if (entry is List) {
            localId = _parseInt(entry[0]);
            type = (entry[1] as String? ?? '').toLowerCase();
          } else if (entry is Map) {
            localId = _parseInt(entry['ID'] ?? entry['id']);
            type = ((entry['type'] as String?) ?? '').toLowerCase();
          } else {
            continue;
          }

          if (localId < 0 || localId >= smsList.length) continue;
          seenIds.add(localId);
          final body = smsList[localId]['body'] as String;

          if (type == 'expense' || type == 'income') {
            final double amount;
            final String currency;
            final String merchant;
            final String category;

            if (entry is List) {
              final rawAmount = entry[2];
              amount = rawAmount is num
                  ? rawAmount.toDouble()
                  : double.tryParse(rawAmount.toString()) ?? 0.0;
              currency = entry[3] as String? ?? 'INR';
              merchant = entry[4] as String? ?? '';
              category = entry[5] as String? ?? 'Others';
            } else {
              final e = entry as Map;
              final rawAmount = e['amount'];
              amount = rawAmount is num
                  ? rawAmount.toDouble()
                  : double.tryParse(rawAmount.toString()) ?? 0.0;
              currency = e['currency'] as String? ?? 'INR';
              merchant = e['merchant'] as String? ?? '';
              category = e['category'] as String? ?? 'Others';
            }

            if (amount <= 0) {
              skipReasons[body] = 'zero_amount';
              continue;
            }

            final normalized = MerchantNormalizer.normalize(merchant);
            String finalCategory = category;
            try {
              final learnedMap =
                  await DatabaseHelper.instance.getMerchantCategoryMap();
              final learnedCategory =
                  learnedMap[normalized.toLowerCase().trim()];
              if (learnedCategory != null && learnedCategory.isNotEmpty) {
                finalCategory = learnedCategory;
              }
            } catch (_) {}

            expenses.add(Expense(
              amount: amount,
              currency: currency,
              merchant: merchant,
              normalizedMerchant: normalized != merchant ? normalized : null,
              category: finalCategory,
              date: DateTime.parse(smsList[localId]['date']),
              originalSms: body,
              type: type,
            ));
          } else if (type == 'skip') {
            final reason = entry is Map
                ? (entry['reason'] as String? ?? 'not_financial')
                : 'not_financial';
            skipReasons[body] = reason;
          } else {
            skipReasons[body] = 'unknown_type:$type';
          }
        } catch (_) {}
      }

      for (var i = 0; i < smsList.length; i++) {
        if (!seenIds.contains(i)) {
          skipReasons[smsList[i]['body'] as String] = 'no_response';
        }
      }

      return SmsBatchResult(expenses: expenses, skipReasons: skipReasons);
    } catch (e) {
      status = 'Error: $e';
      responseText = _sanitizeModelResponse('Exception occurred: $e');
      final reasons = {for (final s in smsList) s['body'] as String: 'parse_error'};
      return SmsBatchResult(expenses: [], skipReasons: reasons);
    } finally {
      try {
        final displayModelName = provider == AiProviderType.flutterGemma
            ? modelName.split('/').last
            : modelName;
        final safeResponse = responseText.length > 4000
            ? '${responseText.substring(0, 4000)}…'
            : responseText;
        await DatabaseHelper.instance.insertAiLog(AiLog(
          requestPrompt:
              '[Provider: ${provider.displayName} | Model: $displayModelName]\n${prompt.length > 1000 ? '${prompt.substring(0, 1000)}...' : prompt}',
          responseBody: safeResponse,
          timestamp: DateTime.now(),
          status: status,
        ));
      } catch (_) {}
    }
  }

  static dynamic _extractJson(String text) {
    try {
      return json.decode(text);
    } catch (_) {}

    final startBracket = text.indexOf('[');
    final startBrace = text.indexOf('{');

    int start = -1;
    if (startBracket != -1 && startBrace != -1) {
      start = startBracket < startBrace ? startBracket : startBrace;
    } else {
      start = startBracket != -1 ? startBracket : startBrace;
    }

    if (start == -1) return null;

    final endBracket = text.lastIndexOf(']');
    final endBrace = text.lastIndexOf('}');

    int end = -1;
    if (endBracket != -1 && endBrace != -1) {
      end = endBracket > endBrace ? endBracket : endBrace;
    } else {
      end = endBracket != -1 ? endBracket : endBrace;
    }

    if (end == -1 || end <= start) return null;

    final jsonPart = text.substring(start, end + 1);
    try {
      return json.decode(jsonPart);
    } catch (_) {
      try {
        final fixed = jsonPart
            .replaceAll(RegExp(r'\}\s*\{'), '},{')
            .replaceAll(RegExp(r'\]\s*\['), '],[');
        return json.decode(fixed);
      } catch (_) {
        return null;
      }
    }
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? -1;
  }

  Future<String> _parseWithGemini(String prompt) async {
    final content = [Content.text(prompt)];
    final response = await _geminiModel!.generateContent(content);
    return response.text ?? '[]';
  }

  Future<String> _parseWithSarvam(String prompt) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.https('api.sarvam.ai', '/v1/chat/completions');
      final request = await client.postUrl(uri).timeout(const Duration(seconds: 15));
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('api-subscription-key', apiKey);
      
      final body = {
        'model': modelName,
        'messages': [
          {
            'role': 'system',
            'content': 'Extract financial transactions from SMS. Return only JSON array output. No markdown.',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
        'temperature': 0.1,
        'top_p': 1,
        'max_tokens': 2000,
      };

      request.add(utf8.encode(json.encode(body)));
      final response = await request.close().timeout(const Duration(seconds: 30));
      final responseText = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Sarvam API error (${response.statusCode}): $responseText',
          uri: uri,
        );
      }

      final data = json.decode(responseText) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) return '[]';

      final content = choices.first['message']?['content'];
      return (content is String && content.trim().isNotEmpty) ? content : '[]';
    } on SocketException catch (e) {
      throw Exception('Network error: Check internet connection or DNS. Details: ${e.message}');
    } on TimeoutException {
      throw Exception('Sarvam AI request timed out. The server might be slow.');
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _parseWithOfflineModel(String prompt) async {
    return _offlineModelService.infer(
      modelName: modelName,
      prompt: prompt,
      maxTokens: onDeviceMaxTokens,
    );
  }

  Future<String> _parseWithFlutterGemma(String prompt) async {
    return _flutterGemmaService.infer(
      modelPath: modelName,
      prompt: prompt,
      maxTokens: onDeviceMaxTokens,
    );
  }

  /// Strips characters that on-device models (LiteRT / Gemma) commonly emit
  /// and that would break JSON parsing or SQLite inserts:
  ///  - Null bytes (\x00) and other ASCII control chars (keep \t, \n, \r)
  ///  - Unicode replacement character (U+FFFD)
  ///  - Markdown code-fence markers that wrap the JSON output
  static String _sanitizeModelResponse(String raw) {
    // Remove null bytes and ASCII control characters except \t (\x09),
    // \n (\x0a) and \r (\x0d).
    String cleaned = raw.replaceAll(
      RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'),
      '',
    );
    // Remove Unicode replacement character.
    cleaned = cleaned.replaceAll('\uFFFD', '');
    // Strip markdown code-fences (```json ... ``` or ``` ... ```).
    cleaned = cleaned.replaceAll(
      RegExp(r'```(?:json)?\s*', caseSensitive: false),
      '',
    );
    return cleaned.trim();
  }
}
