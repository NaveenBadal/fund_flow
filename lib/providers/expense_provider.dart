import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/ai_provider.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/ai_log.dart';
import '../services/database_helper.dart';
import '../services/sms_service.dart';
import '../services/categorization_service.dart';
import '../services/ollama_cloud_service.dart';
import '../utils/category_utils.dart';

// ─── Infrastructure ────────────────────────────────────────────────────────

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());

// ─── AI (Ollama Cloud) ──────────────────────────────────────────────────────

class OllamaApiKeyNotifier extends Notifier<String> {
  @override
  String build() => defaultOllamaApiKey;
  void set(String key) => state = key;
}

final ollamaApiKeyProvider = NotifierProvider<OllamaApiKeyNotifier, String>(
  OllamaApiKeyNotifier.new,
);

class OllamaBaseUrlNotifier extends Notifier<String> {
  @override
  String build() => defaultOllamaBaseUrl;
  void set(String url) => state = url;
}

final ollamaBaseUrlProvider = NotifierProvider<OllamaBaseUrlNotifier, String>(
  OllamaBaseUrlNotifier.new,
);

class OllamaModelNotifier extends Notifier<String> {
  @override
  String build() => defaultOllamaModel;
  void set(String model) => state = model;
}

final ollamaModelProvider = NotifierProvider<OllamaModelNotifier, String>(
  OllamaModelNotifier.new,
);

final activeModelProvider = Provider<String>(
  (ref) => ref.watch(ollamaModelProvider),
);

final ollamaCloudProvider = Provider<OllamaCloudService>((ref) {
  final service = OllamaCloudService(
    apiKey: ref.watch(ollamaApiKeyProvider),
    baseUrl: ref.watch(ollamaBaseUrlProvider),
    model: ref.watch(ollamaModelProvider),
  );
  ref.onDispose(service.close);
  return service;
});

class SyncLookbackNotifier extends Notifier<int> {
  @override
  int build() => 30;
  void setDays(int days) => state = days;
}

final syncLookbackProvider = NotifierProvider<SyncLookbackNotifier, int>(
  SyncLookbackNotifier.new,
);

// ─── Theme ────────────────────────────────────────────────────────────────

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void setThemeMode(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class PreferredCurrencyNotifier extends Notifier<String> {
  @override
  String build() => 'INR';

  Future<void> setCurrency(String currency) async {
    state = currency;
    await ref
        .read(secureStorageProvider)
        .write(key: 'preferred_currency', value: currency);
  }

  void restore(String currency) => state = currency;
}

final preferredCurrencyProvider =
    NotifierProvider<PreferredCurrencyNotifier, String>(
      PreferredCurrencyNotifier.new,
    );

// ─── Privacy / App lock ────────────────────────────────────────────────────

class PrivateModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> toggle() async {
    state = !state;
    await ref
        .read(secureStorageProvider)
        .write(key: 'private_mode_enabled', value: '$state');
  }

  Future<void> set(bool v) async {
    state = v;
    await ref
        .read(secureStorageProvider)
        .write(key: 'private_mode_enabled', value: '$state');
  }

  void restore(bool value) => state = value;
}

final privateModeProvider = NotifierProvider<PrivateModeNotifier, bool>(
  PrivateModeNotifier.new,
);

class AppLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> toggle() async {
    await setEnabled(!state);
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    await ref
        .read(secureStorageProvider)
        .write(key: 'app_lock_enabled', value: state.toString());
  }

  void set(bool v) => state = v;
}

final appLockEnabledProvider = NotifierProvider<AppLockNotifier, bool>(
  AppLockNotifier.new,
);

// ─── Notification parsing ──────────────────────────────────────────────────

class NotificationParsingNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> toggle() async {
    state = !state;
    await ref
        .read(secureStorageProvider)
        .write(key: 'notification_parsing_enabled', value: state.toString());
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    await ref
        .read(secureStorageProvider)
        .write(key: 'notification_parsing_enabled', value: value.toString());
  }

  void set(bool v) => state = v;
}

final notificationParsingEnabledProvider =
    NotifierProvider<NotificationParsingNotifier, bool>(
      NotificationParsingNotifier.new,
    );

// ─── Notification settings ─────────────────────────────────────────────────

class DailyDigestNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  Future<void> toggle() async {
    state = !state;
    await ref
        .read(secureStorageProvider)
        .write(key: 'daily_digest_enabled', value: state.toString());
  }

  void set(bool v) => state = v;
}

final dailyDigestEnabledProvider = NotifierProvider<DailyDigestNotifier, bool>(
  DailyDigestNotifier.new,
);

// ─── Settings initializer ──────────────────────────────────────────────────

