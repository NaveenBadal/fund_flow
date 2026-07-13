import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/ai_provider.dart';
import '../models/action_item.dart';
import '../models/budget.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/ai_log.dart';
import '../models/financial_health_score.dart';
import '../models/savings_goal.dart';
import '../models/merchant_stats.dart';
import '../models/money_briefing.dart';
import '../models/spending_insight.dart';
import '../services/anomaly_detector.dart';
import '../services/action_inbox_service.dart';
import '../services/database_helper.dart';
import '../services/export_service.dart';
import '../services/insights_service.dart';
import '../services/notification_service.dart';
import '../services/money_briefing_service.dart';
import '../services/recurring_detector.dart';
import '../services/sms_service.dart';
import '../services/categorization_service.dart';
import '../utils/category_utils.dart';

// ─── Infrastructure ────────────────────────────────────────────────────────

final secureStorageProvider = Provider((ref) => const FlutterSecureStorage());
final exportServiceProvider = Provider((ref) => const ExportService());

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

class MonthlyPlanNotifier extends Notifier<({double income, double buffer})> {
  @override
  ({double income, double buffer}) build() => (income: 0, buffer: 0);

  Future<void> setPlan({required double income, required double buffer}) async {
    state = (income: income, buffer: buffer);
    final storage = ref.read(secureStorageProvider);
    await Future.wait([
      storage.write(key: 'planned_monthly_income', value: '$income'),
      storage.write(key: 'monthly_safety_buffer', value: '$buffer'),
    ]);
  }

  void restore({required double income, required double buffer}) {
    state = (income: income, buffer: buffer);
  }
}

final monthlyPlanProvider =
    NotifierProvider<MonthlyPlanNotifier, ({double income, double buffer})>(
      MonthlyPlanNotifier.new,
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
  final plannedIncome = double.tryParse(
    await storage.read(key: 'planned_monthly_income') ?? '',
  );
  final buffer = double.tryParse(
    await storage.read(key: 'monthly_safety_buffer') ?? '',
  );
  ref
      .read(monthlyPlanProvider.notifier)
      .restore(income: plannedIncome ?? 0, buffer: buffer ?? 0);

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
    await ref.read(databaseProvider).insertExpenses(expenses);
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

// ─── Budget ───────────────────────────────────────────────────────────────

class BudgetNotifier extends AsyncNotifier<List<Budget>> {
  @override
  Future<List<Budget>> build() async {
    return await ref.watch(databaseProvider).getAllBudgets();
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(databaseProvider).getAllBudgets(),
    );
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

final budgetListProvider = AsyncNotifierProvider<BudgetNotifier, List<Budget>>(
  BudgetNotifier.new,
);

final budgetProgressProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final budgets = await ref.watch(budgetListProvider.future);
  final expenses = await ref.watch(expenseListProvider.future);
  final currency = ref.watch(preferredCurrencyProvider);
  final now = DateTime.now();
  return [
    for (final budget in budgets.where((b) => b.currency == currency))
      <String, dynamic>{
        'category': budget.category,
        'limit_amount': budget.limitAmount,
        'currency': budget.currency,
        'spent': expenses
            .where(
              (e) =>
                  !e.isIncome &&
                  e.currency == currency &&
                  e.category == budget.category &&
                  e.date.year == now.year &&
                  e.date.month == now.month,
            )
            .fold(0.0, (sum, e) => sum + e.amount),
      },
  ];
});

// ─── Analytics ────────────────────────────────────────────────────────────

class AnalyticsPeriodNotifier extends Notifier<int> {
  @override
  int build() => 6;
  void setPeriod(int months) => state = months;
}

final analyticsPeriodProvider = NotifierProvider<AnalyticsPeriodNotifier, int>(
  AnalyticsPeriodNotifier.new,
);

final monthlyTotalsProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final months = ref.watch(analyticsPeriodProvider);
  final currency = ref.watch(preferredCurrencyProvider);
  final expenses = await ref.watch(expenseListProvider.future);
  final now = DateTime.now();
  return [
    for (var offset = months - 1; offset >= 0; offset--)
      () {
        final date = DateTime(now.year, now.month - offset);
        final entries = expenses.where(
          (e) =>
              e.currency == currency &&
              e.date.year == date.year &&
              e.date.month == date.month,
        );
        return <String, dynamic>{
          'year': date.year,
          'month': date.month,
          'total_income': entries
              .where((e) => e.isIncome)
              .fold(0.0, (sum, e) => sum + e.amount),
          'total_expense': entries
              .where((e) => !e.isIncome)
              .fold(0.0, (sum, e) => sum + e.amount),
        };
      }(),
  ];
});

