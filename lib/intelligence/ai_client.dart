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
        // Sent for providers that enforce it. Measured against Ollama Cloud
        // with gpt-oss it changes nothing: output is byte-identical with and
        // without it, so the system prompt is what actually holds the shape
        // and the recovery path below is not redundant.
        'format': IngestionPrompt.responseSchema,
        // Low, never false. Disabling reasoning on this model does not
        // shorten it: measured, "false" produced roughly 5,500 characters of
        // reasoning against 190 for "low", exhausting the output budget
        // before any content was emitted, so every batch came back empty.
        'think': 'low',
        'keep_alive': '10m',
        'options': {
          'temperature': 0,
          // Twelve messages measured at about 780 output tokens. The floor
          // keeps headroom for a verbose reasoning run on a small batch,
          // where an exhausted budget yields empty content rather than a
          // short answer.
          'num_predict': _outputBudget(candidates.length),
        },
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
          // An empty content field alongside a populated thinking field means
          // reasoning consumed the whole output budget. Saying so points at
          // the setting that fixes it instead of implying the messages were
          // unclassifiable.
          final reasoned =
              decoded is Map &&
              decoded['message'] is Map &&
              ((decoded['message'] as Map)['thinking']?.toString() ?? '')
                  .trim()
                  .isNotEmpty;
          throw IngestionSchemaException(
            reasoned
                ? 'The provider spent its whole response on reasoning and '
                      'returned no classifications. Try a smaller batch.'
                : 'The provider returned no classifications.',
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
        // The agent loop genuinely plans: it picks tools, sequences them and
        // decides when it has enough evidence. Low effort keeps first-token
        // latency down while retaining that planning.
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
      // Read rather than drain: the body carries the reason. A retired model
      // answers 410 with the name and retirement date, which is the whole
      // explanation, and discarding it left only a status code to report.
      final body = await streamed.stream.bytesToString();
      throw AiRequestFailure(streamed.statusCode, _providerError(body));
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
  const AiRequestFailure(this.statusCode, [this.detail]);
  final int statusCode;

  /// What the provider said went wrong, when it said anything.
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'Provider error $statusCode.' : detail!;
}

/// Output token budget for a batch of [messageCount] messages.
int _outputBudget(int messageCount) {
  final scaled = 200 * messageCount + 512;
  return scaled < 1024 ? 1024 : scaled;
}

/// Extracts the human-readable reason from a provider error body.
String? _providerError(String body) {
  final text = body.trim();
  if (text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['error'] != null) {
      final message = decoded['error'].toString().trim();
      if (message.isNotEmpty) return message;
    }
  } on FormatException {
    // Not JSON; fall through and use a bounded slice of the raw body.
  }
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}
