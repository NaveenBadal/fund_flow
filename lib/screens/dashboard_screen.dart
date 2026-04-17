import 'package:confetti/confetti.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:intl/intl.dart';
import '../models/ai_provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/expense_form_sheet.dart';
import 'merchant_profile_screen.dart';
import 'settings_screen.dart';

// ─── Public screen ────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String _searchQuery = '';
  bool _searchOpen = false;
  final _searchController = TextEditingController();
  late ConfettiController _confettiController;
  double _lastMonthlyTotal = 0;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expenseListProvider);
    final syncStatus = ref.watch(syncProvider);
    final apiKey = ref.watch(activeApiKeyProvider);
    final modelName = ref.watch(activeModelProvider);
    final provider = ref.watch(selectedAiProviderProvider);
    final hasCredentials =
        provider == AiProviderType.offline ||
        provider == AiProviderType.flutterGemma ||
        (apiKey != null && apiKey.isNotEmpty);
    final hasModel = modelName.trim().isNotEmpty;

    final privateMode = ref.watch(privateModeProvider);

    // Show snackbar with detail when sync finishes or errors.
    ref.listen<SyncState>(syncProvider, (prev, next) {
      if (!mounted) return;
      if (next.phase == SyncPhase.complete && next.detail != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync complete: ${next.detail}'),
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (next.phase == SyncPhase.error && next.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search merchant or category…',
                  border: InputBorder.none,
                ),
                onChanged: (v) =>
                    setState(() => _searchQuery = v.toLowerCase()),
              )
            : const Text('Expense Manager'),
        actions: [
          if (_searchOpen)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _searchOpen = false;
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() => _searchOpen = true),
            ),
            IconButton(
              icon: Icon(
                privateMode
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
              ),
              onPressed: () => ref.read(privateModeProvider.notifier).toggle(),
              tooltip: privateMode ? 'Show amounts' : 'Hide amounts',
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filledTonal(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          expensesAsync.when(
            data: (allEntries) {
              if (!hasCredentials || modelName.trim().isEmpty) {
                return _EmptySetupState(
                  provider: provider,
                  modelName: modelName,
                );
              }
              if (allEntries.isEmpty) {
                return _NoExpensesState(
                  syncStatus: syncStatus,
                  provider: provider,
                  modelName: modelName,
                );
              }
              // Keep all entries (expense + income) for list display.
              // Hero card and category breakdown use expense-only subset.
              final filtered = _applySearch(allEntries);
              return _buildList(
                context,
                ref,
                allEntries,
                filtered,
                provider,
                modelName,
                privateMode,
              );
            },
            loading: () => _SkeletonLoader(),
            error: (err, _) => Center(child: Text('Error: $err')),
          ),
          // Confetti overlay
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              numberOfParticles: 40,
              gravity: 0.1,
              emissionFrequency: 0.05,
            ),
          ),
        ],
      ),
      floatingActionButton: hasCredentials && hasModel
          ? _SyncFab(
              syncStatus: syncStatus,
              onAddManual: () => _showAddExpenseSheet(context, ref),
            )
          : null,
    );
  }

  List<Expense> _applySearch(List<Expense> expenses) {
    if (_searchQuery.isEmpty) return expenses;
    return expenses
        .where(
          (e) =>
              e.merchant.toLowerCase().contains(_searchQuery) ||
              e.category.toLowerCase().contains(_searchQuery),
        )
        .toList();
  }

  Future<void> _onRefresh(WidgetRef ref) async {
    await ref.read(expenseListProvider.notifier).refreshExpenses();
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<Expense> allExpenses,
    List<Expense> filtered,
    AiProviderType provider,
    String modelName,
    bool privateMode,
  ) {
    // Day grouping
    final groups = _groupByDay(filtered);
    final now = DateTime.now();
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0, 23, 59, 59);

    final thisMonth = allExpenses.where((e) {
      return e.date.year == now.year && e.date.month == now.month;
    }).toList();

    final lastMonth = allExpenses.where((e) {
      return e.date.isAfter(lastMonthStart.subtract(const Duration(milliseconds: 1))) &&
             e.date.isBefore(lastMonthEnd.add(const Duration(milliseconds: 1)));
    }).toList();

    final thisMonthExpense = thisMonth.where((e) => !e.isIncome).fold(0.0, (s, e) => s + e.amount);
    final thisMonthIncome = thisMonth.where((e) => e.isIncome).fold(0.0, (s, e) => s + e.amount);

    final lastMonthExpense = lastMonth.where((e) => !e.isIncome).fold(0.0, (s, e) => s + e.amount);
    final currency = allExpenses.isNotEmpty
        ? allExpenses.first.currency
        : 'INR';

    // Trigger confetti if all budgets met (checked once per total change)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (thisMonthExpense != _lastMonthlyTotal) {
        _lastMonthlyTotal = thisMonthExpense;
        ref.read(budgetProgressProvider).whenData((progress) {
          if (progress.isNotEmpty &&
              progress.every(
                (b) =>
                    (b['spent'] as num).toDouble() <=
                    (b['limit_amount'] as num).toDouble(),
              )) {
            _confettiController.play();
          }
        });
      }
    });

    final streak = ref.watch(spendingStreakProvider).asData?.value ?? 0;

    // Build sliver list
    final slivers = <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        sliver: SliverToBoxAdapter(
          child: _MonthlyHeroCard(
            thisMonthExpense: thisMonthExpense,
            thisMonthIncome: thisMonthIncome,
            lastMonthExpense: lastMonthExpense,
            currency: currency,
            count: thisMonth.length,
            streak: streak,
            provider: provider,
            modelName: modelName,
            privateMode: privateMode,
            onExport: () => _doExport(context, ref, allExpenses),
          ),
        ),
      ),
      if (_searchQuery.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: SizedBox(
              height: 260,
              child: _CategoryBreakdown(
                expenses: allExpenses.where((e) => !e.isIncome).toList(),
                currency: currency,
              ),
            ),
          ),
        ),
      if (_searchQuery.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          sliver: SliverToBoxAdapter(child: _InsightsRow()),
        ),
      if (filtered.isEmpty)
        const SliverFillRemaining(child: Center(child: Text('No results.'))),
    ];

    // Day-grouped expense tiles
    for (final entry in groups.entries) {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          sliver: SliverToBoxAdapter(
            child: Text(
              _dayLabel(entry.key),
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.builder(
            itemCount: entry.value.length,
            itemBuilder: (context, i) {
              final expense = entry.value[i];
              return _SwipeableExpenseTile(
                expense: expense,
                onDelete: () => _confirmDelete(context, ref, expense),
                onTap: () => _showDetail(context, ref, expense),
                onEdit: () => _showDetail(context, ref, expense),
              );
            },
          ),
        ),
      );
    }

    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 96)));

    return RefreshIndicator(
      onRefresh: () => _onRefresh(ref),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }

  Map<DateTime, List<Expense>> _groupByDay(List<Expense> expenses) {
    final map = <DateTime, List<Expense>>{};
    for (final e in expenses) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      map.putIfAbsent(day, () => []).add(e);
    }
    final sorted = Map.fromEntries(
      map.entries.toList()..sort((a, b) => b.key.compareTo(a.key)),
    );
    return sorted;
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return DateFormat('EEEE, MMM d').format(day);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          '${expense.merchant} — ${formatAmount(expense.amount, expense.currency)} on ${DateFormat.yMMMd().format(expense.date)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && expense.id != null) {
      await ref.read(expenseListProvider.notifier).deleteExpense(expense.id!);
    }
  }

  void _showDetail(BuildContext context, WidgetRef ref, Expense expense) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExpenseFormSheet(
        initialExpense: expense,
        onSave: (updated) async {
          await ref.read(expenseListProvider.notifier).updateExpense(updated);
        },
        onDelete: () async {
          Navigator.pop(context);
          await _confirmDelete(context, ref, expense);
        },
      ),
    );
  }

  void _showAddExpenseSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExpenseFormSheet(
        onSave: (expense) async {
          await ref.read(expenseListProvider.notifier).addExpense(expense);
        },
      ),
    );
  }

  Future<void> _doExport(
    BuildContext context,
    WidgetRef ref,
    List<Expense> expenses,
  ) async {
    try {
      await ref.read(exportServiceProvider).exportCsv(expenses);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }
}