final categoryTotalsForPeriodProvider = FutureProvider<Map<String, double>>((
  ref,
) async {
  final months = ref.watch(analyticsPeriodProvider);
  final currency = ref.watch(preferredCurrencyProvider);
  final expenses = await ref.watch(expenseListProvider.future);
  final to = DateTime.now();
  final from = DateTime(to.year, to.month - months + 1, 1);
  final totals = <String, double>{};
  for (final expense in expenses.where(
    (e) =>
        !e.isIncome &&
        e.currency == currency &&
        !e.date.isBefore(from) &&
        !e.date.isAfter(to),
  )) {
    totals.update(
      expense.category,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
  }
  return totals;
});

final topMerchantsForPeriodProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
      final months = ref.watch(analyticsPeriodProvider);
      final currency = ref.watch(preferredCurrencyProvider);
      final expenses = await ref.watch(expenseListProvider.future);
      final to = DateTime.now();
      final from = DateTime(to.year, to.month - months + 1, 1);
      final grouped = <String, List<Expense>>{};
      for (final expense in expenses.where(
        (e) =>
            !e.isIncome &&
            e.currency == currency &&
            !e.date.isBefore(from) &&
            !e.date.isAfter(to),
      )) {
        grouped.putIfAbsent(expense.displayMerchant, () => []).add(expense);
      }
      final rows = grouped.entries
          .map(
            (entry) => <String, dynamic>{
              'merchant': entry.key,
              'total': entry.value.fold(0.0, (sum, e) => sum + e.amount),
              'txn_count': entry.value.length,
            },
          )
          .toList();
      rows.sort(
        (a, b) => (b['total'] as double).compareTo(a['total'] as double),
      );
      return rows;
    });

final currentMonthBalanceProvider = FutureProvider<Map<String, double>>((
  ref,
) async {
  final expenses = await ref.watch(expenseListProvider.future);
  final currency = ref.watch(preferredCurrencyProvider);
  final now = DateTime.now();
  final month = expenses.where(
    (e) =>
        e.currency == currency &&
        e.date.year == now.year &&
        e.date.month == now.month,
  );
  return {
    'income': month
        .where((e) => e.isIncome)
        .fold(0.0, (sum, e) => sum + e.amount),
    'expense': month
        .where((e) => !e.isIncome)
        .fold(0.0, (sum, e) => sum + e.amount),
  };
});

/// A local, explainable forecast that turns balances, bills, budgets and goals
/// into one safe-to-spend number and one recommended next action.
final moneyBriefingProvider = Provider<MoneyBriefing?>((ref) {
  final expenses = ref.watch(expenseListProvider).asData?.value;
  if (expenses == null) return null;
  final currency = ref.watch(preferredCurrencyProvider);
  final budgets = ref.watch(budgetListProvider).asData?.value ?? const [];
  final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
  final plan = ref.watch(monthlyPlanProvider);
  return MoneyBriefingService.compute(
    expenses: expenses.where((e) => e.currency == currency).toList(),
    budgets: budgets,
    goals: goals,
    plannedIncome: plan.income,
    safetyBuffer: plan.buffer,
  );
});

// ─── Spending insights & anomalies ────────────────────────────────────────

final spendingInsightsProvider = FutureProvider<List<SpendingInsight>>((
  ref,
) async {
  final expenses = ref.watch(expenseListProvider).asData?.value ?? [];
  final currency = ref.watch(preferredCurrencyProvider);
  return InsightsService.compute(
    expenses.where((e) => e.currency == currency).toList(),
  );
});

final anomalyAlertsProvider = FutureProvider<List<SpendingInsight>>((
  ref,
) async {
  final expenses = ref.watch(expenseListProvider).asData?.value ?? [];
  final currency = ref.watch(preferredCurrencyProvider);
  return AnomalyDetector.detect(
    expenses.where((e) => e.currency == currency).toList(),
  );
});

// ─── Financial health score ────────────────────────────────────────────────

final financialHealthScoreProvider = FutureProvider<FinancialHealthScore>((
  ref,
) async {
  final balance = await ref.watch(currentMonthBalanceProvider.future);
  final budgetProg = await ref.watch(budgetProgressProvider.future);
  final now = DateTime.now();
  final prevMonth = now.month == 1
      ? DateTime(now.year - 1, 12)
      : DateTime(now.year, now.month - 1);
  final expenses = await ref.watch(expenseListProvider.future);
  final currency = ref.watch(preferredCurrencyProvider);
  final previousExpense = expenses
      .where(
        (e) =>
            !e.isIncome &&
            e.currency == currency &&
            e.date.year == prevMonth.year &&
            e.date.month == prevMonth.month,
      )
      .fold(0.0, (sum, e) => sum + e.amount);

  return FinancialHealthScore.compute(
    totalIncome: balance['income'] ?? 0,
    totalExpense: balance['expense'] ?? 0,
    budgetProgress: budgetProg,
    previousMonthExpense: previousExpense,
  );
});

