import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/ai_provider.dart';
import '../models/budget.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/ai_log.dart';
import '../models/financial_health_score.dart';
import '../models/savings_goal.dart';
import '../models/flutter_gemma_model_info.dart';
import '../models/merchant_stats.dart';
import '../models/spending_insight.dart';
import '../services/anomaly_detector.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/flutter_gemma_service.dart';
import '../services/gemini_model_catalog_service.dart';
import '../services/insights_service.dart';
import '../services/notification_service.dart';
import '../services/offline_model_service.dart';
import '../services/recurring_detector.dart';
import '../services/sms_service.dart';
import '../services/categorization_service.dart';
import '../utils/category_utils.dart';

// ─── Infrastructure ────────────────────────────────────────────────────────

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());
final geminiModelCatalogServiceProvider =
    Provider((ref) => const GeminiModelCatalogService());
final offlineModelServiceProvider =
    Provider((ref) => const OfflineModelService());
final flutterGemmaServiceProvider =
    Provider((ref) => const FlutterGemmaService());
final exportServiceProvider = Provider((ref) => const ExportService());

// ─── AI Provider selection ─────────────────────────────────────────────────

class ProviderApiKeysNotifier extends Notifier<Map<AiProviderType, String>> {
  @override
  Map<AiProviderType, String> build() =>
      {for (final p in AiProviderType.values) p: ''};

  void setKey(AiProviderType provider, String key) =>
      state = {...state, provider: key};
}

final providerApiKeysProvider =
    NotifierProvider<ProviderApiKeysNotifier, Map<AiProviderType, String>>(
        ProviderApiKeysNotifier.new);

class SelectedAiProviderNotifier extends Notifier<AiProviderType> {
  @override
  AiProviderType build() => AiProviderType.gemini;
  void setProvider(AiProviderType p) => state = p;
}

final selectedAiProviderProvider =
    NotifierProvider<SelectedAiProviderNotifier, AiProviderType>(
        SelectedAiProviderNotifier.new);

class SyncLookbackNotifier extends Notifier<int> {
  @override
  int build() => 30;
  void setDays(int days) => state = days;
}

final syncLookbackProvider =
    NotifierProvider<SyncLookbackNotifier, int>(SyncLookbackNotifier.new);

const onDeviceMaxTokensStorageKey = 'on_device_max_tokens';
const onDeviceMaxTokensDefault = 4096;

class OnDeviceMaxTokensNotifier extends Notifier<int> {
  @override
  int build() => onDeviceMaxTokensDefault;
  void setTokens(int tokens) => state = tokens;
}

final onDeviceMaxTokensProvider =
    NotifierProvider<OnDeviceMaxTokensNotifier, int>(
        OnDeviceMaxTokensNotifier.new);

class ProviderModelsNotifier extends Notifier<Map<AiProviderType, String>> {
  @override
  Map<AiProviderType, String> build() =>
      {for (final p in AiProviderType.values) p: defaultModelFor(p)};

  void setModel(AiProviderType provider, String model) =>
      state = {...state, provider: model};
}

final providerModelsProvider =
    NotifierProvider<ProviderModelsNotifier, Map<AiProviderType, String>>(
        ProviderModelsNotifier.new);

final activeApiKeyProvider = Provider<String?>((ref) {
  final provider = ref.watch(selectedAiProviderProvider);
  final apiKeys = ref.watch(providerApiKeysProvider);
  final key = apiKeys[provider]?.trim();
  return (key == null || key.isEmpty) ? null : key;
});

final activeModelProvider = Provider<String>((ref) {
  final provider = ref.watch(selectedAiProviderProvider);
  final models = ref.watch(providerModelsProvider);
  final model = models[provider]?.trim();
  return (model == null || model.isEmpty) ? defaultModelFor(provider) : model;
});

// ─── Model catalog providers ───────────────────────────────────────────────

final availableGeminiModelsProvider =
    FutureProvider.family<List<GeminiModelCatalogItem>, String>(
        (ref, apiKey) async {
  if (apiKey.trim().isEmpty) return const [];
  return ref.watch(geminiModelCatalogServiceProvider).fetchModels(apiKey.trim());
});

