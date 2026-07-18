import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/fund_flow_store.dart';
import '../data/secure_preferences.dart';
import '../domain/conversation.dart';
import '../domain/finance_summary.dart';
import '../domain/preferences.dart';
import '../domain/transaction.dart';
import '../ingestion/local_message_parser.dart';
import '../ingestion/sms_source.dart';
import '../intelligence/ai_client.dart';
import 'app_state.dart';

final storeProvider = Provider((ref) {
  final store = FundFlowStore();
  ref.onDispose(store.close);
  return store;
});
final securePreferencesProvider = Provider(
  (ref) => const SecurePreferences(FlutterSecureStorage()),
);
final smsSourceProvider = Provider((ref) => SmsSource());
final aiClientProvider = Provider((ref) {
  final client = AiClient();
  ref.onDispose(client.close);
  return client;
});
final appControllerProvider = AsyncNotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends AsyncNotifier<AppState> {
  @override
  Future<AppState> build() async {
    final secure = ref.read(securePreferencesProvider);
    final prefs = await secure.read();
    final key = await secure.apiKey();
    final store = ref.read(storeProvider);
    final values = await Future.wait([
      store.transactions(),
      store.conversation(),
    ]);
    return AppState(
      preferences: prefs,
      transactions: values[0] as List<MoneyTransaction>,
      conversation: values[1] as List<ConversationMessage>,
      aiConnection: key.isEmpty
          ? AiConnection.disconnected
          : AiConnection.connected,
    );
  }

  AppState get _value => state.requireValue;
  Future<void> updatePreferences(AppPreferences value) async {
    await ref.read(securePreferencesProvider).write(value);
    state = AsyncData(_value.copyWith(preferences: value));
  }

  Future<bool> connectAi({
    required String key,
    required String endpoint,
    required String model,
  }) async {
    state = AsyncData(
      _value.copyWith(aiConnection: AiConnection.checking, clearError: true),
    );
    final valid = await ref
        .read(aiClientProvider)
        .validate(endpoint: endpoint, apiKey: key, model: model);
    if (!valid) {
      state = AsyncData(
        _value.copyWith(
          aiConnection: AiConnection.rejected,
          error:
              'The connection was not accepted. Check the key, endpoint, and model.',
        ),
      );
      return false;
    }
    await ref.read(securePreferencesProvider).writeApiKey(key);
    final prefs = _value.preferences.copyWith(
      aiEndpoint: endpoint,
      aiModel: model,
    );
    await ref.read(securePreferencesProvider).write(prefs);
    state = AsyncData(
      _value.copyWith(
        preferences: prefs,
        aiConnection: AiConnection.connected,
        clearError: true,
      ),
    );
    return true;
  }

  Future<void> disconnectAi() async {
    await ref.read(securePreferencesProvider).writeApiKey('');
    state = AsyncData(_value.copyWith(aiConnection: AiConnection.disconnected));
  }

  Future<void> saveTransaction(MoneyTransaction value) async {
    await ref.read(storeProvider).saveTransaction(value);
    state = AsyncData(
      _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
      ),
    );
  }

  Future<void> confirmTransaction(MoneyTransaction value) => saveTransaction(
    value.copyWith(reviewState: ReviewState.confirmed, confidence: 1),
  );
  Future<void> deleteTransaction(int id) async {
    await ref.read(storeProvider).deleteTransaction(id);
    state = AsyncData(
      _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
      ),
    );
  }

  Future<void> clearConversation() async {
    await ref.read(storeProvider).clearConversation();
    state = AsyncData(_value.copyWith(conversation: const []));
  }

  Future<void> importMessages() async {
    var current = _value;
    state = AsyncData(
      current.copyWith(
        importStatus: const ImportStatus(
          phase: ImportPhase.requestingPermission,
        ),
        clearError: true,
      ),
    );
    final source = ref.read(smsSourceProvider);
    final permission = await source.permission(request: true);
    if (permission != MessagePermission.granted) {
      state = AsyncData(
        _value.copyWith(
          importStatus: ImportStatus(
            phase: ImportPhase.error,
            permission: permission,
            message: permission == MessagePermission.permanentlyDenied
                ? 'Message permission is disabled in Android settings.'
                : 'Message permission was not granted.',
          ),
        ),
      );
      return;
    }
    state = AsyncData(
      _value.copyWith(
        importStatus: ImportStatus(
          phase: ImportPhase.reading,
          permission: permission,
        ),
      ),
    );
    try {
      final candidates = await source.recent(
        _value.preferences.messageLookbackDays,
      );
      final existing = _value.transactions
          .map((e) => e.sourceText)
          .whereType<String>()
          .toSet();
      final parser = LocalMessageParser();
      var imported = 0;
      var skipped = 0;
      for (var i = 0; i < candidates.length; i++) {
        state = AsyncData(
          _value.copyWith(
            importStatus: ImportStatus(
              phase: ImportPhase.understanding,
              permission: permission,
              checked: i,
              imported: imported,
              skipped: skipped,
            ),
          ),
        );
        final parsed = parser.parse(candidates[i]);
        if (parsed == null || existing.contains(parsed.sourceText)) {
          skipped++;
          continue;
        }
        await ref.read(storeProvider).saveTransaction(parsed);
        imported++;
      }
      current = _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
        importStatus: ImportStatus(
          phase: ImportPhase.complete,
          permission: permission,
          checked: candidates.length,
          imported: imported,
          skipped: skipped,
        ),
      );
      state = AsyncData(current);
    } catch (error) {
      state = AsyncData(
        _value.copyWith(
          importStatus: ImportStatus(
            phase: ImportPhase.error,
            permission: permission,
            message: 'Messages could not be checked. Nothing was changed.',
          ),
        ),
      );
    }
  }

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _value.asking) return;
    final user = ConversationMessage(
      author: MessageAuthor.person,
      text: trimmed,
      createdAt: DateTime.now(),
    );
    await ref.read(storeProvider).addMessage(user);
    state = AsyncData(
      _value.copyWith(
        conversation: await ref.read(storeProvider).conversation(),
        asking: true,
        askStage: 'Checking your activity',
        clearError: true,
      ),
    );
    try {
      final key = await ref.read(securePreferencesProvider).apiKey();
      if (key.isEmpty) throw const AiRequestFailure(401);
      final context = _contextFor(trimmed);
      final answer = await ref
          .read(aiClientProvider)
          .answer(
            endpoint: _value.preferences.aiEndpoint,
            apiKey: key,
            model: _value.preferences.aiModel,
            question: trimmed,
            context: context.$1,
          );
      final assistant = ConversationMessage(
        author: MessageAuthor.assistant,
        text: answer,
        createdAt: DateTime.now(),
        verified: true,
        supportingTransactionIds: context.$2,
      );
      await ref.read(storeProvider).addMessage(assistant);
      state = AsyncData(
        _value.copyWith(
          conversation: await ref.read(storeProvider).conversation(),
          asking: false,
          askStage: null,
        ),
      );
    } catch (error) {
      final message = switch (error) {
        AiRequestFailure(statusCode: 401 || 403) =>
          'Reconnect intelligence in You.',
        AiRequestFailure(statusCode: 429) =>
          'The provider is busy. Try again shortly.',
        _ =>
          'The answer could not be completed. Your activity was not changed.',
      };
      state = AsyncData(
        _value.copyWith(asking: false, askStage: null, error: message),
      );
    }
  }

  (String, List<int>) _contextFor(String question) {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month);
    final month = _value.transactions
        .where((e) => !e.occurredAt.isBefore(from))
        .toList();
    final summaries = FinanceEngine.summarize(month);
    final totals = summaries
        .map(
          (e) =>
              '${e.currency}: incoming ${e.incomingMinor} minor units, outgoing ${e.outgoingMinor} minor units, net ${e.netMinor} minor units',
        )
        .join('\n');
    final recent = month
        .take(min(100, month.length))
        .map(
          (e) =>
              'id=${e.id}; ${e.occurredAt.toIso8601String()}; ${e.direction.name}; ${e.amountMinor} ${e.currency} minor units; merchant=${e.merchant}; category=${e.category}',
        )
        .join('\n');
    return (
      'Current month deterministic totals:\n$totals\nTransactions:\n$recent',
      month.map((e) => e.id).whereType<int>().toList(),
    );
  }
}