// ─── Sync FAB ─────────────────────────────────────────────────────────────

class _SyncFab extends ConsumerWidget {
  const _SyncFab({required this.syncStatus, required this.onAddManual});

  final SyncState syncStatus;
  final VoidCallback onAddManual;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = syncStatus.phase;
    final idle = phase == SyncPhase.idle;
    final label = _syncLabel(phase);
    final detail = syncStatus.detail;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Show detail line above FAB while syncing or just after completion.
        if (!idle && detail != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                detail,
                style: Theme.of(context).textTheme.labelSmall,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        FloatingActionButton.small(
          heroTag: 'add_manual',
          onPressed: onAddManual,
          tooltip: 'Add expense manually',
          child: const Icon(Icons.add),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: 'sync',
          onPressed: idle ? () => ref.read(syncProvider.notifier).sync() : null,
          label: Text(label),
          icon: idle
              ? const Icon(Icons.sync_rounded)
              : const SpinKitRotatingPlain(color: Colors.white, size: 20),
        ),
      ],
    );
  }

  String _syncLabel(SyncPhase status) {
    return switch (status) {
      SyncPhase.requestingPermissions => 'Permissions…',
      SyncPhase.fetchingSms => 'Reading SMS…',
      SyncPhase.analyzing => 'Analyzing…',
      SyncPhase.complete => 'Done',
      SyncPhase.error => 'Retry sync',
      SyncPhase.idle => 'Sync SMS',
    };
  }
}

