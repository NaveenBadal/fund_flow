import 'dart:convert';
import 'package:http/http.dart' as http;

class AiClient {
  AiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  Uri _uri(String endpoint) {
    final base = endpoint.endsWith('/')
        ? endpoint.substring(0, endpoint.length - 1)
        : endpoint;
    return Uri.parse('$base/api/chat');
  }

  Future<bool> validate({
    required String endpoint,
    required String apiKey,
    required String model,
  }) async {
    try {
      final response = await _client
          .post(
            _uri(endpoint),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'stream': false,
              'messages': [
                {'role': 'user', 'content': 'Reply with OK only.'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<String> answer({
    required String endpoint,
    required String apiKey,
    required String model,
    required String question,
    required String context,
  }) async {
    final response = await _client
        .post(
          _uri(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'stream': false,
            'messages': [
              {
                'role': 'system',
                'content':
                    'You are Fund Flow. Answer briefly using only the supplied locally computed context. Never combine currencies. If context is insufficient, say so. Context:\n$context',
              },
              {'role': 'user', 'content': question},
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestFailure(response.statusCode);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = (decoded['message'] as Map?)?['content']?.toString().trim();
    if (text == null || text.isEmpty) {
      throw const FormatException('Empty AI answer');
    }
    return text;
  }

  void close() => _client.close();
}

class AiRequestFailure implements Exception {
  const AiRequestFailure(this.statusCode);
  final int statusCode;
}
