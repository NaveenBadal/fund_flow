import '../models/ai_provider.dart';
import '../models/expense.dart';
import '../services/categorization_service.dart';
import '../services/sms_service.dart';

/// Parses push-notification payloads for financial transactions.
///
/// Used when notification-parsing is enabled in settings. The caller
/// supplies the notification title + body; this service decides whether
/// it looks financial and, if so, delegates to [CategorizationService]
/// for full extraction.
class NotificationParserService {
  NotificationParserService({
    required this.apiKey,
    required this.provider,
    required this.modelName,
    this.onDeviceMaxTokens = 4096,
  });

  final String apiKey;
  final AiProviderType provider;
  final String modelName;
  final int onDeviceMaxTokens;

  final _smsService = SmsService();

  /// Returns parsed [Expense] list from a notification, or empty list if
  /// the notification doesn't appear financial.
  Future<List<Expense>> parse(String title, String body) async {
    final combined = '$title $body'.trim();
    if (!_smsService.isFinancialSms(combined)) return const [];

    final catService = CategorizationService(
      apiKey,
      provider: provider,
      modelName: modelName,
      onDeviceMaxTokens: onDeviceMaxTokens,
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