final settingsInitializer = FutureProvider<void>((ref) async {
  final storage = ref.watch(secureStorageProvider);

  final lookback = await storage.read(key: 'sync_lookback_days');
  if (lookback != null) {
    ref
        .read(syncLookbackProvider.notifier)
        .setDays(int.tryParse(lookback) ?? 30);
  }

  final theme = await storage.read(key: 'theme_mode');
  if (theme != null) {
    final mode = ThemeMode.values.firstWhere(
      (e) => e.toString() == theme,
      orElse: () => ThemeMode.system,
    );
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
  }

  final currency = await storage.read(key: 'preferred_currency');
  if (currency != null && currency.isNotEmpty) {
    ref.read(preferredCurrencyProvider.notifier).restore(currency);
  }
  final appLock = await storage.read(key: 'app_lock_enabled');
  ref.read(appLockEnabledProvider.notifier).set(appLock == 'true');

  final privateMode = await storage.read(key: 'private_mode_enabled');
  ref.read(privateModeProvider.notifier).restore(privateMode == 'true');

  final dailyDigest = await storage.read(key: 'daily_digest_enabled');
  ref.read(dailyDigestEnabledProvider.notifier).set(dailyDigest == 'true');

  final notifParsing = await storage.read(key: 'notification_parsing_enabled');
  ref
      .read(notificationParsingEnabledProvider.notifier)
      .set(notifParsing == 'true');

  final apiKey = await storage.read(key: ollamaApiKeyStorageKey);
  if (apiKey != null && apiKey.isNotEmpty) {
    ref.read(ollamaApiKeyProvider.notifier).set(apiKey);
  }

  final ollamaUrl = await storage.read(key: ollamaBaseUrlStorageKey);
  if (ollamaUrl != null && ollamaUrl.isNotEmpty) {
    ref.read(ollamaBaseUrlProvider.notifier).set(ollamaUrl);
  }

  final ollamaModel = await storage.read(key: ollamaModelStorageKey);
  if (ollamaModel != null && ollamaModel.isNotEmpty) {
    // Migrate the former heavyweight default. Users can still explicitly pick
    // 120B again from Settings after this one-time performance migration.
    final migrated = ollamaModel == 'gpt-oss:120b'
        ? defaultOllamaModel
        : ollamaModel;
    ref.read(ollamaModelProvider.notifier).set(migrated);
    if (migrated != ollamaModel) {
      await storage.write(key: ollamaModelStorageKey, value: migrated);
    }
  }
});

// ─── Database ─────────────────────────────────────────────────────────────

final databaseProvider = Provider((ref) => DatabaseHelper.instance);

// ─── Expenses ─────────────────────────────────────────────────────────────

class ExpenseListNotifier extends AsyncNotifier<List<Expense>> {
  @override
  Future<List<Expense>> build() async {
    return await ref.watch(databaseProvider).getAllExpenses();
  }

  Future<void> refreshExpenses() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(databaseProvider).getAllExpenses(),
    );
  }

  Future<void> refreshPreservingData() async {
    state = await AsyncValue.guard(
      () => ref.read(databaseProvider).getAllExpenses(),
    );
  }

  Future<void> addExpense(Expense expense) async {
    await ref.read(databaseProvider).insertExpenses([expense]);
    await refreshExpenses();
  }

  Future<void> addExpenses(List<Expense> expenses) async {
    await ref.read(databaseProvider).insertExpensesReturning(expenses);
    await refreshExpenses();
  }

  Future<List<Expense>> insertExpensesProgressively(
    List<Expense> expenses,
  ) async {
    final inserted = await ref
        .read(databaseProvider)
        .insertExpensesReturning(expenses);
    final visible = state.asData?.value;
    if (visible != null && inserted.isNotEmpty) {
      state = AsyncValue.data(
        [...inserted, ...visible]..sort((a, b) => b.date.compareTo(a.date)),
      );
    } else if (inserted.isNotEmpty) {
      await refreshPreservingData();
    }
    return inserted;
  }

  Future<void> updateExpense(Expense expense) async {
    await ref.read(databaseProvider).updateExpense(expense);
    // Learn category correction
    try {
      final key = (expense.normalizedMerchant ?? expense.merchant)
          .toLowerCase()
          .trim();
      await ref
          .read(databaseProvider)
          .upsertMerchantCategory(key, expense.category);
    } catch (_) {}
    await refreshExpenses();
  }

  Future<void> deleteExpense(int id) async {
    await ref.read(databaseProvider).deleteExpense(id);
    await refreshExpenses();
  }
}

final expenseListProvider =
    AsyncNotifierProvider<ExpenseListNotifier, List<Expense>>(
      ExpenseListNotifier.new,
    );

// ─── Custom categories ─────────────────────────────────────────────────────