// ─── Merchant stats ────────────────────────────────────────────────────────

final merchantStatsProvider = FutureProvider.family<MerchantStats, String>((
  ref,
  merchant,
) async {
  final currency = ref.watch(preferredCurrencyProvider);
  final expenses = await ref.watch(expenseListProvider.future);
  final items =
      expenses
          .where(
            (e) =>
                !e.isIncome &&
                e.currency == currency &&
                e.displayMerchant.toLowerCase() == merchant.toLowerCase(),
          )
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
  final total = items.fold(0.0, (sum, e) => sum + e.amount);
  final now = DateTime.now();
  final monthly = <MonthlyMerchantTotal>[];
  for (var offset = 5; offset >= 0; offset--) {
    final date = DateTime(now.year, now.month - offset);
    monthly.add(
      MonthlyMerchantTotal(
        year: date.year,
        month: date.month,
        total: items
            .where(
              (e) => e.date.year == date.year && e.date.month == date.month,
            )
            .fold(0.0, (sum, e) => sum + e.amount),
      ),
    );
  }
  return MerchantStats(
    merchant: merchant,
    lifetimeTotal: total,
    transactionCount: items.length,
    firstTransactionDate: items.firstOrNull?.date,
    averageAmount: items.isEmpty ? 0 : total / items.length,
    monthlyTotals: monthly,
  );
});

// ─── Heatmap data ──────────────────────────────────────────────────────────

final heatmapDataProvider = FutureProvider<Map<DateTime, double>>((ref) async {
  final currency = ref.watch(preferredCurrencyProvider);
  final expenses = await ref.watch(expenseListProvider.future);
  final to = DateTime.now();
  final from = to.subtract(const Duration(days: 364));
  final totals = <DateTime, double>{};
  for (final expense in expenses.where(
    (e) =>
        !e.isIncome &&
        e.currency == currency &&
        !e.date.isBefore(from) &&
        !e.date.isAfter(to),
  )) {
    final day = DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
    );
    totals.update(
      day,
      (value) => value + expense.amount,
      ifAbsent: () => expense.amount,
    );
  }
  return totals;
});

// ─── Year in review ────────────────────────────────────────────────────────

final yearInReviewProvider = FutureProvider.family<Map<String, dynamic>, int>((
  ref,
  year,
) async {
  final currency = ref.watch(preferredCurrencyProvider);
  final expenses = await ref.watch(expenseListProvider.future);
  final items = expenses
      .where(
        (e) => !e.isIncome && e.currency == currency && e.date.year == year,
      )
      .toList();
  final merchants = <String, double>{};
  final categories = <String, double>{};
  final days = <DateTime, double>{};
  for (final expense in items) {
    merchants.update(
      expense.displayMerchant,
      (v) => v + expense.amount,
      ifAbsent: () => expense.amount,
    );
    categories.update(
      expense.category,
      (v) => v + expense.amount,
      ifAbsent: () => expense.amount,
    );
    final day = DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
    );
    days.update(day, (v) => v + expense.amount, ifAbsent: () => expense.amount);
  }
  MapEntry<String, double>? topMerchant;
  MapEntry<String, double>? topCategory;
  MapEntry<DateTime, double>? topDay;
  if (merchants.isNotEmpty) {
    topMerchant = merchants.entries.reduce((a, b) => a.value > b.value ? a : b);
  }
  if (categories.isNotEmpty) {
    topCategory = categories.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );
  }
  if (days.isNotEmpty) {
    topDay = days.entries.reduce((a, b) => a.value > b.value ? a : b);
  }
  final daysInYear = DateTime(year + 1, 1, 1).difference(DateTime(year)).inDays;
  return {
    'topMerchant': topMerchant?.key,
    'topMerchantTotal': topMerchant?.value ?? 0.0,
    'topCategory': topCategory?.key,
    'totalSpent': items.fold(0.0, (sum, e) => sum + e.amount),
    'maxSpendDay': topDay?.key.toIso8601String(),
    'maxSpendAmount': topDay?.value ?? 0.0,
    'activeDays': days.length,
    'zeroSpendDays': daysInYear - days.length,
  };
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

final previousMonthBalanceProvider = FutureProvider<Map<String, double>>((
  ref,
) async {
  final expenses = await ref.watch(expenseListProvider.future);
  final currency = ref.watch(preferredCurrencyProvider);
  final now = DateTime.now();
  final prev = now.month == 1
      ? DateTime(now.year - 1, 12)
      : DateTime(now.year, now.month - 1);
  final month = expenses.where(
    (e) =>
        e.currency == currency &&
        e.date.year == prev.year &&
        e.date.month == prev.month,
  );
  return {
    'income': month
        .where((e) => e.isIncome)
        .fold(0.0, (sum, e) => sum + e.amount),
    'expense': month
        .where((e) => !e.isIncome)
        .fold(0.0, (sum, e) => sum + e.amount),
  };
});

