import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent/agent_runner.dart';
import '../agent/mcp_protocol.dart';
import '../ingestion/ai_message_ingestion.dart' show IngestionSchemaException;
import 'ai_failure.dart';

/// Native adapter for the OpenAI chat-completions wire.
///
/// Serves OpenAI directly and Sarvam, whose own chat API is the same shape.
/// Uses `max_completion_tokens` (accepted by classic and required by
/// reasoning-tier models) and omits `temperature` (reasoning models reject any
/// value but the default), so one code path covers every model family.
class OpenAiAdapter {
  const OpenAiAdapter(this._client, {required this.base, required this.apiKey});
  final http.Client _client;

  /// Chat-completions root, e.g. `https://api.openai.com/v1`.
  final String base;
  final String apiKey;

  Uri get _chatUri => Uri.parse('$base/chat/completions');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  Future<bool> validate(String model) async {
    try {
      final response = await _client
          .post(
            _chatUri,
            headers: _headers,
            body: jsonEncode({
              'model': model,
              'max_completion_tokens': 16,
              'messages': [
                {'role': 'user', 'content': 'Reply with OK only.'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 25));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// One structured-JSON completion, returning the assistant text. Retries the
  /// same retryable statuses the Ollama path does.
  Future<String> completeJson({
    required String model,
    required List<Map<String, Object?>> messages,
    required int maxTokens,
    void Function(String requestJson)? onRequest,
    void Function(String responseJson)? onResponse,
  }) async {
    final body = jsonEncode({
      'model': model,
      'max_completion_tokens': maxTokens,
      'response_format': {'type': 'json_object'},
      'messages': messages,
    });
    http.Response? response;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      onRequest?.call(body);
      try {
        response = await _client
            .post(_chatUri, headers: _headers, body: body)
            .timeout(const Duration(seconds: 60));
        onResponse?.call(response.body);
        final retryable =
            response.statusCode == 429 || response.statusCode >= 500;
        if (!retryable) break;
        lastError = AiRequestFailure(
          response.statusCode,
          _errorOf(response.body),
        );
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
      throw lastError ??
          AiRequestFailure(response?.statusCode ?? 0, _errorOf(response?.body));
    }
    final content = _contentOf(response.body);
    if (content == null || content.trim().isEmpty) {
      throw const IngestionSchemaException(
        'The provider returned no classifications.',
      );
    }
    return content;
  }

  static String? _contentOf(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final choices = decoded['choices'];
        if (choices is List && choices.isNotEmpty) {
          final message = (choices.first as Map)['message'];
          if (message is Map) return message['content']?.toString();
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

/// Streaming agent turn over OpenAI chat-completions. Accumulates content and
/// tool-call deltas (which arrive fragmented across SSE chunks, keyed by
/// index) into a single assistant turn.
class OpenAiAgentProvider implements AgentProvider {
  const OpenAiAgentProvider({
    required http.Client client,
    required this.base,
    required this.apiKey,
    required this.model,
  }) : _client = client;

  final http.Client _client;
  final String base;
  final String apiKey;
  final String model;

  @override
  Future<ProviderTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<McpToolDefinition> tools,
    void Function(String delta)? onContentDelta,
    AgentCancellationToken? cancellation,
  }) async {
    final request = http.Request('POST', Uri.parse('$base/chat/completions'))
      ..headers.addAll({
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'stream_options': {'include_usage': true},
        'max_completion_tokens': 1200,
        'messages': _sanitize(messages),
        'tools': tools.map((tool) => tool.toProviderJson()).toList(),
      });
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw AiRequestFailure(streamed.statusCode, _errorOf(body));
    }

    final contentBuffer = StringBuffer();
    // Tool-call fragments keyed by their streamed index.
    final calls = <int, _ToolCallDraft>{};
    ProviderMetrics? metrics;

    void handleData(String data) {
      if (data == '[DONE]') return;
      final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return;
      }
      if (decoded is! Map) return;
      final usage = decoded['usage'];
      if (usage is Map) {
        metrics = ProviderMetrics(
          promptTokens: (usage['prompt_tokens'] as num?)?.toInt(),
          outputTokens: (usage['completion_tokens'] as num?)?.toInt(),
        );
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) return;
      final delta = (choices.first as Map)['delta'];
      if (delta is! Map) return;
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        contentBuffer.write(content);
        onContentDelta?.call(content);
      }
      final toolCalls = delta['tool_calls'];
      if (toolCalls is List) {
        for (final raw in toolCalls) {
          if (raw is! Map) continue;
          final index = (raw['index'] as num?)?.toInt() ?? 0;
          final draft = calls.putIfAbsent(index, _ToolCallDraft.new);
          final id = raw['id'];
          if (id is String && id.isNotEmpty) draft.id = id;
          final function = raw['function'];
          if (function is Map) {
            final name = function['name'];
            if (name is String && name.isNotEmpty) draft.name = name;
            final args = function['arguments'];
            if (args is String) draft.arguments.write(args);
          }
        }
      }
    }

    await _readSse(streamed.stream, handleData, cancellation);

    final ordered = calls.keys.toList()..sort();
    final toolCalls = <McpToolCall>[];
    final rawCalls = <Map<String, Object?>>[];
    for (final index in ordered) {
      final draft = calls[index]!;
      final id = draft.id ?? 'call_$index';
      final argsText = draft.arguments.toString();
      rawCalls.add({
        'id': id,
        'type': 'function',
        'function': {'name': draft.name, 'arguments': argsText},
      });
      Map<String, Object?> args;
      try {
        final parsed = argsText.trim().isEmpty ? {} : jsonDecode(argsText);
        args = parsed is Map ? Map<String, Object?>.from(parsed) : {};
      } on FormatException {
        args = {};
      }
      toolCalls.add(
        McpToolCall(id: id, name: draft.name ?? '', arguments: args),
      );
    }

    final content = contentBuffer.toString();
    final message = <String, Object?>{
      'role': 'assistant',
      'content': content,
      if (rawCalls.isNotEmpty) 'tool_calls': rawCalls,
    };
    return ProviderTurn(
      message: message,
      content: content,
      toolCalls: toolCalls,
      metrics: metrics,
    );
  }
}

class _ToolCallDraft {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

/// Reduces canonical messages to the exact fields OpenAI accepts — dropping
/// Ollama-only extras (`thinking`, `tool_name`) that a provider switch may
/// have left in the history, and mapping tool results to `tool_call_id`.
List<Map<String, Object?>> _sanitize(List<Map<String, Object?>> messages) {
  return [
    for (final message in messages)
      switch (message['role']) {
        'tool' => {
          'role': 'tool',
          'tool_call_id': message['tool_call_id'],
          'content': message['content'],
        },
        'assistant' => {
          'role': 'assistant',
          // Sarvam rejects an empty-string content alongside tool_calls; null
          // is what both it and OpenAI accept for a tools-only turn.
          'content':
              (message['tool_calls'] != null &&
                  (message['content'] as String? ?? '').isEmpty)
              ? null
              : (message['content'] ?? ''),
          if (message['tool_calls'] != null)
            'tool_calls': message['tool_calls'],
        },
        _ => {'role': message['role'], 'content': message['content']},
      },
  ];
}

/// Reads an SSE body, calling [onData] with each `data:` payload. Honors
/// cancellation and reassembles lines split across chunks.
Future<void> _readSse(
  Stream<List<int>> stream,
  void Function(String data) onData,
  AgentCancellationToken? cancellation,
) async {
  final iterator = StreamIterator<String>(
    stream.transform(utf8.decoder).timeout(const Duration(seconds: 45)),
  );
  var carry = '';
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
        final line = carry.substring(0, newline).trimRight();
        carry = carry.substring(newline + 1);
        if (line.startsWith('data:')) {
          onData(line.substring(5).trim());
        }
        newline = carry.indexOf('\n');
      }
    }
  } finally {
    await iterator.cancel();
  }
}

String? _errorOf(String? body) {
  if (body == null) return null;
  final text = body.trim();
  if (text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['error'] != null) {
      final error = decoded['error'];
      final message = error is Map ? error['message'] : error;
      final text = message?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
  } on FormatException {
    // Not JSON; fall through.
  }
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}