final availableOfflineModelsProvider =
    FutureProvider<List<OfflineModelInfo>>((ref) async {
  return ref.watch(offlineModelServiceProvider).listModels();
});

final availableFlutterGemmaModelsProvider =
    FutureProvider<List<FlutterGemmaModelInfo>>((ref) async {
  return ref.watch(flutterGemmaServiceProvider).listModels();
});

// ─── Theme ────────────────────────────────────────────────────────────────

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void setThemeMode(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// ─── Privacy / App lock ────────────────────────────────────────────────────

class PrivateModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  void toggle() {
    state = !state;
  }
  
  void set(bool v) {
    state = v;
  }
}

final privateModeProvider =
    NotifierProvider<PrivateModeNotifier, bool>(PrivateModeNotifier.new);

class AppLockNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  Future<void> toggle() async {
    state = !state;
    await ref.read(secureStorageProvider).write(key: 'app_lock_enabled', value: state.toString());
  }
  
  void set(bool v) => state = v;
}

final appLockEnabledProvider =
    NotifierProvider<AppLockNotifier, bool>(AppLockNotifier.new);

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

  void set(bool v) => state = v;
}

final notificationParsingEnabledProvider =
    NotifierProvider<NotificationParsingNotifier, bool>(
        NotificationParsingNotifier.new);

// ─── Notification settings ─────────────────────────────────────────────────

class DailyDigestNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  Future<void> toggle() async {
    state = !state;
    await ref.read(secureStorageProvider).write(key: 'daily_digest_enabled', value: state.toString());
  }
  
  void set(bool v) => state = v;
}

final dailyDigestEnabledProvider =
    NotifierProvider<DailyDigestNotifier, bool>(DailyDigestNotifier.new);

// ─── Settings initializer ──────────────────────────────────────────────────

