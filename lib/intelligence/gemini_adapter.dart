import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../agent/agent_runner.dart';
import '../agent/mcp_protocol.dart';
import '../ingestion/ai_message_ingestion.dart' show IngestionSchemaException;
import 'ai_failure.dart';

/// Native adapter for Google Gemini's `generateContent` API.
///
/// Translates the canonical OpenAI-shaped message history into Gemini's
/// `contents`/`parts` shape and its tool calls back out, so the agent loop and
/// the rest of the app never see the difference.
class GeminiAdapter {
  const GeminiAdapter(this._client, {required this.base, required this.apiKey});
  final http.Client _client;

  /// generateContent root, e.g.
  /// `https://generativelanguage.googleapis.com/v1beta`.
  final String base;
  final String apiKey;

  /// Gemini API keys authenticate via `x-goog-api-key` — the header the API
  /// key flow expects. (Both `AIza…` and newer `AQ.…` keys use it; Bearer is
  /// only for full OAuth access tokens, a flow this app does not use.)
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'x-goog-api-key': apiKey,
  };

  Future<bool> validate(String model) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$base/models/$model:generateContent'),
            headers: headers,
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': 'Reply with OK only.'},
                  ],
                },
              ],
              'generationConfig': {'maxOutputTokens': 16},
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
    final translated = translateContents(messages);
    final body = jsonEncode({
      'contents': translated.contents,
      if (translated.system != null)
        'systemInstruction': {
          'parts': [
            {'text': translated.system},
          ],
        },
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0,
        'maxOutputTokens': maxTokens,
      },
    });
    http.Response? response;
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      onRequest?.call(body);
      try {
        response = await _client
            .post(
              Uri.parse('$base/models/$model:generateContent'),
              headers: headers,
              body: body,
            )
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
      if (decoded is Map) {
        final candidates = decoded['candidates'];
        if (candidates is List && candidates.isNotEmpty) {
          final parts =
              ((candidates.first as Map)['content'] as Map?)?['parts'];
          if (parts is List) {
            final buffer = StringBuffer();
            for (final part in parts) {
              if (part is Map && part['text'] is String) {
                buffer.write(part['text']);
              }
            }
            return buffer.toString();
          }
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

/// Result of translating the canonical history into Gemini's shape.
class GeminiContents {
  const GeminiContents(this.contents, this.system);
  final List<Map<String, Object?>> contents;
  final String? system;
}

/// Maps canonical OpenAI-shaped messages to Gemini `contents` + a hoisted
/// `systemInstruction`.
GeminiContents translateContents(List<Map<String, Object?>> messages) {
  final contents = <Map<String, Object?>>[];
  final systemParts = <String>[];
  for (final message in messages) {
    final role = message['role'];
    switch (role) {
      case 'system':
        final content = message['content'];
        if (content is String) systemParts.add(content);
      case 'tool':
        contents.add({
          'role': 'user',
          'parts': [
            {
              'functionResponse': {
                'name': message['tool_name']?.toString() ?? 'tool',
                'response': {'content': message['content']?.toString() ?? ''},
              },
            },
          ],
        });
      case 'assistant':
        final parts = <Map<String, Object?>>[];
        final content = message['content'];
        if (content is String && content.isNotEmpty) {
          parts.add({'text': content});
        }
        final toolCalls = message['tool_calls'];
        if (toolCalls is List) {
          for (final call in toolCalls) {
            if (call is! Map) continue;
            final function = call['function'];
            if (function is! Map) continue;
            Object? args;
            final raw = function['arguments'];
            if (raw is String && raw.trim().isNotEmpty) {
              try {
                args = jsonDecode(raw);
              } on FormatException {
                args = {};
              }
            }
            parts.add({
              'functionCall': {
                'name': function['name'],
                'args': args ?? <String, Object?>{},
              },
            });
          }
        }
        if (parts.isNotEmpty) contents.add({'role': 'model', 'parts': parts});
      default: // user
        final content = message['content'];
        contents.add({
          'role': 'user',
          'parts': [
            {'text': content is String ? content : jsonEncode(content)},
          ],
        });
    }
  }
  return GeminiContents(
    contents,
    systemParts.isEmpty ? null : systemParts.join('\n\n'),
  );
}

/// Gemini's `functionDeclarations.parameters` accepts only a subset of JSON
/// Schema (the OpenAPI Schema object) and rejects the request outright — with
/// "Unknown name \"additionalProperties\" … Cannot find field" — if it sees a
/// keyword it does not model. The canonical tool schemas carry
/// `additionalProperties: false` on every object (see [McpSchema.object]), so
/// strip that and other unsupported keywords recursively before sending. Other
/// providers (OpenAI, Anthropic) accept the raw schema unchanged.
Object? sanitizeGeminiSchema(Object? schema) {
  const unsupported = {r'$schema', 'additionalProperties'};
  if (schema is Map) {
    return {
      for (final entry in schema.entries)
        if (!unsupported.contains(entry.key))
          entry.key: sanitizeGeminiSchema(entry.value),
    };
  }
  if (schema is List) {
    return [for (final item in schema) sanitizeGeminiSchema(item)];
  }
  return schema;
}

/// Streaming agent turn over Gemini `streamGenerateContent`.
class GeminiAgentProvider implements AgentProvider {
  const GeminiAgentProvider({
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
    final translated = translateContents(messages);
    final adapter = GeminiAdapter(_client, base: base, apiKey: apiKey);
    final request =
        http.Request(
            'POST',
            Uri.parse('$base/models/$model:streamGenerateContent?alt=sse'),
          )
          ..headers.addAll(adapter.headers)
          ..body = jsonEncode({
            'contents': translated.contents,
            if (translated.system != null)
              'systemInstruction': {
                'parts': [
                  {'text': translated.system},
                ],
              },
            'tools': [
              {
                'functionDeclarations': tools
                    .map(
                      (tool) => {
                        'name': tool.name,
                        'description': tool.description,
                        'parameters': sanitizeGeminiSchema(tool.inputSchema),
                      },
                    )
                    .toList(),
              },
            ],
            'generationConfig': {'temperature': 0, 'maxOutputTokens': 1200},
          });
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 45));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw AiRequestFailure(streamed.statusCode, errorOf(body));
    }

    final contentBuffer = StringBuffer();
    final toolCalls = <McpToolCall>[];
    ProviderMetrics? metrics;
    var callIndex = 0;

    void handleData(String data) {
      final Object? decoded;
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return;
      }
      if (decoded is! Map) return;
      final usage = decoded['usageMetadata'];
      if (usage is Map) {
        metrics = ProviderMetrics(
          promptTokens: (usage['promptTokenCount'] as num?)?.toInt(),
          outputTokens: (usage['candidatesTokenCount'] as num?)?.toInt(),
        );
      }
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) return;
      final parts = ((candidates.first as Map)['content'] as Map?)?['parts'];
      if (parts is! List) return;
      for (final part in parts) {
        if (part is! Map) continue;
        final text = part['text'];
        if (text is String && text.isNotEmpty) {
          contentBuffer.write(text);
          onContentDelta?.call(text);
        }
        final functionCall = part['functionCall'];
        if (functionCall is Map) {
          final args = functionCall['args'];
          toolCalls.add(
            McpToolCall(
              id: 'call_${callIndex++}',
              name: functionCall['name']?.toString() ?? '',
              arguments: args is Map ? Map<String, Object?>.from(args) : {},
            ),
          );
        }
      }
    }

    await readSse(streamed.stream, handleData, cancellation);

    // Rebuild the canonical assistant turn so the shared history stays uniform.
    final rawCalls = [
      for (final call in toolCalls)
        {
          'id': call.id,
          'type': 'function',
          'function': {
            'name': call.name,
            'arguments': jsonEncode(call.arguments),
          },
        },
    ];
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

/// Reads an SSE body, invoking [onData] per `data:` payload. Shared shape with
/// the OpenAI adapter but kept local to avoid a cross-adapter dependency.
Future<void> readSse(
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
        if (line.startsWith('data:')) onData(line.substring(5).trim());
        newline = carry.indexOf('\n');
      }
    }
  } finally {
    await iterator.cancel();
  }
}

String? errorOf(String? body) {
  if (body == null) return null;
  final text = body.trim();
  if (text.isEmpty) return null;
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map && decoded['error'] != null) {
      final error = decoded['error'];
      final message = error is Map ? error['message'] : error;
      final asText = message?.toString().trim();
      if (asText != null && asText.isNotEmpty) return asText;
    }
  } on FormatException {
    // Not JSON.
  }
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}
