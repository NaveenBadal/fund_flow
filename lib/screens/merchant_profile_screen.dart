import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/database_helper.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';

class MerchantProfileScreen extends ConsumerWidget {
  const MerchantProfileScreen({super.key, required this.merchant});
  final String merchant;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(merchantStatsProvider(merchant));
    final hidden = ref.watch(privateModeProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(title: Text(merchant)),
          async.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: StatePanel(
                icon: Icons.storefront_outlined,
                title: 'Merchant unavailable',
                message: '$error',
              ),
            ),
            data: (stats) => SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.inverseSurface,
                        borderRadius: AppRadius.all(AppRadius.xxl),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: AppRadius.all(18),
                                ),
                                child: Center(
                                  child: Text(
                                    merchant.characters.first.toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onPrimary,
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      merchant,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onInverseSurface,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    if (stats.firstTransactionDate != null)
                                      Text(
                                        'In your ledger since ${DateFormat('MMMM yyyy').format(stats.firstTransactionDate!)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onInverseSurface
                                                  .withValues(alpha: .62),
                                            ),
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
                                child: _Datum(
                                  label: 'Lifetime',
                                  value: hidden
                                      ? maskAmount('INR')
                                      : formatAmount(
                                          stats.lifetimeTotal,
                                          'INR',
                                        ),
                                ),
                              ),
                              Expanded(
                                child: _Datum(
                                  label: 'Average',
                                  value: hidden
                                      ? maskAmount('INR')
                                      : formatAmount(
                                          stats.averageAmount,
                                          'INR',
                                        ),
                                ),
                              ),
                              Expanded(
                                child: _Datum(
                                  label: 'Visits',
                                  value: '${stats.transactionCount}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SectionLabel('Six-month rhythm'),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      height: 130,
                      child: _MiniBars(
                        values: stats.monthlyTotals
                            .map((e) => e.total)
                            .toList(),
                        labels: stats.monthlyTotals
                            .map(
                              (e) => DateFormat(
                                'MMM',
                              ).format(DateTime(e.year, e.month)),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SectionLabel('Movement history'),
                ),
                SliverToBoxAdapter(
                  child: FutureBuilder<List<Expense>>(
                    future: DatabaseHelper.instance.getExpensesByMerchant(
                      merchant,
                    ),
                    builder: (context, snapshot) {
                      final items = snapshot.data ?? const [];
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                        child: Column(
                          children: [
                            for (final e in items)
                              _Movement(expense: e, hidden: hidden),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Datum extends StatelessWidget {
  const _Datum({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(
            context,
          ).colorScheme.onInverseSurface.withValues(alpha: .55),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.fade,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onInverseSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    ],
  );
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values, required this.labels});
  final List<double> values;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    final max = values.fold<double>(1, (a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < values.length; i++)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 18,
                      height: 90 * values[i] / max,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Text(labels[i], style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _Movement extends StatelessWidget {
  const _Movement({required this.expense, required this.hidden});
  final Expense expense;
  final bool hidden;
  @override
  Widget build(BuildContext context) {
    final color = categoryColor(expense.category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .11),
              borderRadius: AppRadius.all(13),
            ),
            child: Icon(categoryIcon(expense.category), size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.category,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  DateFormat('d MMM y · h:mm a').format(expense.date),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            hidden
                ? maskAmount(expense.currency)
                : formatAmount(expense.amount, expense.currency),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