final settingsInitializer = FutureProvider<void>((ref) async {
  final storage = ref.watch(secureStorageProvider);

  for (final provider in AiProviderType.values) {
    final apiKey = await storage.read(key: provider.apiKeyStorageKey);
    if (apiKey != null) {
      ref.read(providerApiKeysProvider.notifier).setKey(provider, apiKey);
    }
    final savedModel = await storage.read(key: provider.modelStorageKey);
    if (savedModel != null && savedModel.trim().isNotEmpty) {
      ref.read(providerModelsProvider.notifier).setModel(provider, savedModel.trim());
    }
  }

  final lookback = await storage.read(key: 'sync_lookback_days');
  if (lookback != null) {
    ref.read(syncLookbackProvider.notifier).setDays(int.tryParse(lookback) ?? 30);
  }

  final maxTokens = await storage.read(key: onDeviceMaxTokensStorageKey);
  if (maxTokens != null) {
    ref.read(onDeviceMaxTokensProvider.notifier)
        .setTokens(int.tryParse(maxTokens) ?? onDeviceMaxTokensDefault);
  }

  final selectedProvider = await storage.read(key: selectedAiProviderStorageKey);
  ref
      .read(selectedAiProviderProvider.notifier)
      .setProvider(aiProviderFromId(selectedProvider));

  final legacyGeminiModel = await storage.read(key: 'gemini_model');
  if (legacyGeminiModel != null && legacyGeminiModel.trim().isNotEmpty) {
    ref
        .read(providerModelsProvider.notifier)
        .setModel(AiProviderType.gemini, legacyGeminiModel.trim());
  }

  final legacyGeminiKey = await storage.read(key: 'gemini_api_key');
  if (legacyGeminiKey != null && legacyGeminiKey.trim().isNotEmpty) {
    ref
        .read(providerApiKeysProvider.notifier)
        .setKey(AiProviderType.gemini, legacyGeminiKey.trim());
  }

  final theme = await storage.read(key: 'theme_mode');
  if (theme != null) {
    final mode = ThemeMode.values.firstWhere(
      (e) => e.toString() == theme,
      orElse: () => ThemeMode.system,
    );
    ref.read(themeModeProvider.notifier).setThemeMode(mode);
  }

  final appLock = await storage.read(key: 'app_lock_enabled');
  ref.read(appLockEnabledProvider.notifier).set(appLock == 'true');

  final dailyDigest = await storage.read(key: 'daily_digest_enabled');
  ref.read(dailyDigestEnabledProvider.notifier).set(dailyDigest == 'true');

  final notifParsing = await storage.read(key: 'notification_parsing_enabled');
  ref.read(notificationParsingEnabledProvider.notifier).set(notifParsing == 'true');
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
        () => ref.read(databaseProvider).getAllExpenses());
  }

  Future<void> addExpense(Expense expense) async {
    await ref.read(databaseProvider).insertExpenses([expense]);
    await refreshExpenses();
  }

  Future<void> addExpenses(List<Expense> expenses) async {
    await ref.read(databaseProvider).insertExpenses(expenses);
    await refreshExpenses();
  }

  Future<void> updateExpense(Expense expense) async {
    await ref.read(databaseProvider).updateExpense(expense);
    // Learn category correction
    try {
      final key = (expense.normalizedMerchant ?? expense.merchant).toLowerCase().trim();
      await ref.read(databaseProvider).upsertMerchantCategory(key, expense.category);
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
        ExpenseListNotifier.new);

// ─── Custom categories ─────────────────────────────────────────────────────

class CustomCategoryNotifier extends AsyncNotifier<List<CustomCategory>> {
  @override
  Future<List<CustomCategory>> build() async {
    return await ref.watch(databaseProvider).getAllCustomCategories();
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(databaseProvider).getAllCustomCategories());
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
        CustomCategoryNotifier.new);

/// All category names: builtins + custom
final allCategoryNamesProvider = Provider<List<String>>((ref) {
  final custom = ref.watch(customCategoryListProvider).asData?.value ?? [];
  return [...kBuiltinCategories, ...custom.map((c) => c.name)];
});

// ─── Budget ───────────────────────────────────────────────────────────────

class BudgetNotifier extends AsyncNotifier<List<Budget>> {
  @override
  Future<List<Budget>> build() async {
    return await ref.watch(databaseProvider).getAllBudgets();
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(databaseProvider).getAllBudgets());
  }

  Future<void> upsert(Budget budget) async {
    await ref.read(databaseProvider).insertOrUpdateBudget(budget);
    await _reload();
  }

  Future<void> remove(String category) async {
    await ref.read(databaseProvider).deleteBudget(category);
    await _reload();
  }
}

final budgetListProvider =
    AsyncNotifierProvider<BudgetNotifier, List<Budget>>(BudgetNotifier.new);

final budgetProgressProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(budgetListProvider);
  ref.watch(expenseListProvider);
  final now = DateTime.now();
  return ref.read(databaseProvider).getBudgetProgress(now.year, now.month);
});

// ─── Analytics ────────────────────────────────────────────────────────────

class AnalyticsPeriodNotifier extends Notifier<int> {
  @override
  int build() => 6;
  void setPeriod(int months) => state = months;
}

final analyticsPeriodProvider =
    NotifierProvider<AnalyticsPeriodNotifier, int>(AnalyticsPeriodNotifier.new);

final monthlyTotalsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final months = ref.watch(analyticsPeriodProvider);
  ref.watch(expenseListProvider);
  return ref.read(databaseProvider).getMonthlyTotals(months: months);
});

final categoryTotalsForPeriodProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final months = ref.watch(analyticsPeriodProvider);
  ref.watch(expenseListProvider);
  final to = DateTime.now();
  final from = DateTime(to.year, to.month - months + 1, 1);
  return ref.read(databaseProvider).getCategoryTotals(from, to);
});

final topMerchantsForPeriodProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final months = ref.watch(analyticsPeriodProvider);
  ref.watch(expenseListProvider);
  final to = DateTime.now();
  final from = DateTime(to.year, to.month - months + 1, 1);
  return ref.read(databaseProvider).getTopMerchants(from, to);
});

