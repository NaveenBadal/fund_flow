import 'dart:convert';

enum McpRisk { read, propose, platform, compose }

class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.risk,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final McpRisk risk;

  Map<String, Object?> toProviderJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };
}

class McpToolCall {
  const McpToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, Object?> arguments;

  factory McpToolCall.fromProviderJson(Map<Object?, Object?> value, int index) {
    final function = Map<Object?, Object?>.from(
      value['function'] as Map? ?? const {},
    );
    final raw = function['arguments'];
    Map<String, Object?> arguments;
    if (raw is String) {
      arguments = Map<String, Object?>.from(
        jsonDecode(raw) as Map<Object?, Object?>,
      );
    } else {
      arguments = Map<String, Object?>.from(
        raw as Map<Object?, Object?>? ?? const {},
      );
    }
    final name = function['name']?.toString().trim() ?? '';
    if (name.isEmpty) throw const McpProtocolException('Missing tool name');
    return McpToolCall(
      id: value['id']?.toString() ?? 'call_$index',
      name: name,
      arguments: arguments,
    );
  }
}

class McpToolResult {
  const McpToolResult({
    required this.callId,
    required this.tool,
    required this.content,
    this.isError = false,
    this.summary,
  });

  final String callId;
  final String tool;
  final Map<String, Object?> content;
  final bool isError;
  final String? summary;

  /// Ceiling on a single tool result once encoded.
  ///
  /// Results accumulate in the message array for the rest of the run and are
  /// resent on every subsequent turn, so one broad search can otherwise
  /// dominate the prompt and slow every turn that follows it.
  static const int maximumContentCharacters = 6000;

  Map<String, Object?> toProviderMessage() => {
    'role': 'tool',
    // Canonical history carries both: Ollama reads tool_name, OpenAI reads
    // tool_call_id, and the Claude/Gemini adapters translate from these.
    'tool_call_id': callId,
    'tool_name': tool,
    'content': _encodeWithinBudget({'ok': !isError, ...content}),
  };

  /// Encodes [payload], trimming its longest list until the result fits.
  ///
  /// Rows are dropped from the end rather than the string being cut, so the
  /// provider always receives valid JSON, and an explicit marker tells it the
  /// view is partial so it does not treat the tail as absent data.
  static String _encodeWithinBudget(Map<String, Object?> payload) {
    var encoded = jsonEncode(payload);
    if (encoded.length <= maximumContentCharacters) return encoded;

    final working = Map<String, Object?>.from(payload);
    // Captured before any trimming so the marker reports how many rows the
    // capability actually found, not how many survived the last pass.
    final originalLengths = <String, int>{
      for (final entry in working.entries)
        if (entry.value is List) entry.key: (entry.value! as List).length,
    };

    while (encoded.length > maximumContentCharacters) {
      String? longestKey;
      var longestLength = 0;
      for (final entry in working.entries) {
        final value = entry.value;
        if (value is List && value.length > longestLength) {
          longestKey = entry.key;
          longestLength = value.length;
        }
      }
      // Nothing left to trim: the payload is large without being list shaped.
      if (longestKey == null || longestLength <= 1) break;
      final list = List<Object?>.from(working[longestKey]! as List);
      final keep = (list.length * 2) ~/ 3;
      working[longestKey] = list.sublist(0, keep < 1 ? 1 : keep);
      working['truncated'] = {
        'field': longestKey,
        'returned': (working[longestKey]! as List).length,
        'total': originalLengths[longestKey] ?? longestLength,
        'note':
            'Result trimmed to fit the context budget. Narrow the filters or '
            'use a finance capability to aggregate instead of listing rows.',
      };
      encoded = jsonEncode(working);
    }
    return encoded;
  }
}

class McpProtocolException implements Exception {
  const McpProtocolException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract final class McpSchema {
  static Map<String, Object?> object({
    Map<String, Object?> properties = const {},
    List<String> required = const [],
  }) => {
    'type': 'object',
    'properties': properties,
    'required': required,
    'additionalProperties': false,
  };

  static Map<String, Object?> string({List<String>? values}) => {
    'type': 'string',
    'enum': ?values,
  };

  static Map<String, Object?> integer({int? minimum, int? maximum}) => {
    'type': 'integer',
    'minimum': ?minimum,
    'maximum': ?maximum,
  };

  static Map<String, Object?> boolean() => {'type': 'boolean'};

  static Map<String, Object?> array(
    Map<String, Object?> items, {
    int? minItems,
  }) => {'type': 'array', 'items': items, 'minItems': ?minItems};
}
