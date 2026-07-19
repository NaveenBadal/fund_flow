import 'dart:convert';
import 'dart:async';
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
    void Function(String requestJson)? onRequest,
    void Function(String responseJson)? onResponse,
  }) async {
    final baseMessages = <Map<String, Object?>>[
      {'role': 'system', 'content': IngestionPrompt.system(now)},
      {'role': 'user', 'content': IngestionPrompt.user(candidates)},
    ];
    Future<String> send(List<Map<String, Object?>> messages) async {
      final requestBody = jsonEncode({
        'model': model,
        'stream': false,
        'think': 'low',
        'keep_alive': '10m',
        'options': {'temperature': 0, 'num_predict': 1200},
        'messages': messages,
      });
      http.Response? response;
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        onRequest?.call(requestBody);
        try {
          response = await _client
              .post(
                _uri(endpoint),
                headers: {
                  'Authorization': 'Bearer $apiKey',
                  'Content-Type': 'application/json',
                },
                body: requestBody,
              )
              .timeout(const Duration(seconds: 60));
          onResponse?.call(response.body);
          final retryable =
              response.statusCode == 429 ||
              response.statusCode == 502 ||
              response.statusCode == 503 ||
              response.statusCode >= 500;
          if (!retryable) break;
          lastError = AiRequestFailure(response.statusCode);
        } catch (error) {
          lastError = error;
        }
        if (attempt < 2) {
          await Future<void>.delayed(Duration(milliseconds: 300 << attempt));
        }
      }
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw lastError ?? AiRequestFailure(response?.statusCode ?? 0);
      }
      try {
        final decoded = jsonDecode(response.body);
        String? content;
        if (decoded is Map) {
          final message = decoded['message'];
          if (message is Map) content = message['content']?.toString();
          final choices = decoded['choices'];
          if (content == null && choices is List && choices.isNotEmpty) {
            final choice = choices.first;
            if (choice is Map && choice['message'] is Map) {
              content = (choice['message'] as Map)['content']?.toString();
            }
          }
        }
        if (content == null || content.trim().isEmpty) {
          throw const IngestionSchemaException(
            'The provider returned no classifications.',
          );
        }
        return content;
      } on IngestionSchemaException {
        rethrow;
      } on FormatException {
        throw const IngestionSchemaException(
          'The provider response envelope was not valid JSON.',
        );
      }
    }

    final first = await send(baseMessages);
    try {
      return AiIngestionBatch.parse(
        content: first,
        candidates: candidates,
        source: source,
        now: now,
      );
    } on IngestionSchemaException catch (firstError) {
      final repaired = await send([
        ...baseMessages,
        {'role': 'assistant', 'content': first},
        {
          'role': 'user',
          'content':
              'Your previous output was rejected: ${firstError.message} Return the complete corrected JSON object now. Include exactly one result for every supplied id, including non-transactions. Use only the exact schema and field names from the system message.',
        },
      ]);
      try {
        return AiIngestionBatch.parse(
          content: repaired,
          candidates: candidates,
          source: source,
          now: now,
        );
      } on IngestionSchemaException catch (repairError) {
        throw IngestionSchemaException(
          'The provider failed both structured attempts. ${repairError.message}',
        );
      }
    }
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
    void Function(String delta)? onContentDelta,
    AgentCancellationToken? cancellation,
  }) async {
    final request = http.Request('POST', _uri)
      ..headers.addAll({
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'model': _model,
        'stream': true,
        // GPT-OSS cannot disable reasoning completely. Low effort materially
        // improves first-token latency while retaining enough planning for
        // choosing and sequencing local MCP tools.
        'think': 'low',
        'keep_alive': '10m',
        'options': {'temperature': 0, 'num_predict': 1200},
        'messages': messages,
        'tools': tools.map((tool) => tool.toProviderJson()).toList(),
      });
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      // Drain so the connection can be released before surfacing the error.
      await streamed.stream.drain<void>();
      throw AiRequestFailure(streamed.statusCode);
    }

    final contentBuffer = StringBuffer();
    final thinkingBuffer = StringBuffer();
    final rawCalls = <Map<Object?, Object?>>[];
    Object? role;
    var carry = '';
    var completed = false;
    ProviderMetrics? metrics;

    void handleLine(String line) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) return;
      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException {
        throw const FormatException('Ollama returned malformed NDJSON.');
      }
      if (decoded is! Map) return;
      final rawMessage = decoded['message'];
      if (rawMessage is Map) {
        role ??= rawMessage['role'];
        final delta = rawMessage['content'];
        if (delta is String && delta.isNotEmpty) {
          contentBuffer.write(delta);
          onContentDelta?.call(delta);
        }
        final thinking = rawMessage['thinking'];
        if (thinking is String && thinking.isNotEmpty) {
          thinkingBuffer.write(thinking);
        }
        final calls = rawMessage['tool_calls'];
        if (calls is List) {
          for (final call in calls) {
            if (call is Map) rawCalls.add(Map<Object?, Object?>.from(call));
          }
        }
      }
      if (decoded['done'] == true) {
        completed = true;
        final envelope = decoded;
        int? integer(String key) {
          final value = envelope[key];
          return value is num ? value.toInt() : null;
        }

        metrics = ProviderMetrics(
          totalDurationNs: integer('total_duration'),
          loadDurationNs: integer('load_duration'),
          promptTokens: integer('prompt_eval_count'),
          promptDurationNs: integer('prompt_eval_duration'),
          outputTokens: integer('eval_count'),
          outputDurationNs: integer('eval_duration'),
        );
      }
    }

    final iterator = StreamIterator<String>(
      streamed.stream
          .transform(utf8.decoder)
          .timeout(const Duration(seconds: 45)),
    );
    try {
      while (true) {
        final moved = cancellation == null
            ? await iterator.moveNext()
            : await Future.any<bool>([
                iterator.moveNext(),
                cancellation.whenCancelled.then<bool>(
                  (_) => throw const AgentRunCancelled(),
                ),
              ]);
        if (!moved) break;
        carry += iterator.current;
        var newline = carry.indexOf('\n');
        while (newline != -1) {
          handleLine(carry.substring(0, newline));
          carry = carry.substring(newline + 1);
          newline = carry.indexOf('\n');
        }
      }
    } finally {
      await iterator.cancel();
    }
    if (carry.trim().isNotEmpty) handleLine(carry);
    if (!completed) {
      throw const FormatException(
        'Ollama closed the response before marking it complete.',
      );
    }

    final content = contentBuffer.toString();
    final message = <String, Object?>{
      'role': role?.toString() ?? 'assistant',
      'content': content,
      if (thinkingBuffer.isNotEmpty) 'thinking': thinkingBuffer.toString(),
      if (rawCalls.isNotEmpty) 'tool_calls': rawCalls,
    };
    final calls = <McpToolCall>[];
    for (var index = 0; index < rawCalls.length; index++) {
      calls.add(McpToolCall.fromProviderJson(rawCalls[index], index));
    }
    return ProviderTurn(
      message: message,
      content: content,
      toolCalls: calls,
      metrics: metrics,
    );
  }
}

class AiRequestFailure implements Exception {
  const AiRequestFailure(this.statusCode);
  final int statusCode;
}
