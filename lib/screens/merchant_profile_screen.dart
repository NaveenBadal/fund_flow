import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import '../models/expense.dart';
import '../services/database_helper.dart';
import '../utils/category_utils.dart';

class MerchantProfileScreen extends ConsumerWidget {
  const MerchantProfileScreen({super.key, required this.merchant});

  final String merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(merchantStatsProvider(merchant));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Scaffold(
      appBar: AppBar(
        title: Text(merchant),
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stats) {
          return FutureBuilder<List<Expense>>(
            future: DatabaseHelper.instance.getExpensesByMerchant(merchant),
            builder: (context, snapshot) {
              final expenses = snapshot.data ?? [];
              return CustomScrollView(
                slivers: [
                  // Hero stats card
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Container(
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
                                CircleAvatar(
                                  radius: 28,
                                  backgroundColor: scheme.primary.withValues(alpha: 0.15),
                                  child: Text(
                                    merchant.isNotEmpty ? merchant[0].toUpperCase() : '?',
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: scheme.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        merchant,
                                        style: theme.textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: scheme.onPrimaryContainer),
                                      ),
                                      if (stats.firstTransactionDate != null)
                                        Text(
                                          'First seen: ${DateFormat('MMM d, yyyy').format(stats.firstTransactionDate!)}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                              color: scheme.onPrimaryContainer.withValues(alpha: 0.7)),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: _StatTile(
                                    label: 'Lifetime total',
                                    value: fmt.format(stats.lifetimeTotal),
                                    icon: Icons.payments_rounded,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Transactions',
                                    value: '${stats.transactionCount}',
                                    icon: Icons.receipt_long_rounded,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _StatTile(
                                    label: 'Avg spend',
                                    value: fmt.format(stats.averageAmount),
                                    icon: Icons.trending_flat_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 6-month bar chart
                  if (stats.monthlyTotals.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(
                        child: Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Monthly trend',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 160,
                                  child: _MerchantBarChart(
                                    totals: stats.monthlyTotals,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Transaction history
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    sliver: SliverToBoxAdapter(
                      child: Text(
                        'Transaction history',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),

                  if (expenses.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Text('No transactions found',
                              style: theme.textTheme.bodyLarge),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverList.builder(
                        itemCount: expenses.length,
                        itemBuilder: (context, i) {
                          final e = expenses[i];
                          final color = categoryColor(e.category);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: color.withValues(alpha: 0.16),
                                      child: Icon(categoryIcon(e.category), size: 18, color: color),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            DateFormat('MMM d, yyyy').format(e.date),
                                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                          ),
                                          Text(
                                            e.category,
                                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      fmt.format(e.amount),
                                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 88)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(height: 6),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MerchantBarChart extends StatelessWidget {
  const _MerchantBarChart({required this.totals});

  final List totals;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    if (totals.isEmpty) return const SizedBox.shrink();

    double maxY = 0;
    for (final t in totals) {
      if (t.total > maxY) maxY = t.total;
    }
    maxY = maxY * 1.2;
    if (maxY < 100) maxY = 100;

    final barGroups = totals.asMap().entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value.total,
            color: scheme.primary,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        maxY: maxY,
        barGroups: barGroups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= totals.length) return const SizedBox.shrink();
                final t = totals[idx];
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    DateFormat('MMM').format(DateTime(t.year, t.month)),
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
