import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';
import 'budget_screen.dart';
import 'savings_goals_screen.dart';
import 'subscriptions_screen.dart';

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance =
        ref.watch(currentMonthBalanceProvider).asData?.value ??
        const <String, double>{};
    final budgets =
        ref.watch(budgetProgressProvider).asData?.value ??
        const <Map<String, dynamic>>[];
    final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
    final detectedIncome = balance['income'] ?? 0;
    final expense = balance['expense'] ?? 0;
    final briefing = ref.watch(moneyBriefingProvider);
    final income = briefing?.income ?? detectedIncome;
    final free = briefing?.safeToSpend ?? (income - expense);
    final currency = ref.watch(preferredCurrencyProvider);
    final hidden = ref.watch(privateModeProvider);
    String money(double value) =>
        hidden ? maskAmount(currency) : formatAmount(value, currency);
    final pressure = budgets.where((b) {
      final limit = (b['limit_amount'] as num?)?.toDouble() ?? 0;
      final spent = (b['spent'] as num?)?.toDouble() ?? 0;
      return limit > 0 && spent / limit >= .8;
    }).length;

    return CommandScaffold(
      eyebrow: 'A simulation of what comes next',
      title: 'Possible futures',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: AppRadius.all(AppRadius.xxl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UNCOMMITTED POSSIBILITY',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimaryContainer.withValues(alpha: .65),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    money(free),
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    free > 0
                        ? briefing != null &&
                                  (briefing.commitmentsTotal > 0 ||
                                      briefing.goalReserve > 0)
                              ? 'Upcoming commitments and goal pace are already protected.'
                              : 'Available to budget, save, or enjoy.'
                        : 'Your plan needs attention before the month ends.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionLabel('Change the future')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.list(
            children: [
              _PlanDestination(
                icon: Icons.donut_large_rounded,
                title: 'Pressure boundaries',
                subtitle:
                    '${budgets.length} budgets · $pressure need attention',
                accent: const Color(0xFFFF7657),
                onTap: () => _push(context, const BudgetScreen()),
              ),
              const SizedBox(height: 12),
              _PlanDestination(
                icon: Icons.repeat_rounded,
                title: 'Inevitable movements',
                subtitle: 'Bills and repeating commitments',
                accent: const Color(0xFF6C8CFF),
                onTap: () => _push(context, const SubscriptionsScreen()),
              ),
              const SizedBox(height: 12),
              _PlanDestination(
                icon: Icons.flag_rounded,
                title: 'Future anchors',
                subtitle: '${goals.length} goals in progress',
                accent: const Color(0xFF22A879),
                onTap: () => _push(context, const SavingsGoalsScreen()),
              ),
            ],
          ),
        ),
        const SliverToBoxAdapter(child: SectionLabel('Current trajectory')),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 128,
                    child: MetricTile(
                      label: 'ENERGY IN',
                      value: money(income),
                      icon: Icons.south_west_rounded,
                      color: context.finance.income,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 128,
                    child: MetricTile(
                      label: 'ENERGY OUT',
                      value: money(expense),
                      icon: Icons.north_east_rounded,
                      color: context.finance.expense,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _PlanDestination extends StatelessWidget {
  const _PlanDestination({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: AppRadius.all(AppRadius.lg),
    child: InkWell(
      borderRadius: AppRadius.all(AppRadius.lg),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .12),
                borderRadius: AppRadius.all(15),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, size: 20),
          ],
        ),
      ),
    ),
  );
}