class CustomCategoryNotifier extends AsyncNotifier<List<CustomCategory>> {
  @override
  Future<List<CustomCategory>> build() async {
    return await ref.watch(databaseProvider).getAllCustomCategories();
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(databaseProvider).getAllCustomCategories(),
    );
  }

  Future<void> upsert(CustomCategory cat) async {
    await ref.read(databaseProvider).insertOrUpdateCustomCategory(cat);
    await _reload();
  }

  Future<void> remove(int id) async {
    await ref.read(databaseProvider).deleteCustomCategory(id);
    await _reload();
  }
}

final customCategoryListProvider =
    AsyncNotifierProvider<CustomCategoryNotifier, List<CustomCategory>>(
      CustomCategoryNotifier.new,
    );

/// All category names: builtins + custom
final allCategoryNamesProvider = Provider<List<String>>((ref) {
  final custom = ref.watch(customCategoryListProvider).asData?.value ?? [];
  return [...kBuiltinCategories, ...custom.map((c) => c.name)];
});

// ─── Parsed SMS audit ─────────────────────────────────────────────────────

final parsedSmsAuditProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(databaseProvider).getParsedSmsAudit();
});

// ─── AI Logs ──────────────────────────────────────────────────────────────

class AiLogNotifier extends AsyncNotifier<List<AiLog>> {
  @override
  Future<List<AiLog>> build() async {
    return await ref.watch(databaseProvider).getAllAiLogs();
  }

  Future<void> refreshLogs() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(databaseProvider).getAllAiLogs(),
    );
  }

  Future<void> clearLogs() async {
    await ref.read(databaseProvider).clearAiLogs();
    await refreshLogs();
  }
}

final aiLogProvider = AsyncNotifierProvider<AiLogNotifier, List<AiLog>>(
  AiLogNotifier.new,
);

// ─── Sync ─────────────────────────────────────────────────────────────────

enum SyncPhase {
  idle,
  requestingPermissions,
  fetchingSms,
  analyzing,
  complete,
  error,
}

class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.errorMessage,
    this.detail,
    this.current = 0,
    this.total = 0,
    this.imported = 0,
    this.skipped = 0,
  });
  final SyncPhase phase;
  final String? errorMessage;
  final String? detail;

  /// Index of the SMS currently being parsed (1-based).
  final int current;

  /// Total SMS queued for parsing.
  final int total;
  final int imported;
  final int skipped;

  bool get isAnalyzing => phase == SyncPhase.analyzing && total > 0;

  SyncState copyWith({
    SyncPhase? phase,
    String? errorMessage,
    String? detail,
    int? current,
    int? total,
    int? imported,
    int? skipped,
  }) => SyncState(
    phase: phase ?? this.phase,
    errorMessage: errorMessage ?? this.errorMessage,
    detail: detail ?? this.detail,
    current: current ?? this.current,
    total: total ?? this.total,
    imported: imported ?? this.imported,
    skipped: skipped ?? this.skipped,
  );

  static const idle = SyncState();
}

class SyncNotifier extends Notifier<SyncState> {
  final SmsService _smsService = SmsService();
  bool _cancelled = false;
  bool _paused = false;
  Completer<void>? _resumeSignal;

  @override
  SyncState build() => SyncState.idle;

  void cancel() {
    _cancelled = true;
    resume();
  }

  void pause() {
    if (state.phase == SyncPhase.analyzing) _paused = true;
  }

  void resume() {
    _paused = false;
    _resumeSignal?.complete();
    _resumeSignal = null;
  }

  Future<void> _waitWhilePaused() async {
    if (!_paused) return;
    state = state.copyWith(detail: 'Paused · unlock to continue safely');
    _resumeSignal ??= Completer<void>();
    await _resumeSignal!.future;
  }

  void _error(String message) {
    state = SyncState(phase: SyncPhase.error, errorMessage: message);
  }

