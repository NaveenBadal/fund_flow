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
    return AgentPresentation(parts: ordered(parts));
  }

  /// Answer parts in reading order, whatever order they arrived in.
  ///
  /// The provider composes parts in the order it thought of them, which has
  /// put the conclusion underneath the chart it summarises and below the
  /// provenance note — so the answer opened on a wall of rows and the
  /// sentence explaining them had to be hunted for. Position is a property of
  /// the kind, not of the model's train of thought.
  static List<AgentPart> ordered(List<AgentPart> parts) {
    int rank(AgentPartKind kind) => switch (kind) {
      AgentPartKind.conclusion => 0,
      AgentPartKind.warning => 1,
      AgentPartKind.narrative => 2,
      AgentPartKind.metricRow => 3,
      AgentPartKind.comparison => 4,
      AgentPartKind.breakdown => 5,
      AgentPartKind.transactionList => 6,
      AgentPartKind.insight => 7,
      AgentPartKind.proposal => 8,
      AgentPartKind.sourceNote => 9,
      AgentPartKind.followUps => 10,
    };
    // Sorting on the arrival index as a tiebreak keeps the sort stable, so
    // several parts of one kind stay in the order they were given.
    final indexed = parts.indexed.toList()
      ..sort((a, b) {
        final byKind = rank(a.$2.kind).compareTo(rank(b.$2.kind));
        return byKind != 0 ? byKind : a.$1.compareTo(b.$1);
      });
    return [for (final entry in indexed) entry.$2];
  }

  factory AgentPresentation.unstructured(String text) => AgentPresentation(
    unstructured: true,
    parts: [
      AgentPart(kind: AgentPartKind.narrative, data: {'text': text}),
    ],
  );

  /// Recovers a presentation from a turn that answered in prose.
  ///
  /// Providers sometimes describe the compose call instead of making it,
  /// writing headings with the part objects beneath them as fenced JSON. The
  /// content is correct and fully grounded; only the delivery is wrong, and
  /// rendering it as markdown showed the person raw JSON. Rather than discard
  /// a good answer, the part objects are lifted out of the prose.
  static AgentPresentation? tryFromLooseContent(String content) {
    final parts = <AgentPart>[];
    for (final candidate in _jsonCandidates(content.trim())) {
      final Object? decoded;
      try {
        decoded = jsonDecode(candidate);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;

      // A wrapper object carrying the whole list is the intended shape.
      if (decoded['parts'] is List) {
        try {
          return AgentPresentation.fromComposeArguments(
            Map<String, Object?>.from(decoded),
          );
        } catch (_) {
          continue;
        }
      }
      final type = decoded['type']?.toString();
      if (type == null) continue;
      if (!AgentPartKind.values.any((kind) => kind.name == type)) continue;
      try {
        final part = AgentPart.fromJson(Map<Object?, Object?>.from(decoded));
        // _jsonCandidates walks every opening brace, so the same object can
        // be produced more than once.
        if (!parts.any(
          (existing) =>
              existing.kind == part.kind &&
              jsonEncode(existing.data) == jsonEncode(part.data),
        )) {
          parts.add(part);
        }
      } catch (_) {
        continue;
      }
    }
    if (parts.isEmpty) return null;

    // Prose ahead of the first part object is the answer itself when the
    // provider never emitted a conclusion object.
    if (!parts.any((part) => part.kind == AgentPartKind.conclusion)) {
      final lead = _leadingProse(content) ?? _conclusionFromParts(parts);
      if (lead != null) {
        parts.insert(
          0,
          AgentPart(kind: AgentPartKind.conclusion, data: {'text': lead}),
        );
      } else {
        return null;
      }
    }
    return AgentPresentation(parts: ordered(parts));
  }

  /// A conclusion drawn from the parts themselves, for a reply that is one
  /// bare part object with no prose around it — a comparison's detail line is
  /// the answer, and discarding the whole reply over a missing heading would
  /// show the person raw JSON instead. A detail promoted to the conclusion is
  /// removed from its part so the same sentence is not shown twice.
  static String? _conclusionFromParts(List<AgentPart> parts) {
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final detail = part.data['detail']?.toString().trim();
      if (detail != null && detail.isNotEmpty) {
        parts[index] = AgentPart(
          kind: part.kind,
          data: Map<String, Object?>.from(part.data)..remove('detail'),
        );
        return detail;
      }
      final text =
          (part.data['text'] ?? part.data['title'])?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  /// First substantial line of prose before any JSON or fence, with markdown
  /// heading markers removed.
  static String? _leadingProse(String content) {
    final cut = content.indexOf(RegExp(r'```|\{'));
    final head = (cut == -1 ? content : content.substring(0, cut)).trim();
    if (head.isEmpty) return null;
    final lines = head
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'^\s*#{1,6}\s*'), '').trim())
        .where((line) => line.isNotEmpty)
        // Bare section labels the provider wrote as headings carry no answer.
        .where(
          (line) => !RegExp(
            r'^(conclusion|narrative|summary|answer)$',
            caseSensitive: false,
          ).hasMatch(line),
        )
        .toList();
    if (lines.isEmpty) return null;
    final text = lines.join(' ').trim();
    return text.length > 600 ? '${text.substring(0, 600)}…' : text;
  }

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