final currentMonthBalanceProvider =
    FutureProvider<Map<String, double>>((ref) async {
  ref.watch(expenseListProvider);
  final now = DateTime.now();
  return ref.read(databaseProvider).getMonthlyBalance(now.year, now.month);
});

// ─── Spending insights & anomalies ────────────────────────────────────────

final spendingInsightsProvider = FutureProvider<List<SpendingInsight>>((ref) async {
  final expenses = ref.watch(expenseListProvider).asData?.value ?? [];
  return InsightsService.compute(expenses);
});

final anomalyAlertsProvider = FutureProvider<List<SpendingInsight>>((ref) async {
  final expenses = ref.watch(expenseListProvider).asData?.value ?? [];
  return AnomalyDetector.detect(expenses);
});

// ─── Financial health score ────────────────────────────────────────────────

final financialHealthScoreProvider = FutureProvider<FinancialHealthScore>((ref) async {
  final balance = await ref.watch(currentMonthBalanceProvider.future);
  final budgetProg = await ref.watch(budgetProgressProvider.future);
  final now = DateTime.now();
  final prevMonth = now.month == 1
      ? DateTime(now.year - 1, 12)
      : DateTime(now.year, now.month - 1);
  final prevBalance = await ref
      .read(databaseProvider)
      .getMonthlyBalance(prevMonth.year, prevMonth.month);

  return FinancialHealthScore.compute(
    totalIncome: balance['income'] ?? 0,
    totalExpense: balance['expense'] ?? 0,
    budgetProgress: budgetProg,
    previousMonthExpense: prevBalance['expense'] ?? 0,
  );
});

// ─── Merchant stats ────────────────────────────────────────────────────────

final merchantStatsProvider =
    FutureProvider.family<MerchantStats, String>((ref, merchant) async {
  return ref.read(databaseProvider).getMerchantStats(merchant);
});

// ─── Heatmap data ──────────────────────────────────────────────────────────

final heatmapDataProvider = FutureProvider<Map<DateTime, double>>((ref) async {
  ref.watch(expenseListProvider);
  final to = DateTime.now();
  final from = to.subtract(const Duration(days: 364));
  return ref.read(databaseProvider).getDailyTotals(from, to);
});

// ─── Year in review ────────────────────────────────────────────────────────

final yearInReviewProvider =
    FutureProvider.family<Map<String, dynamic>, int>((ref, year) async {
  ref.watch(expenseListProvider);
  return ref.read(databaseProvider).getYearInReview(year);
});

// ─── Spending streak ──────────────────────────────────────────────────────

final spendingStreakProvider = FutureProvider<int>((ref) async {
  ref.watch(expenseListProvider);
  final to = DateTime.now();
  final from = to.subtract(const Duration(days: 365));
  final dailyTotals = await ref.read(databaseProvider).getDailyTotals(from, to);
  int streak = 0;
  var day = DateTime(to.year, to.month, to.day);
  while (true) {
    final key = dailyTotals.keys.firstWhere(
      (k) => k.year == day.year && k.month == day.month && k.day == day.day,
      orElse: () => DateTime(0),
    );
    if (key.year != 0 && (dailyTotals[key] ?? 0) > 0) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    } else {
      break;
    }
  }
  return streak;
});

// ─── Previous month balance ────────────────────────────────────────────────

final previousMonthBalanceProvider = FutureProvider<Map<String, double>>((ref) async {
  ref.watch(expenseListProvider);
  final now = DateTime.now();
  final prev = now.month == 1
      ? DateTime(now.year - 1, 12)
      : DateTime(now.year, now.month - 1);
  return ref.read(databaseProvider).getMonthlyBalance(prev.year, prev.month);
});

// ─── Parsed SMS audit ─────────────────────────────────────────────────────

final parsedSmsAuditProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
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
        () => ref.read(databaseProvider).getAllAiLogs());
  }

  Future<void> clearLogs() async {
    await ref.read(databaseProvider).clearAiLogs();
    await refreshLogs();
  }
}

