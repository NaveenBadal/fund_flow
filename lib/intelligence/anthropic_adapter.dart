import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent/agent_runner.dart';
import '../agent/mcp_protocol.dart';
import '../ingestion/ai_message_ingestion.dart' show IngestionSchemaException;
import 'ai_failure.dart';
import 'gemini_adapter.dart' show errorOf, readSse;

/// Native adapter for Anthropic's Messages API — the long-term production path
/// the user asked for. Translates the canonical OpenAI-shaped history into
/// Claude's content-block shape (`tool_use` / `tool_result`) and back.
class AnthropicAdapter {
  const AnthropicAdapter(
    this._client, {
    required this.base,
    required this.apiKey,
  });
  final http.Client _client;
  final String base;
  final String apiKey;

  static const _version = '2023-06-01';

  Uri get _uri => Uri.parse('$base/v1/messages');
  Map<String, String> get headers => {
    'x-api-key': apiKey,
    'anthropic-version': _version,
    'Content-Type': 'application/json',
  };

  Future<bool> validate(String model) async {
    try {
      final response = await _client
          .post(
            _uri,
            headers: headers,
            body: jsonEncode({
              'model': model,
              'max_tokens': 16,
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

  Future<String> completeJson({
    required String model,
    required List<Map<String, Object?>> messages,
    required int maxTokens,
    void Function(String requestJson)? onRequest,
    void Function(String responseJson)? onResponse,
  }) async {
    final translated = translateMessages(messages);
    final body = jsonEncode({
      'model': model,
      'max_tokens': maxTokens,
      if (translated.system != null) 'system': translated.system,
      'messages': translated.messages,
    });
    http.Response? response;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      onRequest?.call(body);
      try {
        response = await _client
            .post(_uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 60));
        onResponse?.call(response.body);
        final retryable =
            response.statusCode == 429 || response.statusCode >= 500;
        if (!retryable) break;
        lastError = AiRequestFailure(
          response.statusCode,
          errorOf(response.body),
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
          AiRequestFailure(response?.statusCode ?? 0, errorOf(response?.body));
    }
    final text = _textOf(response.body);
    if (text == null || text.trim().isEmpty) {
      throw const IngestionSchemaException(
        'The provider returned no classifications.',
      );
    }
    return text;
  }

  static String? _textOf(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['content'] is List) {
        final buffer = StringBuffer();
        for (final block in decoded['content'] as List) {
          if (block is Map && block['type'] == 'text') {
            buffer.write(block['text']);
          }
        }
        return buffer.toString();
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class AnthropicMessages {
  const AnthropicMessages(this.messages, this.system);
  final List<Map<String, Object?>> messages;
  final String? system;
}

/// Maps canonical OpenAI-shaped messages to Claude's content-block shape,
/// hoisting the system prompt and merging consecutive tool results into one
/// user turn (Claude expects all `tool_result` blocks for a turn together).
AnthropicMessages translateMessages(List<Map<String, Object?>> source) {
  final out = <Map<String, Object?>>[];
  final systemParts = <String>[];
  for (final message in source) {
    final role = message['role'];
    switch (role) {
      case 'system':
        final content = message['content'];
        if (content is String) systemParts.add(content);
      case 'tool':
        final block = {
          'type': 'tool_result',
          'tool_use_id': message['tool_call_id']?.toString() ?? '',
          'content': message['content']?.toString() ?? '',
        };
        // Append to a trailing user turn built from tool results, else start
        // one.
        if (out.isNotEmpty &&
            out.last['role'] == 'user' &&
            out.last['_toolResults'] == true) {
          (out.last['content'] as List).add(block);
        } else {
          out.add({
            'role': 'user',
            'content': [block],
            '_toolResults': true,
          });
        }
      case 'assistant':
        final blocks = <Map<String, Object?>>[];
        final content = message['content'];
        if (content is String && content.trim().isNotEmpty) {
          blocks.add({'type': 'text', 'text': content});
        }
        final toolCalls = message['tool_calls'];
        if (toolCalls is List) {
          for (final call in toolCalls) {
            if (call is! Map) continue;
            final function = call['function'];
            if (function is! Map) continue;
            Object input = <String, Object?>{};
            final raw = function['arguments'];
            if (raw is String && raw.trim().isNotEmpty) {
              try {
                input = jsonDecode(raw) as Object;
              } on FormatException {
                input = <String, Object?>{};
              }
            }
            blocks.add({
              'type': 'tool_use',
              'id': call['id']?.toString() ?? '',
              'name': function['name'],
              'input': input,
            });
          }
        }
        if (blocks.isNotEmpty)
          out.add({'role': 'assistant', 'content': blocks});
      default: // user
        final content = message['content'];
        out.add({
          'role': 'user',
          'content': content is String ? content : jsonEncode(content),
        });
    }
  }
  // Strip the private marker before sending.
  for (final message in out) {
    message.remove('_toolResults');
  }
  return AnthropicMessages(
    out,
    systemParts.isEmpty ? null : systemParts.join('\n\n'),
  );
}

/// Streaming agent turn over the Messages API. Accumulates `text_delta` into
/// content and `input_json_delta` fragments into each `tool_use` block's input.
class AnthropicAgentProvider implements AgentProvider {
  const AnthropicAgentProvider({
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
    final translated = translateMessages(messages);
    final request = http.Request('POST', Uri.parse('$base/v1/messages'))
      ..headers.addAll({
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode({
        'model': model,
        'max_tokens': 1200,
        'stream': true,
        if (translated.system != null) 'system': translated.system,
        'messages': translated.messages,
        'tools': tools
            .map(
              (tool) => {
                'name': tool.name,
                'description': tool.description,
                'input_schema': tool.inputSchema,
              },
            )
            .toList(),
      });
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw AiRequestFailure(streamed.statusCode, errorOf(body));
    }

    final contentBuffer = StringBuffer();
    // Per content-block index: the block being assembled.
    final blocks = <int, _BlockDraft>{};
    ProviderMetrics? metrics;

    void handleData(String data) {
      final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return;
      }
      if (decoded is! Map) return;
      switch (decoded['type']) {
        case 'content_block_start':
          final index = (decoded['index'] as num?)?.toInt() ?? 0;
          final block = decoded['content_block'];
          if (block is Map && block['type'] == 'tool_use') {
            blocks[index] = _BlockDraft()
              ..id = block['id']?.toString()
              ..name = block['name']?.toString();
          }
        case 'content_block_delta':
          final index = (decoded['index'] as num?)?.toInt() ?? 0;
          final delta = decoded['delta'];
          if (delta is! Map) return;
          if (delta['type'] == 'text_delta') {
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              contentBuffer.write(text);
              onContentDelta?.call(text);
            }
          } else if (delta['type'] == 'input_json_delta') {
            final partial = delta['partial_json'];
            if (partial is String) {
              (blocks[index] ??= _BlockDraft()).arguments.write(partial);
            }
          }
        case 'message_delta':
          final usage = decoded['usage'];
          if (usage is Map) {
            metrics = ProviderMetrics(
              outputTokens: (usage['output_tokens'] as num?)?.toInt(),
            );
          }
      }
    }

    await readSse(streamed.stream, handleData, cancellation);

    final ordered = blocks.keys.toList()..sort();
    final toolCalls = <McpToolCall>[];
    final rawCalls = <Map<String, Object?>>[];
    for (final index in ordered) {
      final draft = blocks[index]!;
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
    return ProviderTurn(
      message: {
        'role': 'assistant',
        'content': content,
        if (rawCalls.isNotEmpty) 'tool_calls': rawCalls,
      },
      content: content,
      toolCalls: toolCalls,
      metrics: metrics,
    );
  }
}

class _BlockDraft {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
