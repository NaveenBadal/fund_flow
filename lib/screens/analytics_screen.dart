import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import 'financial_health_screen.dart';
import 'heatmap_screen.dart';
import 'merchant_profile_screen.dart';

// ─── Main screen ──────────────────────────────────────────────────────────────

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(analyticsPeriodProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: CustomScrollView(
      slivers: [
        // Period selector
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: _PeriodSelector(selectedPeriod: period),
          ),
        ),

        // Income vs Expense balance card
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: const SliverToBoxAdapter(child: _BalanceCard()),
        ),

        // Month-over-month delta chip
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
          sliver: SliverToBoxAdapter(child: _DeltaChip()),
        ),

        // Anomaly callout (only if anomalies found)
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
          sliver: SliverToBoxAdapter(child: _AnomalyCalloutCard()),
        ),

        // Monthly spending bar chart
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: const SliverToBoxAdapter(child: _MonthlyBarChart()),
        ),

        // Category breakdown pie chart
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: const SliverToBoxAdapter(child: _CategoryPieChart()),
        ),

        // Top merchants list
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: const SliverToBoxAdapter(child: _TopMerchantsList()),
        ),

        // Quick links
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: _QuickLinkCard(
                    icon: Icons.calendar_month_rounded,
                    label: 'Spending Heatmap',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HeatmapScreen())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickLinkCard(
                    icon: Icons.favorite_rounded,
                    label: 'Financial Health',
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialHealthScreen())),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 88)),
      ],
    ), // CustomScrollView
    ); // Scaffold
  }
}

