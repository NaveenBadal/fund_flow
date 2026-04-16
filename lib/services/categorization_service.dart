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

  Future<List<Expense>> parseSmsBatch(List<Map<String, dynamic>> smsList) async {
    if (smsList.isEmpty) return [];

    final isOnDevice = provider == AiProviderType.offline ||
        provider == AiProviderType.flutterGemma;

    if (isOnDevice && smsList.length > _onDeviceChunkSize) {
      // Process in chunks and aggregate results.
      final results = <Expense>[];
      for (var i = 0; i < smsList.length; i += _onDeviceChunkSize) {
        final chunk = smsList.sublist(
          i,
          (i + _onDeviceChunkSize).clamp(0, smsList.length),
        );
        // Re-index within chunk but keep a local→global offset for date/body lookup.
        final chunkExpenses = await _parseSingleBatch(chunk, globalOffset: i);
        results.addAll(chunkExpenses);
      }
      return results;
    }

    return _parseSingleBatch(smsList, globalOffset: 0);
  }

  Future<List<Expense>> _parseSingleBatch(
    List<Map<String, dynamic>> smsList, {
    required int globalOffset,
  }) async {
    final smsDataString = smsList.asMap().entries.map((e) {
      return 'ID: ${e.key} | Date: ${e.value['date']} | Msg: ${e.value['body']}';
    }).join('\n');

    final prompt = '''
Analyze these SMS messages for financial transactions.
For each message, determine if it is a valid Expense or Income.

Return your response in JSON format with a key "transactions" containing a list of objects or arrays.
Each transaction should have: ID, type ("expense" or "income"), amount, currency, merchant, and category.

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

      // Sanitize: strip null bytes, ASCII control characters (keep \t \n \r),
      // and markdown code fences that on-device models commonly emit.
      responseText = _sanitizeModelResponse(responseText);

      // Try to extract a nested JSON array [[...], ...].
      // On-device models often omit commas between rows or even the outer
      // wrapper, so we handle those cases too.
      String jsonText;
      final outerMatch = RegExp(r'\[\s*\[.*\]\s*\]', dotAll: true).firstMatch(responseText);
      if (outerMatch != null) {
        jsonText = outerMatch.group(0)!;
      } else {
        // Fallback: collect individual [...] rows and wrap them.
        final rows = RegExp(r'\[.+?\]').allMatches(responseText).map((m) => m.group(0)!).toList();
        if (rows.isEmpty) {
          status = 'Error: No valid JSON array of arrays found in response';
          return [];
        }
        jsonText = '[${rows.join(',')}]';
      }

      // Fix missing commas between consecutive ][ (very common with LiteRT).
      jsonText = jsonText.replaceAll(RegExp(r'\]\s*\['), '],[');

      final decoded = json.decode(jsonText);
      final List<dynamic> batchData;
      if (decoded is Map && decoded.containsKey('transactions')) {
        batchData = decoded['transactions'];
      } else if (decoded is List) {
        batchData = decoded;
      } else {
        status = 'Error: Unexpected JSON structure';
        return [];
      }

      final expenses = <Expense>[];

      for (final entry in batchData) {
        try {
          final int localId;
          final String type;
          final double amount;
          final String currency;
          final String merchant;
          final String category;

          if (entry is List) {
            localId = entry[0];
            type = entry[1];
            // Handle amount being a string or number
            final rawAmount = entry[2];
            amount = rawAmount is num ? rawAmount.toDouble() : double.tryParse(rawAmount.toString()) ?? 0.0;
            currency = entry[3];
            merchant = entry[4];
            category = entry[5];
          } else if (entry is Map) {
            localId = entry['ID'] ?? entry['id'];
            type = entry['type'];
            final rawAmount = entry['amount'];
            amount = rawAmount is num ? rawAmount.toDouble() : double.tryParse(rawAmount.toString()) ?? 0.0;
            currency = entry['currency'];
            merchant = entry['merchant'];
            category = entry['category'];
          } else {
            continue;
          }

          if (localId < 0 || localId >= smsList.length) continue;
          if (type == 'expense' || type == 'income') {
            // Normalize merchant name
            final normalized = MerchantNormalizer.normalize(merchant);

            // Check if we have a learned category for this merchant
            String finalCategory = category;
            try {
              final learnedMap = await DatabaseHelper.instance.getMerchantCategoryMap();
              final learnedCategory = learnedMap[normalized.toLowerCase().trim()];
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
              originalSms: smsList[localId]['body'],
              type: type,
            ));
          }
        } catch (_) {
          // Skip malformed entries
        }
      }

      return expenses;
    } catch (e) {
      status = 'Error: $e';
      responseText = _sanitizeModelResponse('Exception occurred: $e');
      return [];
    } finally {
      // Guarded so a DB failure here can never propagate and kill the sync.
      try {
        final displayModelName = provider == AiProviderType.flutterGemma
            ? modelName.split('/').last
            : modelName;
        // Truncate responseBody to a reasonable size before storing.
        final safeResponse = responseText.length > 4000
            ? '${responseText.substring(0, 4000)}…'
            : responseText;
        await DatabaseHelper.instance.insertAiLog(AiLog(
          requestPrompt:
              '[Provider: ${provider.displayName} | Model: $displayModelName${provider == AiProviderType.gemini ? ' | API: $defaultGeminiApiVersion' : ''}]\n${prompt.length > 1000 ? '${prompt.substring(0, 1000)}...' : prompt}',
          responseBody: safeResponse,
          timestamp: DateTime.now(),
          status: status,
        ));
      } catch (_) {
        // Swallow: log insertion failure must never break the callers.
      }
    }
  }

  Future<String> _parseWithGemini(String prompt) async {
    final content = [Content.text(prompt)];
    final response = await _geminiModel!.generateContent(content);
    return response.text ?? '[]';
  }

  Future<String> _parseWithSarvam(String prompt) async {
    final client = HttpClient();

    try {
      final uri = Uri.https('api.sarvam.ai', '/v1/chat/completions');
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set('api-subscription-key', apiKey);
      request.add(utf8.encode(json.encode({
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
        'temperature': 0.2,
        'top_p': 1,
        'max_tokens': 2000,
      })));

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Sarvam chat completions failed (${response.statusCode}): $responseText',
          uri: uri,
        );
      }

      final data = json.decode(responseText) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>? ?? const [];
      final firstChoice = choices.isNotEmpty ? choices.first as Map<String, dynamic> : const <String, dynamic>{};
      final message = firstChoice['message'] as Map<String, dynamic>? ?? const <String, dynamic>{};
      final content = message['content'];
      if (content is String && content.trim().isNotEmpty) {
        return content;
      }

      return '[]';
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
