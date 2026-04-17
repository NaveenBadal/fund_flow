import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import 'merchant_profile_screen.dart';

// Groups recurring expenses by merchant and computes derived stats.
class _SubscriptionInfo {
  final String merchant;
  final String category;
  final double avgAmount;
  final String currency;
  final DateTime lastCharged;
  final String frequency; // 'monthly' | 'weekly' | 'yearly' | 'unknown'
  final double monthlyCost;
  final int txnCount;

  const _SubscriptionInfo({
    required this.merchant,
    required this.category,
    required this.avgAmount,
    required this.currency,
    required this.lastCharged,
    required this.frequency,
    required this.monthlyCost,
    required this.txnCount,
  });
}

List<_SubscriptionInfo> _buildSubscriptions(List<Expense> expenses) {
  final recurring = expenses
      .where((e) => e.isRecurring && !e.isIncome)
      .toList();

  // Group by normalised merchant key
  final Map<String, List<Expense>> groups = {};
  for (final e in recurring) {
    final key = (e.normalizedMerchant ?? e.merchant).toLowerCase().trim();
    groups.putIfAbsent(key, () => []).add(e);
  }

  final List<_SubscriptionInfo> result = [];

  for (final entry in groups.entries) {
    final list = entry.value
      ..sort((a, b) => a.date.compareTo(b.date));

    final displayMerchant = list.last.displayMerchant;
    final category = list.last.category;
    final currency = list.last.currency;
    final lastCharged = list.last.date;

    final double avgAmount =
        list.fold(0.0, (sum, e) => sum + e.amount) / list.length;

    // Compute average gap between transactions
    String frequency = 'monthly';
    double monthlyCost = avgAmount;

    if (list.length >= 2) {
      final totalDays =
          list.last.date.difference(list.first.date).inDays.toDouble();
      final avgGapDays = totalDays / (list.length - 1);

      if (avgGapDays <= 10) {
        frequency = 'weekly';
        monthlyCost = avgAmount * (30 / 7);
      } else if (avgGapDays <= 45) {
        frequency = 'monthly';
        monthlyCost = avgAmount;
      } else if (avgGapDays <= 200) {
        frequency = 'quarterly';
        monthlyCost = avgAmount / 3;
      } else {
        frequency = 'yearly';
        monthlyCost = avgAmount / 12;
      }
    }

    result.add(_SubscriptionInfo(
      merchant: displayMerchant,
      category: category,
      avgAmount: avgAmount,
      currency: currency,
      lastCharged: lastCharged,
      frequency: frequency,
      monthlyCost: monthlyCost,
      txnCount: list.length,
    ));
  }

  result.sort((a, b) => b.monthlyCost.compareTo(a.monthlyCost));
  return result;
}

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expenseListProvider);
    final privateMode = ref.watch(privateModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Subscriptions')),
      body: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (expenses) {
          final subs = _buildSubscriptions(expenses);

          if (subs.isEmpty) {
            return const _EmptyState();
          }

          // Total monthly cost (in primary currency of first sub)
          final totalMonthlyCost =
              subs.fold(0.0, (sum, s) => sum + s.monthlyCost);
          final primaryCurrency =
              subs.isNotEmpty ? subs.first.currency : 'INR';

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: _HeroCard(
                    totalMonthlyCost: totalMonthlyCost,
                    currency: primaryCurrency,
                    count: subs.length,
                    privateMode: privateMode,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                sliver: SliverList.separated(
                  itemCount: subs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _SubscriptionCard(
                    info: subs[index],
                    privateMode: privateMode,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MerchantProfileScreen(
                          merchant: subs[index].merchant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.totalMonthlyCost,
    required this.currency,
    required this.count,
    required this.privateMode,
  });

  final double totalMonthlyCost;
  final String currency;
  final int count;
  final bool privateMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
              child: Icon(
                Icons.repeat_rounded,
                color: scheme.onPrimaryContainer,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    privateMode
                        ? maskAmount(currency)
                        : formatAmount(totalMonthlyCost, currency),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$count subscription${count == 1 ? '' : 's'} · per month',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.75),
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

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.info,
    required this.privateMode,
    required this.onTap,
  });

  final _SubscriptionInfo info;
  final bool privateMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final catColor = categoryColor(info.category);

    final daysSince = DateTime.now().difference(info.lastCharged).inDays;
    final lastChargedLabel = daysSince == 0
        ? 'Today'
        : daysSince == 1
            ? 'Yesterday'
            : '$daysSince days ago';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: catColor.withValues(alpha: 0.15),
                child: Icon(
                  categoryIcon(info.category),
                  color: catColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.merchant,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _Chip(
                          label: info.frequency,
                          color: scheme.secondaryContainer,
                          textColor: scheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 6),
                        _Chip(
                          label: 'Last: $lastChargedLabel',
                          color: scheme.surfaceContainerHighest,
                          textColor: scheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    privateMode
                        ? maskAmount(info.currency)
                        : formatAmount(info.monthlyCost, info.currency),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  Text(
                    '/ month',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: textColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.repeat_rounded, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'No subscriptions found.',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Sync your SMS to detect recurring payments.',
              style: theme.textTheme.bodyLarge
                  ?.copyWith(color: scheme.onSurface.withValues(alpha: 0.65)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
