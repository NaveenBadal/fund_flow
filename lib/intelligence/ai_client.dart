import 'dart:convert';
import '../agent/agent_runner.dart';
import '../agent/mcp_protocol.dart';
import '../domain/transaction.dart';
import '../ingestion/ai_message_ingestion.dart';
import '../ingestion/message_candidate.dart';
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

  Future<AiReply> answer({
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
                    'You are Fund Flow. Use only the supplied locally computed context and never combine currencies. Return only JSON shaped as {"answer":"brief answer","change":null}. If the person explicitly asks to recategorize exactly one listed transaction, change may instead be {"transactionId":123,"category":"New category"}. Never propose any other mutation. Context:\n$context',
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
    return AiReply.parse(text);
  }

  AgentProvider configured({
    required String endpoint,
    required String apiKey,
    required String model,
  }) => _ConfiguredAiProvider(
    client: _client,
    uri: _uri(endpoint),
    apiKey: apiKey,
    model: model,
  );

  Future<AiIngestionBatch> analyzeMessages({
    required String endpoint,
    required String apiKey,
    required String model,
    required List<MessageCandidate> candidates,
    required TransactionSource source,
    required DateTime now,
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
            'format': IngestionPrompt.responseSchema,
            'messages': [
              {'role': 'system', 'content': IngestionPrompt.system(now)},
              {'role': 'user', 'content': IngestionPrompt.user(candidates)},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestFailure(response.statusCode);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (decoded['message'] as Map?)?['content']?.toString();
    if (content == null || content.trim().isEmpty) {
      throw const IngestionSchemaException(
        'The provider returned no classifications.',
      );
    }
    return AiIngestionBatch.parse(
      content: content,
      candidates: candidates,
      source: source,
      now: now,
    );
  }

  void close() => _client.close();
}

class _ConfiguredAiProvider implements AgentProvider {
  const _ConfiguredAiProvider({
    required http.Client client,
    required Uri uri,
    required String apiKey,
    required String model,
  }) : _client = client,
       _uri = uri,
       _apiKey = apiKey,
       _model = model;

  final http.Client _client;
  final Uri _uri;
  final String _apiKey;
  final String _model;

  @override
  Future<ProviderTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<McpToolDefinition> tools,
  }) async {
    final response = await _client
        .post(
          _uri,
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': _model,
            'stream': false,
            'messages': messages,
            'tools': tools.map((tool) => tool.toProviderJson()).toList(),
          }),
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiRequestFailure(response.statusCode);
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawMessage = decoded['message'];
    if (rawMessage is! Map) throw const FormatException('Missing AI message');
    final message = Map<String, Object?>.from(rawMessage);
    final rawCalls = message['tool_calls'];
    final calls = <McpToolCall>[];
    if (rawCalls is List) {
      for (var index = 0; index < rawCalls.length; index++) {
        calls.add(
          McpToolCall.fromProviderJson(
            Map<Object?, Object?>.from(rawCalls[index] as Map),
            index,
          ),
        );
      }
    }
    return ProviderTurn(
      message: message,
      content: message['content']?.toString() ?? '',
      toolCalls: calls,
    );
  }
}

class AiReply {
  const AiReply({required this.answer, this.categoryChange});
  final String answer;
  final AiCategoryChange? categoryChange;

  factory AiReply.parse(String text) {
    try {
      final payload = jsonDecode(text) as Map<String, dynamic>;
      final answer = payload['answer']?.toString().trim();
      if (answer == null || answer.isEmpty) throw const FormatException();
      final rawChange = payload['change'];
      AiCategoryChange? change;
      if (rawChange is Map) {
        final id = rawChange['transactionId'];
        final category = rawChange['category']?.toString().trim();
        if (id is num && category != null && category.isNotEmpty) {
          change = AiCategoryChange(id.toInt(), category);
        }
      }
      return AiReply(answer: answer, categoryChange: change);
    } catch (_) {
      return AiReply(answer: text);
    }
  }
}

class AiCategoryChange {
  const AiCategoryChange(this.transactionId, this.category);
  final int transactionId;
  final String category;
}

class AiRequestFailure implements Exception {
  const AiRequestFailure(this.statusCode);
  final int statusCode;
}
