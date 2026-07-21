import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ai_provider.dart';

/// Fetches the list of model ids a provider currently serves, so the connect
/// sheet offers a live dropdown instead of an error-prone text field. Returns
/// an empty list on any failure; the caller falls back to the seed models.
class ModelCatalog {
  const ModelCatalog({http.Client? client}) : _client = client;
  final http.Client? _client;

  Future<List<String>> fetch({
    required AiProvider provider,
    required String base,
    required String apiKey,
  }) async {
    final client = _client ?? http.Client();
    try {
      final info = providerInfo(provider);
      final ids = switch (info.wire) {
        AiWireKind.openai => await _openai(client, base, apiKey),
        AiWireKind.anthropic => await _anthropic(client, base, apiKey),
        AiWireKind.gemini => await _gemini(client, base, apiKey),
        AiWireKind.ollamaNative => await _ollama(client, base, apiKey),
      };
      ids.sort();
      return ids;
    } catch (_) {
      return const [];
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<List<String>> _openai(
    http.Client client,
    String base,
    String key,
  ) async {
    final response = await client
        .get(
          Uri.parse('$base/models'),
          headers: {'Authorization': 'Bearer $key'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300)
      return const [];
    final data = (jsonDecode(response.body) as Map)['data'];
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map && item['id'] is String) item['id'] as String,
    ];
  }

  Future<List<String>> _anthropic(
    http.Client client,
    String base,
    String key,
  ) async {
    final response = await client
        .get(
          Uri.parse('$base/v1/models'),
          headers: {'x-api-key': key, 'anthropic-version': '2023-06-01'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300)
      return const [];
    final data = (jsonDecode(response.body) as Map)['data'];
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map && item['id'] is String) item['id'] as String,
    ];
  }

  Future<List<String>> _gemini(
    http.Client client,
    String base,
    String key,
  ) async {
    final response = await client
        .get(Uri.parse('$base/models'), headers: {'x-goog-api-key': key})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300)
      return const [];
    final models = (jsonDecode(response.body) as Map)['models'];
    if (models is! List) return const [];
    final ids = <String>[];
    for (final item in models) {
      if (item is! Map) continue;
      final methods = item['supportedGenerationMethods'];
      if (methods is List && !methods.contains('generateContent')) continue;
      final name = item['name'];
      if (name is String) {
        ids.add(name.startsWith('models/') ? name.substring(7) : name);
      }
    }
    return ids;
  }

  Future<List<String>> _ollama(
    http.Client client,
    String base,
    String key,
  ) async {
    // Local Ollama exposes /api/tags; the hosted endpoint may not, in which
    // case the caller keeps the seed models.
    final response = await client
        .get(
          Uri.parse('$base/api/tags'),
          headers: {'Authorization': 'Bearer $key'},
        )
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300)
      return const [];
    final models = (jsonDecode(response.body) as Map)['models'];
    if (models is! List) return const [];
    return [
      for (final item in models)
        if (item is Map && item['name'] is String) item['name'] as String,
    ];
  }

  /// The recommended default within [models] for [provider].
  ///
  /// The per-role [seed] is the curated pick, so prefer it whenever the live
  /// catalog actually serves it — this is what keeps a role-appropriate model
  /// on each field (e.g. Gemini's `gemini-flash-lite-latest` for parsing vs
  /// `gemini-flash-latest` for chat). Only when the seed is not served does it
  /// fall back to the provider's recommended substrings, then to the first
  /// model. The substring list is a coarse net (Gemini's `flash` also matches
  /// `flash-lite`), so it must not override an available seed — that was the
  /// bug that collapsed both fields onto the same lite model.
  static String recommend({
    required AiProvider provider,
    required List<String> models,
    required String seed,
  }) {
    if (models.isEmpty) return seed;
    if (models.contains(seed)) return seed;
    for (final needle in providerInfo(provider).recommendedContains) {
      for (final id in models) {
        if (id.toLowerCase().contains(needle.toLowerCase())) return id;
      }
    }
    return models.first;
  }
}