// ─── Monthly hero card ────────────────────────────────────────────────────

class _MonthlyHeroCard extends StatelessWidget {
  const _MonthlyHeroCard({
    required this.thisMonthExpense,
    required this.thisMonthIncome,
    required this.lastMonthExpense,
    required this.currency,
    required this.count,
    required this.streak,
    required this.provider,
    required this.modelName,
    required this.onExport,
    required this.privateMode,
  });

  final double thisMonthExpense;
  final double thisMonthIncome;
  final double lastMonthExpense;
  final String currency;
  final int count;
  final int streak;
  final AiProviderType provider;
  final String modelName;
  final VoidCallback onExport;
  final bool privateMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final delta = lastMonthExpense > 0
        ? ((thisMonthExpense - lastMonthExpense) / lastMonthExpense * 100)
        : null;
    final deltaUp = delta != null && delta > 0;
    final displayModel = provider == AiProviderType.flutterGemma
        ? modelName.split('/').last
        : modelName;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          colors: [scheme.primaryContainer, scheme.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _HeroChip(
                      icon: Icons.hub_outlined,
                      label: provider.displayName,
                    ),
                    _HeroChip(
                      icon: Icons.auto_awesome_rounded,
                      label: displayModel,
                    ),
                    _HeroChip(
                      icon: Icons.receipt_long_outlined,
                      label: '$count this month',
                    ),
                    if (streak > 0)
                      _HeroChip(
                        icon: Icons.local_fire_department_rounded,
                        label: '$streak day streak',
                      ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Export CSV',
                onPressed: onExport,
                icon: const Icon(Icons.download_outlined),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            DateFormat('MMMM yyyy').format(DateTime.now()),
            style: theme.textTheme.titleMedium?.copyWith(
              color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spent',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        privateMode
                            ? maskAmount(currency)
                            : formatAmount(thisMonthExpense, currency),
                        key: ValueKey(privateMode
                            ? 'private_exp'
                            : thisMonthExpense.toStringAsFixed(0)),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: scheme.onPrimaryContainer,
                        ),
                      ).animate(key: ValueKey(thisMonthExpense)).shimmer(
                            duration: 800.ms,
                            color: scheme.onPrimaryContainer.withValues(alpha: 0.3),
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: scheme.onPrimaryContainer.withValues(alpha: 0.1),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Income',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 600),
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: Text(
                        privateMode
                            ? maskAmount(currency)
                            : formatAmount(thisMonthIncome, currency),
                        key: ValueKey(privateMode
                            ? 'private_inc'
                            : thisMonthIncome.toStringAsFixed(0)),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: Colors.green.shade700,
                        ),
                      ).animate(key: ValueKey(thisMonthIncome)).shimmer(
                            duration: 800.ms,
                            color: Colors.green.withValues(alpha: 0.3),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (delta != null)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: (deltaUp ? Colors.red : Colors.green).withValues(
                      alpha: 0.18,
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        deltaUp
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 14,
                        color: deltaUp ? Colors.red : Colors.green,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${delta.abs().toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: deltaUp ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!privateMode)
                  Text(
                    'vs ${formatAmount(lastMonthExpense, currency)} last month',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Category breakdown (donut) ───────────────────────────────────────────

class _CategoryBreakdown extends StatefulWidget {
  const _CategoryBreakdown({required this.expenses, this.currency = 'INR'});

  final List<Expense> expenses;
  final String currency;

  @override
  State<_CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<_CategoryBreakdown> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryTotals = <String, double>{};
    for (final e in widget.expenses) {
      categoryTotals.update(
        e.category,
        (v) => v + e.amount,
        ifAbsent: () => e.amount,
      );
    }
    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sections = sorted.asMap().entries.map((entry) {
      final i = entry.key;
      final cat = entry.value;
      final isTouched = _touched == i;
      return PieChartSectionData(
        value: cat.value,
        title: isTouched ? formatAmount(cat.value, widget.currency) : '',
        color: categoryColor(cat.key),
        radius: isTouched ? 68 : 56,
        titleStyle: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      );
    }).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Category breakdown',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: PieChart(
                      PieChartData(
                        sections: sections,
                        centerSpaceRadius: 38,
                        sectionsSpace: 3,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            if (!event.isInterestedForInteractions ||
                                response == null ||
                                response.touchedSection == null) {
                              setState(() => _touched = null);
                              return;
                            }
                            setState(
                              () => _touched =
                                  response.touchedSection!.touchedSectionIndex,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: sorted
                          .map(
                            (entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: categoryColor(entry.key),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Swipeable expense tile ────────────────────────────────────────────────

class _SwipeableExpenseTile extends StatelessWidget {
  const _SwipeableExpenseTile({
    required this.expense,
    required this.onDelete,
    required this.onTap,
    required this.onEdit,
  });

  final Expense expense;
  final VoidCallback onDelete;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Dismissible(
      key: ValueKey(expense.id ?? expense.originalSms),
      direction: DismissDirection.horizontal,
      // Left-swipe (end-to-start) = delete
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      // Right-swipe (start-to-end) = edit
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(Icons.edit_outlined, color: scheme.onPrimaryContainer),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.mediumImpact();
          onEdit();
          return false;
        }
        HapticFeedback.heavyImpact();
        onDelete();
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _ExpenseTile(expense: expense, onTap: onTap),
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({required this.expense, required this.onTap});

  final Expense expense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = categoryColor(expense.category);
    final privateMode = ref.watch(privateModeProvider);
    final isIncome = expense.isIncome;
    final amountColor = isIncome ? Colors.green.shade700 : scheme.onSurface;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.16),
                child: Icon(
                  isIncome ? Icons.account_balance_wallet_rounded : categoryIcon(expense.category),
                  color: color,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MerchantProfileScreen(
                            merchant: expense.displayMerchant,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              expense.displayMerchant,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (expense.isRecurring) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Recurring',
                              child: Icon(
                                Icons.repeat_rounded,
                                size: 14,
                                color: scheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _MetaPill(
                          label: isIncome ? 'Income' : expense.category,
                          icon: isIncome ? Icons.add_circle_outline_rounded : Icons.sell_outlined,
                        ),
                        const SizedBox(width: 6),
                        _MetaPill(
                          label: DateFormat('MMM d').format(expense.date),
                          icon: Icons.event_outlined,
                        ),
                        if (expense.tagList.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          _MetaPill(
                            label: expense.tagList.first,
                            icon: Icons.local_offer_outlined,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                privateMode
                    ? maskAmount(expense.currency)
                    : '${isIncome ? '+' : ''}${formatAmount(expense.amount, expense.currency)}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─── Empty states ─────────────────────────────────────────────────────────

class _EmptySetupState extends StatelessWidget {
  const _EmptySetupState({required this.provider, required this.modelName});

  final AiProviderType provider;
  final String modelName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOnDevice =
        provider == AiProviderType.offline ||
        provider == AiProviderType.flutterGemma;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    isOnDevice ? Icons.memory_outlined : Icons.key_off_outlined,
                    size: 34,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  isOnDevice
                      ? 'No model selected'
                      : '${provider.displayName} API key missing',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  provider == AiProviderType.offline
                      ? 'Select a `.litertlm` model in settings.'
                      : provider == AiProviderType.flutterGemma
                      ? 'Select a model from AI Edge Gallery in settings.'
                      : 'Add ${provider.displayName} API key in settings.',
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoExpensesState extends StatelessWidget {
  const _NoExpensesState({
    required this.syncStatus,
    required this.provider,
    required this.modelName,
  });

  final SyncState syncStatus;
  final AiProviderType provider;
  final String modelName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final phase = syncStatus.phase;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            gradient: LinearGradient(
              colors: [scheme.secondaryContainer, scheme.primaryContainer],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forum_outlined,
                size: 48,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(height: 16),
              Text(
                'No expenses yet',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Run SMS sync to populate your dashboard.\nProvider: ${provider.displayName}.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Status: ${phase.name}',
                style: theme.textTheme.labelLarge,
              ),
              if (syncStatus.detail != null) ...[
                const SizedBox(height: 4),
                Text(
                  syncStatus.detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSecondaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Skeleton loader ──────────────────────────────────────────────────────

class _SkeletonLoader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest.withValues(alpha: 0.4);

    Widget bone(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(12),
      ),
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Hero card skeleton
        Container(
          height: 160,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(32),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          height: 240,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(28),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(
          4,
          (_) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                CircleAvatar(radius: 24, backgroundColor: base),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      bone(160, 16),
                      const SizedBox(height: 8),
                      bone(100, 12),
                    ],
                  ),
                ),
                bone(70, 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Meta pill ────────────────────────────────────────────────────────────

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.primary),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

// ─── Insights row ─────────────────────────────────────────────────────────

class _InsightsRow extends ConsumerWidget {
  const _InsightsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(spendingInsightsProvider);
    final anomalyAsync = ref.watch(anomalyAlertsProvider);

    final allInsights = [
      ...insightsAsync.asData?.value ?? [],
      ...anomalyAsync.asData?.value ?? [],
    ];

    if (allInsights.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Insights',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: allInsights.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final insight = allInsights[i];
              return Container(
                width: 200,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: insight.isWarning
                      ? scheme.errorContainer.withValues(alpha: 0.45)
                      : scheme.secondaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      insight.icon,
                      size: 18,
                      color: insight.isWarning
                          ? scheme.error
                          : scheme.secondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            insight.title,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            insight.body,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
