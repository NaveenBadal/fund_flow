import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';
import 'merchant_profile_screen.dart';

class _Commitment {
  const _Commitment({
    required this.merchant,
    required this.category,
    required this.currency,
    required this.last,
    required this.frequency,
    required this.monthly,
    required this.average,
    required this.count,
  });
  final String merchant, category, currency, frequency;
  final DateTime last;
  final double monthly, average;
  final int count;
}

List<_Commitment> _commitments(List<Expense> expenses) {
  final groups = <String, List<Expense>>{};
  for (final item in expenses.where((e) => e.isRecurring && !e.isIncome)) {
    groups
        .putIfAbsent(
          (item.normalizedMerchant ?? item.merchant).toLowerCase().trim(),
          () => [],
        )
        .add(item);
  }
  final result = <_Commitment>[];
  for (final list in groups.values) {
    list.sort((a, b) => a.date.compareTo(b.date));
    final average =
        list.fold<double>(0, (sum, e) => sum + e.amount) / list.length;
    var frequency = 'Monthly';
    var monthly = average;
    if (list.length > 1) {
      final gap =
          list.last.date.difference(list.first.date).inDays / (list.length - 1);
      if (gap <= 10) {
        frequency = 'Weekly';
        monthly = average * 30 / 7;
      } else if (gap <= 45) {
        frequency = 'Monthly';
      } else if (gap <= 200) {
        frequency = 'Quarterly';
        monthly = average / 3;
      } else {
        frequency = 'Yearly';
        monthly = average / 12;
      }
    }
    final last = list.last;
    result.add(
      _Commitment(
        merchant: last.displayMerchant,
        category: last.category,
        currency: last.currency,
        last: last.date,
        frequency: frequency,
        monthly: monthly,
        average: average,
        count: list.length,
      ),
    );
  }
  result.sort((a, b) => b.monthly.compareTo(a.monthly));
  return result;
}

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(expenseListProvider);
    final hidden = ref.watch(privateModeProvider);
    final preferredCurrency = ref.watch(preferredCurrencyProvider);
    return CommandScaffold(
      eyebrow: 'Movements that happen without asking',
      title: 'Inevitable money',
      slivers: [
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.repeat_rounded,
              title: 'Commitments unavailable',
              message: '$error',
            ),
          ),
          data: (expenses) {
            final items = _commitments(
              expenses.where((e) => e.currency == preferredCurrency).toList(),
            );
            if (items.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: StatePanel(
                  icon: Icons.repeat_rounded,
                  title: 'No repeating charges yet',
                  message:
                      'Once a recurring pattern is confirmed, it will appear here automatically.',
                ),
              );
            }
            final currency = items.first.currency;
            final total = items.fold<double>(
              0,
              (sum, item) => sum + item.monthly,
            );
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF090D16),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(38),
                          bottomLeft: Radius.circular(38),
                          bottomRight: Radius.circular(8),
                        ),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MONTHLY BASELINE',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface
                                      .withValues(alpha: .6),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hidden
                                ? maskAmount(currency)
                                : formatAmount(total, currency),
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onInverseSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hidden
                                ? '${items.length} commitments · yearly total hidden'
                                : '${items.length} commitments · ${formatAmount(total * 12, currency)} projected yearly',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface
                                      .withValues(alpha: .68),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SectionLabel('Patterns Flow detected'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      indent: 58,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .45),
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final color = categoryColor(item.category);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        shape: const Border(
                          left: BorderSide(
                            color: Color(0xFF65EAD1),
                            width: 1.5,
                          ),
                        ),
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .12),
                            borderRadius: AppRadius.all(15),
                          ),
                          child: Icon(
                            categoryIcon(item.category),
                            color: color,
                          ),
                        ),
                        title: Text(
                          item.merchant,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${item.frequency} · last ${DateFormat('d MMM').format(item.last)}',
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              hidden
                                  ? maskAmount(item.currency)
                                  : formatAmount(item.monthly, item.currency),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Text(
                              '/ month',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MerchantProfileScreen(merchant: item.merchant),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
