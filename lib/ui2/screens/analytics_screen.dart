import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/money_format.dart';
import '../../domain/transaction.dart';
import '../charts/flow_charts.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';
import '../tokens/flow_type.dart';
import 'today_screen.dart';

/// Deep spending analytics, merchant leaderboards, and subscription intelligence.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final flow = context.flow;
    final hidden = app.preferences.hideAmounts;
    final analytics = AnalyticsSummary.of(app.transactions, DateTime.now());

    if (analytics == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.analytics_outlined, size: 36, color: flow.accent),
              const SizedBox(height: FlowSpace.md),
              Text(
                'No analytics data yet',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: FlowSpace.sm),
              Text(
                'Sync your messages to see spending insights, top merchants, and recurring bills.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: flow.inkSoft),
              ),
            ],
          ),
        ),
      );
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FlowSpace.xl,
              FlowSpace.lg,
              FlowSpace.xl,
              FlowSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Analytics',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Monthly breakdown & spending intelligence',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Cashflow Summary Card
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FlowSpace.xl,
              FlowSpace.md,
              FlowSpace.xl,
              0,
            ),
            child: Container(
              padding: const EdgeInsets.all(FlowSpace.xl),
              decoration: BoxDecoration(
                color: flow.raised,
                borderRadius: FlowRadius.xl,
                border: Border.all(color: flow.accent.withValues(alpha: 0.15)),
                boxShadow: FlowElevation.card(Theme.of(context).brightness),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MONTHLY CASHFLOW',
                    style: FlowType.eyebrow.copyWith(color: flow.inkFaint),
                  ),
                  const SizedBox(height: FlowSpace.md),
                  Row(
                    children: [
                      Expanded(
                        child: _CashflowMetric(
                          label: 'Income',
                          amountMinor: analytics.totalIncomeMinor,
                          currency: analytics.currency,
                          color: flow.income,
                          hidden: hidden,
                          icon: Icons.south_west_rounded,
                        ),
                      ),
                      Container(width: 1, height: 40, color: flow.line),
                      Expanded(
                        child: _CashflowMetric(
                          label: 'Expenses',
                          amountMinor: analytics.totalExpenseMinor,
                          currency: analytics.currency,
                          color: flow.expense,
                          hidden: hidden,
                          icon: Icons.north_east_rounded,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Top Merchants Section
        if (analytics.topMerchants.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                FlowSpace.xl,
                FlowSpace.xl,
                FlowSpace.xl,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOP SPENDING DESTINATIONS',
                    style: FlowType.eyebrow.copyWith(color: flow.inkFaint),
                  ),
                  const SizedBox(height: FlowSpace.md),
                  for (final merchant in analytics.topMerchants)
                    _MerchantRow(
                      merchant: merchant,
                      totalExpense: analytics.totalExpenseMinor,
                      currency: analytics.currency,
                      hidden: hidden,
                    ),
                ],
              ),
            ),
          ),

        // Category Breakdown Section
        if (analytics.categories.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                FlowSpace.xl,
                FlowSpace.xl,
                FlowSpace.xl,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CATEGORY BREAKDOWN',
                    style: FlowType.eyebrow.copyWith(color: flow.inkFaint),
                  ),
                  const SizedBox(height: FlowSpace.md),
                  if (!hidden && analytics.categories.length >= 2)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: FlowSpace.lg),
                        child: FlowDonut(
                          size: 148,
                          centerLabel: 'Spent',
                          centerValue: formatMoney(
                            analytics.totalExpenseMinor,
                            analytics.currency,
                          ),
                          segments: [
                            for (var i = 0; i < analytics.categories.length; i++)
                              FlowDonutSegment(
                                value: analytics.categories[i].amountMinor.toDouble(),
                                color: flow.seriesAt(i),
                              ),
                          ],
                        ),
                      ),
                    ),
                  for (var i = 0; i < analytics.categories.length; i++)
                    FlowBarRow(
                      label: analytics.categories[i].label,
                      swatch: !hidden && analytics.categories.length >= 2,
                      amount: hidden
                          ? '••••'
                          : formatMoney(
                              analytics.categories[i].amountMinor,
                              analytics.currency,
                            ),
                      fraction: analytics.categories[i].amountMinor /
                          analytics.categories.first.amountMinor,
                      share: analytics.totalExpenseMinor == 0
                          ? null
                          : analytics.categories[i].amountMinor / analytics.totalExpenseMinor,
                      color: flow.seriesAt(i),
                    ),
                ],
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: FlowSpace.xxl)),
      ],
    );
  }
}

