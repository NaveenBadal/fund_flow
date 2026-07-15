import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';
import 'merchant_profile_screen.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(analyticsPeriodProvider);
    final monthly = ref.watch(monthlyTotalsProvider);
    final categories = ref.watch(categoryTotalsForPeriodProvider);
    final merchants = ref.watch(topMerchantsForPeriodProvider);
    final currency = ref.watch(preferredCurrencyProvider);
    final hidden = ref.watch(privateModeProvider);
    return CommandScaffold(
      eyebrow: 'Your velocity through time',
      title: 'Trajectory',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<int>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 3, label: Text('3M')),
                ButtonSegment(value: 6, label: Text('6M')),
                ButtonSegment(value: 12, label: Text('1Y')),
              ],
              selected: {period},
              onSelectionChanged: (value) => ref
                  .read(analyticsPeriodProvider.notifier)
                  .setPeriod(value.first),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionLabel('Temporal movement')),
        monthly.when(
          loading: () => const SliverToBoxAdapter(
            child: SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (error, _) => SliverToBoxAdapter(
            child: StatePanel(
              icon: Icons.show_chart_rounded,
              title: 'Trend unavailable',
              message: '$error',
            ),
          ),
          data: (rows) => SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _Timeline(rows: rows, currency: currency, hidden: hidden),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionLabel('Gravity wells')),
        categories.when(
          loading: () => const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverToBoxAdapter(child: Text('$error')),
          data: (data) {
            final rows = data.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            final total = rows.fold<double>(0, (sum, row) => sum + row.value);
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final row = rows[index];
                  final color = categoryColor(row.key);
                  return Column(
                    children: [
                      Row(
                        children: [
                          Icon(categoryIcon(row.key), size: 18, color: color),
                          const SizedBox(width: 9),
                          Expanded(
                            child: Text(
                              row.key,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            hidden
                                ? maskAmount(currency)
                                : formatAmount(row.value, currency),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: AppRadius.all(99),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : row.value / total,
                          minHeight: 7,
                          color: color,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SectionLabel('Repeated attraction')),
        merchants.when(
          loading: () => const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverToBoxAdapter(child: Text('$error')),
          data: (items) => SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList.separated(
              itemCount: items.take(8).length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: .4),
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                final name = item['merchant'] as String? ?? 'Unknown';
                final total = (item['total'] as num?)?.toDouble() ?? 0;
                final count = item['txn_count'] as int? ?? 0;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 5),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    child: Text(name.characters.first.toUpperCase()),
                  ),
                  title: Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('$count movements'),
                  trailing: Text(
                    hidden
                        ? maskAmount(currency)
                        : formatAmount(total, currency),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MerchantProfileScreen(merchant: name),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.rows,
    required this.currency,
    required this.hidden,
  });
  final List<Map<String, dynamic>> rows;
  final String currency;
  final bool hidden;
  @override
  Widget build(BuildContext context) {
    final maximum = rows.fold<double>(
      1,
      (value, row) => max(
        value,
        max(
          (row['total_expense'] as num?)?.toDouble() ?? 0,
          (row['total_income'] as num?)?.toDouble() ?? 0,
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: AppRadius.all(AppRadius.xxl),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 180,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final row in rows)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 7,
                                  height:
                                      140 *
                                      (((row['total_income'] as num?)
                                                  ?.toDouble() ??
                                              0) /
                                          maximum),
                                  decoration: BoxDecoration(
                                    color: context.finance.income,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Container(
                                  width: 7,
                                  height:
                                      140 *
                                      (((row['total_expense'] as num?)
                                                  ?.toDouble() ??
                                              0) /
                                          maximum),
                                  decoration: BoxDecoration(
                                    color: context.finance.expense,
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            DateFormat('MMM').format(
                              DateTime(
                                row['year'] as int? ?? DateTime.now().year,
                                row['month'] as int? ?? 1,
                              ),
                            ),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface
                                      .withValues(alpha: .65),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _Legend(color: context.finance.income, label: 'Income'),
              const SizedBox(width: 16),
              _Legend(color: context.finance.expense, label: 'Spent'),
              const Spacer(),
              Text(
                hidden
                    ? 'Peak ${maskAmount(currency)}'
                    : 'Peak ${formatAmount(maximum, currency)}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onInverseSurface.withValues(alpha: .65),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onInverseSurface,
        ),
      ),
    ],
  );
}
