import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../services/captured_notification_service.dart';
import '../services/categorization_service.dart';

class NotificationIngestionState {
  const NotificationIngestionState({
    this.accessEnabled = false,
    this.processing = false,
    this.imported = 0,
    this.error,
  });

  final bool accessEnabled;
  final bool processing;
  final int imported;
  final String? error;

  NotificationIngestionState copyWith({
    bool? accessEnabled,
    bool? processing,
    int? imported,
    String? error,
    bool clearError = false,
  }) => NotificationIngestionState(
    accessEnabled: accessEnabled ?? this.accessEnabled,
    processing: processing ?? this.processing,
    imported: imported ?? this.imported,
    error: clearError ? null : error ?? this.error,
  );
}

class NotificationIngestionNotifier
    extends Notifier<NotificationIngestionState> {
  final _native = const CapturedNotificationService();

  @override
  NotificationIngestionState build() => const NotificationIngestionState();

  Future<void> refreshAccess() async {
    final enabled = await _native.isAccessEnabled();
    state = state.copyWith(accessEnabled: enabled, clearError: true);
  }

  Future<void> setEnabled(bool enabled) async {
    await ref
        .read(notificationParsingEnabledProvider.notifier)
        .setEnabled(enabled);
    await _native.setCaptureEnabled(enabled);
    if (!enabled) {
      state = state.copyWith(processing: false, clearError: true);
      return;
    }
    await refreshAccess();
    if (!state.accessEnabled) {
      await _native.openAccessSettings();
    } else {
      await processPending();
    }
  }

  Future<void> openAccessSettings() => _native.openAccessSettings();

  Future<void> processPending() async {
    if (state.processing || !ref.read(notificationParsingEnabledProvider)) {
      return;
    }
    await _native.setCaptureEnabled(true);
    final access = await _native.isAccessEnabled();
    state = state.copyWith(accessEnabled: access, clearError: true);
    if (!access) return;

    final pending = await _native.getPending();
    if (pending.isEmpty) return;
    final apiKey = ref.read(ollamaApiKeyProvider).trim();
    if (apiKey.isEmpty) {
      state = state.copyWith(
        error: 'Add your Ollama API key to process captured transactions.',
      );
      return;
    }

    state = state.copyWith(processing: true, imported: 0, clearError: true);
    final db = ref.read(databaseProvider);
    final acknowledged = <String>{};
    var imported = 0;
    try {
      final fresh = <CapturedNotification>[];
      for (final event in pending) {
        if (await db.smsExists(event.body)) {
          acknowledged.add(event.id);
        } else {
          fresh.add(event);
        }
      }

      final parser = CategorizationService(
        apiKey: apiKey,
        baseUrl: ref.read(ollamaBaseUrlProvider),
        model: ref.read(ollamaModelProvider),
        currency: ref.read(preferredCurrencyProvider),
      );
      for (var start = 0; start < fresh.length; start += 12) {
        final end = (start + 12).clamp(0, fresh.length);
        final chunk = fresh.sublist(start, end);
        final messages = [
          for (final event in chunk)
            {
              'body': event.body,
              'date': event.postedAt.toIso8601String(),
              'address': 'Notification · ${event.title}',
              'timestamp': event.postedAt.millisecondsSinceEpoch,
            },
        ];
        final result = await parser.parseSmsBatch(messages);
        final inserted = await ref
            .read(expenseListProvider.notifier)
            .insertExpensesProgressively(result.expenses);
        imported += inserted.length;

        final confirmed = <Map<String, dynamic>>[];
        for (var index = 0; index < chunk.length; index++) {
          final event = chunk[index];
          final reason = result.skipReasons[event.body];
          final producedExpense = result.expenses.any(
            (expense) => expense.originalSms == event.body,
          );
          final retryable =
              reason == 'parse_error' ||
              reason == 'no_response' ||
              reason == 'no_api_key';
          if (producedExpense || !retryable) {
            acknowledged.add(event.id);
            confirmed.add(messages[index]);
          }
        }
        if (confirmed.isNotEmpty) {
          await db.markSmsBatchParsed(
            confirmed,
            skipReasons: result.skipReasons,
          );
        }
      }
      await _native.acknowledge(acknowledged);
      ref.invalidate(parsedSmsAuditProvider);
      state = state.copyWith(processing: false, imported: imported);
    } catch (error) {
      await _native.acknowledge(acknowledged);
      state = state.copyWith(processing: false, error: '$error');
    }
  }
}

final notificationIngestionProvider =
    NotifierProvider<NotificationIngestionNotifier, NotificationIngestionState>(
      NotificationIngestionNotifier.new,
    );