class _CashflowMetric extends StatelessWidget {
  const _CashflowMetric({
    required this.label,
    required this.amountMinor,
    required this.currency,
    required this.color,
    required this.hidden,
    required this.icon,
  });

  final String label;
  final int amountMinor;
  final String currency;
  final Color color;
  final bool hidden;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.flow.inkSoft,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hidden ? '••••••' : formatMoney(amountMinor, currency),
            style: FlowType.amountLarge.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _MerchantRow extends StatelessWidget {
  const _MerchantRow({
    required this.merchant,
    required this.totalExpense,
    required this.currency,
    required this.hidden,
  });

  final MerchantTotal merchant;
  final int totalExpense;
  final String currency;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final share = totalExpense == 0 ? 0.0 : (merchant.amountMinor / totalExpense).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: FlowSpace.md),
      child: Container(
        padding: const EdgeInsets.all(FlowSpace.md),
        decoration: BoxDecoration(
          color: flow.raised,
          borderRadius: FlowRadius.md,
          border: Border.all(color: flow.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    merchant.name,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  hidden ? '••••' : formatMoney(merchant.amountMinor, currency),
                  style: FlowType.amountRow.copyWith(color: flow.ink),
                ),
              ],
            ),
            const SizedBox(height: FlowSpace.xs),
            ClipRRect(
              borderRadius: FlowRadius.pill,
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
                backgroundColor: flow.sunken,
                color: flow.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MerchantTotal {
  const MerchantTotal({required this.name, required this.amountMinor});
  final String name;
  final int amountMinor;
}

class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totalIncomeMinor,
    required this.totalExpenseMinor,
    required this.currency,
    required this.topMerchants,
    required this.categories,
  });

  final int totalIncomeMinor;
  final int totalExpenseMinor;
  final String currency;
  final List<MerchantTotal> topMerchants;
  final List<CategoryTotal> categories;

  static AnalyticsSummary? of(List<MoneyTransaction> transactions, DateTime now) {
    if (transactions.isEmpty) return null;

    final monthStart = DateTime(now.year, now.month);
    final monthItems = transactions.where((item) => !item.occurredAt.isBefore(monthStart));
    if (monthItems.isEmpty) return null;

    final counts = <String, int>{};
    for (final item in monthItems) {
      counts[item.currency] = (counts[item.currency] ?? 0) + 1;
    }
    final currency = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

    var income = 0;
    var expense = 0;
    final merchantMap = <String, int>{};
    final categoryMap = <String, int>{};

    for (final item in monthItems.where((e) => e.currency == currency)) {
      if (item.direction == TransactionDirection.incoming) {
        income += item.amountMinor;
      } else {
        expense += item.amountMinor;
        merchantMap[item.merchant] = (merchantMap[item.merchant] ?? 0) + item.amountMinor;
        categoryMap[item.category] = (categoryMap[item.category] ?? 0) + item.amountMinor;
      }
    }

    final topMerchants = merchantMap.entries
        .map((e) => MerchantTotal(name: e.key, amountMinor: e.value))
        .toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    final categories = categoryMap.entries
        .map((e) => CategoryTotal(label: e.key, amountMinor: e.value))
        .toList()
      ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    return AnalyticsSummary(
      totalIncomeMinor: income,
      totalExpenseMinor: expense,
      currency: currency,
      topMerchants: topMerchants.take(5).toList(),
      categories: categories.take(5).toList(),
    );
  }
}