// ─── Parsed SMS audit ─────────────────────────────────────────────────────

final parsedSmsAuditProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  return ref.read(databaseProvider).getParsedSmsAudit();
});

class ActionDismissalsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() =>
      ref.watch(databaseProvider).getDismissedActionKeys();

  Future<void> dismiss(String key) async {
    await ref.read(databaseProvider).dismissAction(key);
    state = AsyncValue.data({...?state.asData?.value, key});
  }

  Future<void> restore(String key) async {
    await ref.read(databaseProvider).restoreAction(key);
    final next = {...?state.asData?.value}..remove(key);
    state = AsyncValue.data(next);
  }
}

final actionDismissalsProvider =
    AsyncNotifierProvider<ActionDismissalsNotifier, Set<String>>(
      ActionDismissalsNotifier.new,
    );

final actionInboxProvider = FutureProvider<List<ActionItem>>((ref) async {
  final expenses = await ref.watch(expenseListProvider.future);
  final currency = ref.watch(preferredCurrencyProvider);
  final budgets = await ref.watch(budgetListProvider.future);
  final goals = await ref.watch(savingsGoalsProvider.future);
  final audit = await ref.watch(parsedSmsAuditProvider.future);
  final dismissed = await ref.watch(actionDismissalsProvider.future);
  final plan = ref.watch(monthlyPlanProvider);
  final briefing = MoneyBriefingService.compute(
    expenses: expenses.where((e) => e.currency == currency).toList(),
    budgets: budgets,
    goals: goals,
    plannedIncome: plan.income,
    safetyBuffer: plan.buffer,
  );
  return ActionInboxService.compute(
    expenses: expenses.where((e) => e.currency == currency).toList(),
    budgets: budgets,
    smsAudit: audit,
    briefing: briefing,
    dismissedKeys: dismissed,
  );
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
  });
  final SyncPhase phase;
  final String? errorMessage;
  final String? detail;

  /// Index of the SMS currently being parsed (1-based).
  final int current;

  /// Total SMS queued for parsing.
  final int total;

  bool get isAnalyzing => phase == SyncPhase.analyzing && total > 0;

  SyncState copyWith({
    SyncPhase? phase,
    String? errorMessage,
    String? detail,
    int? current,
    int? total,
  }) => SyncState(
    phase: phase ?? this.phase,
    errorMessage: errorMessage ?? this.errorMessage,
    detail: detail ?? this.detail,
    current: current ?? this.current,
    total: total ?? this.total,
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
      _error('Add your Ollama Cloud API key in Settings before syncing.');
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
    final catService = CategorizationService(
      apiKey: ref.read(ollamaApiKeyProvider),
      baseUrl: ref.read(ollamaBaseUrlProvider),
      model: ref.read(ollamaModelProvider),
      currency: ref.read(preferredCurrencyProvider),
    );
    final lookbackDays = ref.read(syncLookbackProvider);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cutoffDate = today.subtract(Duration(days: lookbackDays));
    final cutoffTimestamp = cutoffDate.millisecondsSinceEpoch;

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
        );
        Future.delayed(const Duration(seconds: 4), () {
          if (state.phase == SyncPhase.complete) state = SyncState.idle;
        });
        return;
      }

      ref.invalidate(parsedSmsAuditProvider);

      try {
        final allExpenses = await db.getAllExpenses();
        final flags = RecurringDetector.detect(allExpenses);
        await db.updateRecurringFlags(flags);
        await ref.read(expenseListProvider.notifier).refreshPreservingData();
      } catch (_) {}
    }

    try {
      await ref.read(aiLogProvider.notifier).refreshLogs();
    } catch (_) {}

    await db.setAppMetadata('last_sync_at', DateTime.now().toIso8601String());

    HapticFeedback.mediumImpact();

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

    final completeDetail = total == 0
        ? 'No new messages (${alreadyParsedCount > 0 ? '$alreadyParsedCount already parsed' : 'none matched'})'
        : '$total analyzed · $importedCount imported';
    state = SyncState(phase: SyncPhase.complete, detail: completeDetail);
    Future.delayed(const Duration(seconds: 4), () {
      if (state.phase == SyncPhase.complete) state = SyncState.idle;
    });
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);

// ─── Savings Goals ─────────────────────────────────────────────────────────

class SavingsGoalNotifier extends AsyncNotifier<List<SavingsGoal>> {
  @override
  Future<List<SavingsGoal>> build() async {
    return await ref.watch(databaseProvider).getAllSavingsGoals();
  }

  Future<void> _reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(databaseProvider).getAllSavingsGoals(),
    );
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
      SavingsGoalNotifier.new,
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
