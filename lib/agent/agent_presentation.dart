import 'dart:convert';

enum AgentPartKind {
  conclusion,
  narrative,
  metricRow,
  comparison,
  breakdown,
  transactionList,
  insight,
  sourceNote,
  followUps,
  proposal,
  warning,
}

class AgentPart {
  const AgentPart({required this.kind, required this.data});
  final AgentPartKind kind;
  final Map<String, Object?> data;

  factory AgentPart.fromJson(Map<Object?, Object?> value) {
    final type = value['type']?.toString();
    final kind = AgentPartKind.values.where((item) => item.name == type);
    if (kind.length != 1) {
      throw AgentPresentationException('Unknown answer part: $type');
    }
    final data = Map<String, Object?>.from(value)..remove('type');
    return AgentPart(kind: kind.single, data: data);
  }

  Map<String, Object?> toJson() => {'type': kind.name, ...data};

  /// One-line rendering for replay into provider history.
  ///
  /// Prose parts carry a `text` field, but figures live in structured fields
  /// that plain text drops entirely. Without this, an agent rereading its own
  /// last answer sees the sentences and none of the numbers, and cannot
  /// resolve a follow-up like "why is that higher than last month?".
  String? get historyLine {
    String money(Object? row) {
      if (row is! Map) return '';
      final label = row['label'] ?? row['title'] ?? '';
      final amount = row['amountMinor'];
      final currency = row['currency'] ?? '';
      return amount == null ? '$label' : '$label $amount $currency';
    }

    List<Object?> rows(String key) {
      final value = data[key];
      return value is List ? value : const [];
    }

    return switch (kind) {
      AgentPartKind.conclusion ||
      AgentPartKind.narrative ||
      AgentPartKind.insight ||
      AgentPartKind.sourceNote ||
      AgentPartKind.warning => data['text']?.toString(),
      AgentPartKind.comparison => [
        data['title'],
        data['detail'],
      ].whereType<Object>().join(': '),
      AgentPartKind.metricRow =>
        rows('metrics').map(money).where((e) => e.isNotEmpty).join('; '),
      AgentPartKind.breakdown => [
        data['title']?.toString() ?? 'Breakdown',
        rows('rows').map(money).where((e) => e.isNotEmpty).join(', '),
      ].where((e) => e.isNotEmpty).join(': '),
      AgentPartKind.transactionList =>
        'transaction ids ${rows('transactionIds').join(', ')}',
      AgentPartKind.proposal => 'proposed: ${data['title'] ?? ''}',
      // Suggested questions were never stated as fact and only add noise.
      AgentPartKind.followUps => null,
    };
  }
}

class AgentPresentation {
  const AgentPresentation({required this.parts, this.unstructured = false});
  final List<AgentPart> parts;
  final bool unstructured;

  String get plainText => parts
      .map((part) => part.data['text']?.toString())
      .whereType<String>()
      .join('\n\n');

  factory AgentPresentation.fromComposeArguments(
    Map<String, Object?> arguments,
  ) {
    final raw = arguments['parts'];
    if (raw is! List || raw.isEmpty || raw.length > 16) {
      throw const AgentPresentationException(
        'An answer needs between 1 and 16 parts.',
      );
    }
    final parts = raw
        .map((item) => AgentPart.fromJson(item as Map<Object?, Object?>))
        .toList();
    if (!parts.any((part) => part.kind == AgentPartKind.conclusion)) {
      throw const AgentPresentationException(
        'An answer requires a conclusion.',
      );
    }
    return AgentPresentation(parts: parts);
  }

  factory AgentPresentation.unstructured(String text) => AgentPresentation(
    unstructured: true,
    parts: [
      AgentPart(kind: AgentPartKind.narrative, data: {'text': text}),
    ],
  );

  static AgentPresentation? tryFromProviderContent(String content) {
    var text = content.trim();
    if (text.startsWith('```')) {
      final newline = text.indexOf('\n');
      if (newline == -1) return null;
      text = text.substring(newline + 1);
      final fence = text.lastIndexOf('```');
      if (fence != -1) text = text.substring(0, fence);
      text = text.trim();
    }
    for (final candidate in _jsonCandidates(text)) {
      try {
        final decoded = jsonDecode(candidate);
        if (decoded is! Map || !decoded.containsKey('parts')) continue;
        return AgentPresentation.fromComposeArguments(
          Map<String, Object?>.from(decoded),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  static Iterable<String> _jsonCandidates(String text) sync* {
    yield text;
    for (var start = 0; start < text.length; start++) {
      if (text.codeUnitAt(start) != 123) continue;
      var depth = 0;
      var quoted = false;
      var escaped = false;
      for (var index = start; index < text.length; index++) {
        final code = text.codeUnitAt(index);
        if (quoted) {
          if (escaped) {
            escaped = false;
          } else if (code == 92) {
            escaped = true;
          } else if (code == 34) {
            quoted = false;
          }
          continue;
        }
        if (code == 34) {
          quoted = true;
        } else if (code == 123) {
          depth++;
        } else if (code == 125) {
          depth--;
          if (depth == 0) {
            yield text.substring(start, index + 1);
            break;
          }
        }
      }
    }
  }
}

class AgentPresentationException implements Exception {
  const AgentPresentationException(this.message);
  final String message;
  @override
  String toString() => message;
}