  Future<void> sync() async {
    _cancelled = false;
    if (ref.read(ollamaApiKeyProvider).trim().isEmpty) {
      _error('Connect Flow intelligence in You before analyzing messages.');
      return;
    }

    state = const SyncState(phase: SyncPhase.requestingPermissions);
    final hasPermission = await _smsService.requestPermissions();
    if (!hasPermission) {
      _error('SMS permission denied. Grant SMS access in system settings.');
      return;
    }

    final db = ref.read(databaseProvider);
    final lookbackDays = ref.read(syncLookbackProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoffDate = today.subtract(Duration(days: lookbackDays));
    final cutoffTimestamp = cutoffDate.millisecondsSinceEpoch;

    state = SyncState(
      phase: SyncPhase.fetchingSms,
      detail: 'Reading the last $lookbackDays days from your inbox',
    );
    final messages = await _smsService.getMessages(since: cutoffDate);
    final catService = CategorizationService(
      apiKey: ref.read(ollamaApiKeyProvider),
      baseUrl: ref.read(ollamaBaseUrlProvider),
      model: ref.read(ollamaModelProvider),
      currency: ref.read(preferredCurrencyProvider),
    );

    state = SyncState(
      phase: SyncPhase.analyzing,
      detail:
          '${messages.length} SMS in inbox · scanning last $lookbackDays days',
    );

    final List<Map<String, dynamic>> unparsedSms = [];
    final Set<String> seenBodies = {};
    int alreadyParsedCount = 0;

    final parsedKeys = await db.getParsedSmsKeys(cutoffTimestamp);

    for (var msg in messages) {
      final msgBody = msg.body;
      final msgDate = msg.date ?? now;
      final sender = msg.address ?? 'Unknown';
      final timestamp = msg.date?.millisecondsSinceEpoch ?? 0;

      if (msgBody == null || msgDate.isBefore(cutoffDate)) continue;

      final seenKey = '$sender|$msgBody|$timestamp';
      if (seenBodies.contains(seenKey)) continue;

      if (!parsedKeys.contains(seenKey)) {
        unparsedSms.add({
          'body': msgBody,
          'date': msgDate.toIso8601String(),
          'address': sender,
          'timestamp': timestamp,
        });
        seenBodies.add(seenKey);
      } else {
        alreadyParsedCount++;
      }
    }

    debugPrint(
      '[Sync] inbox=${messages.length} '
      'alreadyParsed=$alreadyParsedCount queued=${unparsedSms.length} '
      'lookback=${lookbackDays}d cutoff=$cutoffDate',
    );

    final total = unparsedSms.length;

    state = SyncState(
      phase: SyncPhase.analyzing,
      detail: '$total new SMS to analyze',
      total: total,
      current: 0,
    );

    var importedCount = 0;
    var skippedCount = 0;
    if (total > 0) {
      // Run two 12-message AI batches per wave. Each batch is published as soon
      // as it finishes, so the ledger visibly fills while the second request
      // and later waves continue in the background.
      const aiBatchSize = 12;
      const waveSize = aiBatchSize * 2;
      var processed = 0;

      Future<void> processBatch(List<Map<String, dynamic>> batch) async {
        try {
          final result = await catService.parseSmsBatch(batch);
          if (result.expenses.isNotEmpty) {
            await ref
                .read(expenseListProvider.notifier)
                .insertExpensesProgressively(result.expenses);
            importedCount += result.expenses.length;
          }
          skippedCount += result.skipReasons.length;
          final confirmed = batch
              .where((sms) => result.skipReasons[sms['body']] != 'parse_error')
              .toList();
          if (confirmed.isNotEmpty) {
            await db.markSmsBatchParsed(
              confirmed,
              skipReasons: result.skipReasons,
            );
          }
        } catch (error) {
          debugPrint('AI batch failed: $error');
        } finally {
          processed += batch.length;
          state = SyncState(
            phase: SyncPhase.analyzing,
            detail: '$processed of $total analyzed · $importedCount imported',
            current: processed,
            total: total,
            imported: importedCount,
            skipped: skippedCount,
          );
        }
      }

      for (var i = 0; i < total; i += waveSize) {
        await _waitWhilePaused();
        if (_cancelled) break;

        final waveEnd = (i + waveSize).clamp(0, total);
        final batches = <List<Map<String, dynamic>>>[];
        for (var start = i; start < waveEnd; start += aiBatchSize) {
          batches.add(
            unparsedSms.sublist(start, (start + aiBatchSize).clamp(0, waveEnd)),
          );
        }
        await Future.wait(batches.map(processBatch));
      }

      if (_cancelled) {
        await ref.read(expenseListProvider.notifier).refreshPreservingData();
        final done = state.current;
        state = SyncState(
          phase: SyncPhase.complete,
          detail: 'Stopped after $done / $total',
          current: done,
          total: total,
          imported: importedCount,
          skipped: skippedCount,
        );
        return;
      }

      ref.invalidate(parsedSmsAuditProvider);
      await ref.read(expenseListProvider.notifier).refreshPreservingData();
    }

    try {
      await ref.read(aiLogProvider.notifier).refreshLogs();
    } catch (_) {}

    await db.setAppMetadata('last_sync_at', DateTime.now().toIso8601String());

    HapticFeedback.mediumImpact();

    final completeDetail = total == 0
        ? 'No new messages (${alreadyParsedCount > 0 ? '$alreadyParsedCount already parsed' : 'none matched'})'
        : '$total analyzed · $importedCount imported';
    state = SyncState(
      phase: SyncPhase.complete,
      detail: completeDetail,
      current: total,
      total: total,
      imported: importedCount,
      skipped: skippedCount,
    );
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);

// ─── Onboarding ────────────────────────────────────────────────────────────

final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final done = await storage.read(key: 'onboarding_done');
  return done == 'true';
});

Future<void> markOnboardingDone(FlutterSecureStorage storage) async {
  await storage.write(key: 'onboarding_done', value: 'true');
}