// ─── Period selector ──────────────────────────────────────────────────────────

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector({required this.selectedPeriod});

  final int selectedPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const periods = [1, 3, 6, 12];
    const labels = {1: '1M', 3: '3M', 6: '6M', 12: '12M'};

    return SegmentedButton<int>(
      segments: periods
          .map(
            (p) => ButtonSegment<int>(
              value: p,
              label: Text(labels[p]!),
            ),
          )
          .toList(),
      selected: {selectedPeriod},
      onSelectionChanged: (selection) {
        ref.read(analyticsPeriodProvider.notifier).setPeriod(selection.first);
      },
      style: SegmentedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

// ─── Balance card ─────────────────────────────────────────────────────────────

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(currentMonthBalanceProvider);
    final privateMode = ref.watch(privateModeProvider);
    final currency = ref.watch(expenseListProvider).asData?.value
            .firstOrNull?.currency ??
        'INR';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This month',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            balanceAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => _ErrorRetry(
                message: 'Failed to load balance',
                onRetry: () => ref.invalidate(currentMonthBalanceProvider),
              ),
              data: (balance) {
                final income = balance['income'] ?? 0.0;
                final expense = balance['expense'] ?? 0.0;
                return Row(
                  children: [
                    Expanded(
                      child: _BalanceTile(
                        label: 'Income',
                        amount: income,
                        currency: currency,
                        privateMode: privateMode,
                        icon: Icons.arrow_downward_rounded,
                        color: Colors.green.shade600,
                        containerColor: Colors.green.shade50,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _BalanceTile(
                        label: 'Expenses',
                        amount: expense,
                        currency: currency,
                        privateMode: privateMode,
                        icon: Icons.arrow_upward_rounded,
                        color: scheme.error,
                        containerColor: scheme.errorContainer,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Month-over-month delta chip ──────────────────────────────────────────────

class _DeltaChip extends ConsumerWidget {
  const _DeltaChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsync = ref.watch(currentMonthBalanceProvider);
    final prevAsync = ref.watch(previousMonthBalanceProvider);
    final privateMode = ref.watch(privateModeProvider);

    final current = (currentAsync.asData?.value['expense'] as num?)?.toDouble() ?? 0.0;
    final prev = (prevAsync.asData?.value['expense'] as num?)?.toDouble() ?? 0.0;

    if (prev <= 0 || privateMode) return const SizedBox.shrink();

    final delta = (current - prev) / prev * 100;
    final up = delta > 0;
    final color = up ? Colors.red : Colors.green;
    final icon = up ? Icons.trending_up_rounded : Icons.trending_down_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '${delta.abs().toStringAsFixed(1)}% vs last month',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Anomaly callout ──────────────────────────────────────────────────────────

class _AnomalyCalloutCard extends ConsumerWidget {
  const _AnomalyCalloutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anomaliesAsync = ref.watch(anomalyAlertsProvider);
    final anomalies = anomaliesAsync.asData?.value ?? [];
    if (anomalies.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.errorContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: scheme.error, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${anomalies.length} Anomal${anomalies.length == 1 ? 'y' : 'ies'} Detected',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...anomalies.take(3).map((a) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '• ${a.body}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onErrorContainer.withValues(alpha: 0.85),
                ),
              ),
            )),
            if (anomalies.length > 3)
              Text(
                '+${anomalies.length - 3} more…',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onErrorContainer.withValues(alpha: 0.6),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({
    required this.label,
    required this.amount,
    required this.currency,
    required this.privateMode,
    required this.icon,
    required this.color,
    required this.containerColor,
  });

  final String label;
  final double amount;
  final String currency;
  final bool privateMode;
  final IconData icon;
  final Color color;
  final Color containerColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: containerColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            privateMode ? maskAmount(currency) : formatAmount(amount, currency),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─── Monthly bar chart ────────────────────────────────────────────────────────

class _MonthlyBarChart extends ConsumerWidget {
  const _MonthlyBarChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthlyAsync = ref.watch(monthlyTotalsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Monthly overview',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _LegendDot(color: scheme.primary, label: 'Expense'),
                const SizedBox(width: 16),
                _LegendDot(color: scheme.tertiary, label: 'Income'),
              ],
            ),
            const SizedBox(height: 16),
            monthlyAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SizedBox(
                height: 200,
                child: _ErrorRetry(
                  message: 'Failed to load monthly data',
                  onRetry: () => ref.invalidate(monthlyTotalsProvider),
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: Text('No data for this period')),
                  );
                }

                // Rows are newest-first; reverse so chart is oldest → newest
                final sorted = rows.reversed.toList();

                double maxY = 0;
                for (final r in sorted) {
                  final e = (r['total_expense'] as num?)?.toDouble() ?? 0.0;
                  final i = (r['total_income'] as num?)?.toDouble() ?? 0.0;
                  if (e > maxY) maxY = e;
                  if (i > maxY) maxY = i;
                }
                // Add 20 % headroom, ensure sensible minimum
                maxY = maxY * 1.2;
                if (maxY < 100) maxY = 100;

                final barGroups = sorted.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;
                  final expense =
                      (r['total_expense'] as num?)?.toDouble() ?? 0.0;
                  final income =
                      (r['total_income'] as num?)?.toDouble() ?? 0.0;
                  return BarChartGroupData(
                    x: idx,
                    groupVertically: false,
                    barRods: [
                      BarChartRodData(
                        toY: expense,
                        color: scheme.primary,
                        width: 10,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                      BarChartRodData(
                        toY: income,
                        color: scheme.tertiary,
                        width: 10,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                    barsSpace: 4,
                  );
                }).toList();

                return SizedBox(
                  height: 220,
                  child: BarChart(
                    BarChartData(
                      maxY: maxY,
                      barGroups: barGroups,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: scheme.outlineVariant.withValues(alpha: 0.4),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 52,
                            getTitlesWidget: (value, meta) {
                              if (value == meta.max || value == 0) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                _compactAmount(value),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              );
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= sorted.length) {
                                return const SizedBox.shrink();
                              }
                              final r = sorted[idx];
                              final month = r['month'] as int? ?? 1;
                              final label = DateFormat('MMM')
                                  .format(DateTime(2000, month));
                              return SideTitleWidget(
                                meta: meta,
                                child: Text(
                                  label,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (_) => scheme.surfaceContainerHighest,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final r = sorted[groupIndex];
                            final month = r['month'] as int? ?? 1;
                            final year = r['year'] as int? ?? 0;
                            final label = DateFormat('MMM yyyy')
                                .format(DateTime(year, month));
                            final typeLabel =
                                rodIndex == 0 ? 'Expense' : 'Income';
                            return BarTooltipItem(
                              '$label\n$typeLabel: ${formatAmount(rod.toY, 'INR')}',
                              theme.textTheme.labelSmall!.copyWith(
                                color: scheme.onSurface,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _compactAmount(double value) {
    const sym = '₹'; // y-axis labels are always compact; full symbol is fine
    if (value >= 100000) return '$sym${(value / 100000).toStringAsFixed(1)}L';
    if (value >= 1000) return '$sym${(value / 1000).toStringAsFixed(0)}K';
    return '$sym${value.toStringAsFixed(0)}';
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ],
    );
  }
}

// ─── Category pie chart ───────────────────────────────────────────────────────

class _CategoryPieChart extends ConsumerWidget {
  const _CategoryPieChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoryAsync = ref.watch(categoryTotalsForPeriodProvider);
    final theme = Theme.of(context);

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
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            categoryAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SizedBox(
                height: 200,
                child: _ErrorRetry(
                  message: 'Failed to load categories',
                  onRetry: () =>
                      ref.invalidate(categoryTotalsForPeriodProvider),
                ),
              ),
              data: (totals) {
                if (totals.isEmpty) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: Text('No category data')),
                  );
                }

                final entries = totals.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));

                final sections = entries.map((entry) {
                  final color = categoryColor(entry.key);
                  return PieChartSectionData(
                    value: entry.value,
                    title: '',
                    color: color,
                    radius: 60,
                  );
                }).toList();

                return SizedBox(
                  height: 240,
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: PieChart(
                          PieChartData(
                            sections: sections,
                            centerSpaceRadius: 44,
                            sectionsSpace: 3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: entries.map((entry) {
                            final color = categoryColor(entry.key);
                            final icon = categoryIcon(entry.key);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor:
                                        color.withValues(alpha: 0.15),
                                    child: Icon(icon,
                                        size: 14, color: color),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.key,
                                          style: theme.textTheme.labelMedium,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          formatAmount(entry.value, 'INR'),
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Top merchants list ───────────────────────────────────────────────────────

class _TopMerchantsList extends ConsumerWidget {
  const _TopMerchantsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantsAsync = ref.watch(topMerchantsForPeriodProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top merchants',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            merchantsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => _ErrorRetry(
                message: 'Failed to load merchants',
                onRetry: () => ref.invalidate(topMerchantsForPeriodProvider),
              ),
              data: (merchants) {
                if (merchants.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('No merchant data')),
                  );
                }

                return Column(
                  children: merchants.asMap().entries.map((entry) {
                    final rank = entry.key + 1;
                    final m = entry.value;
                    final name = m['merchant'] as String? ?? '—';
                    final total = (m['total'] as num?)?.toDouble() ?? 0.0;
                    final count = m['txn_count'] as int? ?? 0;

                    final isFirst = rank == 1;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MerchantProfileScreen(merchant: name),
                          ),
                        ),
                        child: Container(
                        decoration: BoxDecoration(
                          color: isFirst
                              ? scheme.primaryContainer.withValues(alpha: 0.4)
                              : scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundColor: isFirst
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                            child: Text(
                              '#$rank',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isFirst
                                    ? scheme.onPrimary
                                    : scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$count transaction${count == 1 ? '' : 's'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: Text(
                            formatAmount(total, 'INR'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        ), // Container
                      ), // GestureDetector
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick link card ──────────────────────────────────────────────────────────

class _QuickLinkCard extends StatelessWidget {
  const _QuickLinkCard({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.secondaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: scheme.secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 14, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Shared error widget ──────────────────────────────────────────────────────

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 36, color: scheme.error),
          const SizedBox(height: 10),
          Text(
            message,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
