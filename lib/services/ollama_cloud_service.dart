import 'dart:convert';

import 'package:http/http.dart' as http;

class OllamaParseResult {
  const OllamaParseResult({
    required this.type,
    this.amount,
    this.merchant,
    this.category,
  });

  final String type;
  final double? amount;
  final String? merchant;
  final String? category;

  bool get isFinancial =>
      type == 'expense' || type == 'income' || type == 'transfer';
}

/// AI-only, batched Ollama Cloud client.
///
/// A batch shares one prompt evaluation, one TLS exchange, and one generated
/// JSON envelope. Stable numeric IDs let callers match responses without
/// depending on model ordering.
class OllamaCloudService {
  OllamaCloudService({
    required this.apiKey,
    this.baseUrl = 'https://ollama.com',
    this.model = 'gpt-oss:20b-cloud',
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String baseUrl;
  final String model;
  final http.Client _client;

  static const timeout = Duration(seconds: 60);
  static const maxBatchSize = 12;

  bool get hasKey => apiKey.trim().isNotEmpty;

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'Bearer ${apiKey.trim()}',
  };

  static const _systemPrompt =
      'Parse Indian bank/wallet SMS. Return only compact valid JSON. '
      'Every input must produce exactly one result with the same id. '
      'Actual money movement types: expense, income, transfer. '
      'OTP, promotion, balance alert, bill reminder, and statement without a new transaction are not_financial. '
      'Categories: Food, Transport, Utilities, Entertainment, Shopping, Health, Others. '
      'Amount must be a JSON number in INR or null. No markdown or explanation.';

  Future<Map<int, OllamaParseResult>> parseBatch(List<String> smsBodies) async {
    if (!hasKey) throw StateError('Ollama Cloud API key is not set.');
    if (smsBodies.isEmpty) return const {};
    if (smsBodies.length > maxBatchSize) {
      throw ArgumentError(
        'A batch may contain at most $maxBatchSize messages.',
      );
    }

    final inputs = [
      for (var index = 0; index < smsBodies.length; index++)
        {'id': index, 'sms': smsBodies[index]},
    ];
    final prompt =
        '${jsonEncode(inputs)}\n'
        'Output: {"results":[{"id":0,"type":"expense|income|transfer|not_financial",'
        '"amount":123.45,"merchant":"name or null","category":"category or null"}]}';

    final response = await _withRetry(
      () => _client
          .post(
            Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/chat'),
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': _systemPrompt},
                {'role': 'user', 'content': prompt},
              ],
              'stream': false,
              'think': 'low',
              'keep_alive': '10m',
              'options': {'temperature': 0.0, 'num_predict': 1200},
            }),
          )
          .timeout(timeout),
    );

    if (response.statusCode != 200) {
      throw OllamaRequestException(response.statusCode, response.body);
    }
    final outer = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (outer['message'] as Map<String, dynamic>?)?['content'] as String? ??
        '';
    return _decodeBatch(content, smsBodies.length);
  }

  Future<OllamaParseResult> parse(String smsBody) async =>
      (await parseBatch([smsBody]))[0] ??
      (throw const FormatException('Missing result 0'));

  /// Grounded free-form answer used by the in-app financial copilot.
  Future<String> answer({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    if (!hasKey) throw StateError('Ollama Cloud API key is not set.');
    final response = await _withRetry(
      () => _client
          .post(
            Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/chat'),
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userPrompt},
              ],
              'stream': false,
              'think': 'medium',
              'options': {'temperature': .1, 'num_predict': 900},
            }),
          )
          .timeout(timeout),
    );
    if (response.statusCode != 200) {
      throw OllamaRequestException(response.statusCode, response.body);
    }
    final outer = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (outer['message'] as Map<String, dynamic>?)?['content']
        ?.toString()
        .trim();
    if (content == null || content.isEmpty) {
      throw const FormatException('The model returned an empty answer.');
    }
    return content;
  }

  Map<int, OllamaParseResult> _decodeBatch(String raw, int expectedCount) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('```')) {
      cleaned = cleaned
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('Model returned no JSON object.');
    }

    final envelope =
        jsonDecode(cleaned.substring(start, end + 1)) as Map<String, dynamic>;
    final rawResults = envelope['results'];
    if (rawResults is! List) {
      throw const FormatException('Model response has no results array.');
    }

    const validTypes = {'expense', 'income', 'transfer', 'not_financial'};
    final results = <int, OllamaParseResult>{};
    for (final rawResult in rawResults) {
      if (rawResult is! Map) continue;
      final item = Map<String, dynamic>.from(rawResult);
      final id = _toInt(item['id']);
      final type = item['type']?.toString().toLowerCase().trim();
      if (id == null ||
          id < 0 ||
          id >= expectedCount ||
          type == null ||
          !validTypes.contains(type) ||
          results.containsKey(id)) {
        continue;
      }
      final merchant = _nullableText(item['merchant']);
      final category = _normalizeCategory(_nullableText(item['category']));
      results[id] = OllamaParseResult(
        type: type,
        amount: _toDouble(item['amount']),
        merchant: merchant,
        category: category,
      );
    }
    if (results.isEmpty) {
      throw const FormatException('Model returned no valid results.');
    }
    return results;
  }

  Future<http.Response> _withRetry(
    Future<http.Response> Function() request,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await request();
        if (response.statusCode != 429 &&
            response.statusCode != 502 &&
            response.statusCode != 503 &&
            response.statusCode < 500) {
          return response;
        }
        lastError = OllamaRequestException(response.statusCode, response.body);
      } catch (error) {
        lastError = error;
      }
      if (attempt < 2) {
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (1 << attempt)),
        );
      }
    }
    throw lastError ?? Exception('Ollama request failed');
  }

  Future<bool> validateKey() async {
    if (!hasKey) return false;
    try {
      final response = await _client
          .get(
            Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/tags'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static int? _toInt(dynamic value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
  static double? _toDouble(dynamic value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().replaceAll(',', '') ?? '');
  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text.toLowerCase() == 'null'
        ? null
        : text;
  }

  static String? _normalizeCategory(String? value) {
    if (value == null) return null;
    const categories = [
      'Food',
      'Transport',
      'Utilities',
      'Entertainment',
      'Shopping',
      'Health',
      'Others',
    ];
    for (final category in categories) {
      if (category.toLowerCase() == value.toLowerCase()) return category;
    }
    return 'Others';
  }
}

class OllamaRequestException implements Exception {
  const OllamaRequestException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'Ollama HTTP $statusCode: $body';
}