final aiLogProvider =
    AsyncNotifierProvider<AiLogNotifier, List<AiLog>>(AiLogNotifier.new);

// ─── Sync ─────────────────────────────────────────────────────────────────

enum SyncPhase { idle, requestingPermissions, fetchingSms, analyzing, complete, error }

class SyncState {
  const SyncState({this.phase = SyncPhase.idle, this.errorMessage, this.detail});
  final SyncPhase phase;
  final String? errorMessage;
  /// Human-readable detail shown in UI (e.g. "48 SMS found · 3 queued").
  final String? detail;

  SyncState copyWith({SyncPhase? phase, String? errorMessage, String? detail}) =>
      SyncState(
        phase: phase ?? this.phase,
        errorMessage: errorMessage ?? this.errorMessage,
        detail: detail ?? this.detail,
      );

  static const idle = SyncState();
}

class SyncNotifier extends Notifier<SyncState> {
  final SmsService _smsService = SmsService();

  @override
  SyncState build() => SyncState.idle;

  void _error(String message) {
    state = SyncState(phase: SyncPhase.error, errorMessage: message);
  }

  Future<void> sync() async {
    final provider = ref.read(selectedAiProviderProvider);
    final needsApiKey = provider != AiProviderType.offline &&
        provider != AiProviderType.flutterGemma;
    final apiKey = needsApiKey ? ref.read(activeApiKeyProvider) : '';
    final modelName = ref.read(activeModelProvider);

    if (needsApiKey && (apiKey == null || apiKey.isEmpty)) {
      _error('No API key configured for ${provider.displayName}. Go to Settings.');
      return;
    }
    if (modelName.trim().isEmpty) {
      _error('No model selected for ${provider.displayName}. Go to Settings and choose a model.');
      return;
    }

    state = const SyncState(phase: SyncPhase.requestingPermissions);
    final hasPermission = await _smsService.requestPermissions();
    if (!hasPermission) {
      _error('SMS permission denied. Grant SMS access in system settings.');
      return;
    }

    state = const SyncState(phase: SyncPhase.fetchingSms);
    final messages = await _smsService.getMessages();
    final db = ref.read(databaseProvider);
    final maxTokens = ref.read(onDeviceMaxTokensProvider);
    final catService = CategorizationService(
      apiKey ?? '',
      provider: provider,
      modelName: modelName,
      onDeviceMaxTokens: maxTokens,
    );
    final lookbackDays = ref.read(syncLookbackProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoffDate = today.subtract(Duration(days: lookbackDays));
    final cutoffTimestamp = cutoffDate.millisecondsSinceEpoch;

    // Report how many raw SMS we fetched so user can see the window.
    state = SyncState(
      phase: SyncPhase.analyzing,
      detail: '${messages.length} SMS in inbox · scanning last $lookbackDays days',
    );

    final List<Map<String, dynamic>> unparsedSms = [];
    final Set<String> seenBodies = {};
    int financialCount = 0;
    int alreadyParsedCount = 0;

    // Prefetch all parsed message keys for this lookback window to avoid N+1 DB hits
    final parsedKeys = await db.getParsedSmsKeys(cutoffTimestamp);

    for (var msg in messages) {
      final msgBody = msg.body;
      final msgDate = msg.date ?? now;
      final sender = msg.address ?? 'Unknown';
      final timestamp = msg.date?.millisecondsSinceEpoch ?? 0;

      if (msgBody == null || msgDate.isBefore(cutoffDate)) continue;

      final seenKey = '$sender|$msgBody|$timestamp';
      if (seenBodies.contains(seenKey)) continue;

      if (_smsService.isFinancialSms(msgBody)) {
        financialCount++;
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
    }

    debugPrint('[Sync] inbox=${messages.length} financial=$financialCount '
        'alreadyParsed=$alreadyParsedCount queued=${unparsedSms.length} '
        'lookback=${lookbackDays}d cutoff=$cutoffDate');

    state = SyncState(
      phase: SyncPhase.analyzing,
      detail: '$financialCount financial SMS · ${unparsedSms.length} new to process',
    );

    if (unparsedSms.isNotEmpty) {
      const batchSize = 20;
      for (var i = 0; i < unparsedSms.length; i += batchSize) {
        final end =
            (i + batchSize < unparsedSms.length) ? i + batchSize : unparsedSms.length;
        final batch = unparsedSms.sublist(i, end);

        try {
          final result = await catService.parseSmsBatch(batch);
          if (result.expenses.isNotEmpty) {
            await ref.read(expenseListProvider.notifier).addExpenses(result.expenses);
          }
          await db.markSmsBatchParsed(batch, skipReasons: result.skipReasons);
        } catch (e) {
          debugPrint('Batch parse error: $e');
          final reasons = {for (final s in batch) s['body'] as String: 'parse_error'};
          try {
            await db.markSmsBatchParsed(batch, skipReasons: reasons);
          } catch (_) {}
        }
      }
      
      // Refresh the audit provider since parsed_sms changed
      ref.invalidate(parsedSmsAuditProvider);

      // Re-run recurring detection across all expenses so subscriptions
      // screen stays accurate after new transactions are added.
      try {
        final allExpenses = await db.getAllExpenses();
        final flags = RecurringDetector.detect(allExpenses);
        await db.updateRecurringFlags(flags);
        // Refresh expense list to reflect updated recurring flags.
        await ref.read(expenseListProvider.notifier).refreshExpenses();
      } catch (_) {}
    }

    // Always refresh the AI log list so the UI reflects the current DB state
    // regardless of whether there were new SMS to process this run.
    try {
      await ref.read(aiLogProvider.notifier).refreshLogs();
    } catch (_) {}

    // Save last sync timestamp
    await db.setAppMetadata('last_sync_at', DateTime.now().toIso8601String());

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Check budget proximity
    try {
      final budgetProgress = await db.getBudgetProgress(now.year, now.month);
      for (final b in budgetProgress) {
        final spent = (b['spent'] as num).toDouble();
        final limit = (b['limit_amount'] as num).toDouble();
        if (limit > 0 && spent / limit >= 0.8) {
          await NotificationService.instance.sendBudgetProximityAlert(
            b['category'] as String,
            spent / limit * 100,
          );
        }
      }
    } catch (_) {}

    final completeDetail = unparsedSms.isEmpty
        ? 'No new messages (${alreadyParsedCount > 0 ? '$alreadyParsedCount already parsed' : 'none matched'})'
        : '${unparsedSms.length} processed';
    state = SyncState(phase: SyncPhase.complete, detail: completeDetail);
    Future.delayed(const Duration(seconds: 4), () {
      if (state.phase == SyncPhase.complete) state = SyncState.idle;
    });
  }
}


final syncProvider =
    NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);

// ─── Savings Goals ─────────────────────────────────────────────────────────

class SavingsGoalNotifier extends AsyncNotifier<List<SavingsGoal>> {
  @override
  Future<List<SavingsGoal>> build() async {
    return await ref.watch(databaseProvider).getAllSavingsGoals();
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
        () => ref.read(databaseProvider).getAllSavingsGoals());
  }

  Future<void> upsert(SavingsGoal goal) async {
    await ref.read(databaseProvider).insertOrUpdateSavingsGoal(goal);
    await _reload();
  }

  Future<void> remove(int id) async {
    await ref.read(databaseProvider).deleteSavingsGoal(id);
    await _reload();
  }
}

final savingsGoalsProvider =
    AsyncNotifierProvider<SavingsGoalNotifier, List<SavingsGoal>>(
        SavingsGoalNotifier.new);

// ─── Onboarding ────────────────────────────────────────────────────────────

final onboardingDoneProvider = FutureProvider<bool>((ref) async {
  final storage = ref.watch(secureStorageProvider);
  final done = await storage.read(key: 'onboarding_done');
  return done == 'true';
});

Future<void> markOnboardingDone(FlutterSecureStorage storage) async {
  await storage.write(key: 'onboarding_done', value: 'true');
}
