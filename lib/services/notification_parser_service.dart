import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/ai_provider.dart';
import '../models/expense.dart';
import '../services/categorization_service.dart';

class NotificationParserService {
  const NotificationParserService();

  static const _storage = FlutterSecureStorage();

  Future<List<Expense>> parse(String title, String body) async {
    final combined = '$title $body'.trim();

    final apiKey = await _storage.read(key: ollamaApiKeyStorageKey) ?? '';
    if (apiKey.isEmpty) return const [];
    final model =
        await _storage.read(key: ollamaModelStorageKey) ?? defaultOllamaModel;
    final baseUrl =
        await _storage.read(key: ollamaBaseUrlStorageKey) ?? defaultOllamaBaseUrl;

    final catService = CategorizationService(
      apiKey: apiKey,
      baseUrl: baseUrl,
      model: model,
    );

    try {
      final result = await catService.parseSmsBatch([
        {
          'body': combined,
          'date': DateTime.now().toIso8601String(),
          'address': title,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }
      ]);
      return result.expenses;
    } catch (_) {
      return const [];
    }
  }
}
