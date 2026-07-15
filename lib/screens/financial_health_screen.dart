import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/command_ui.dart';

class FinancialHealthScreen extends ConsumerWidget {
  const FinancialHealthScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(financialHealthScoreProvider);
    return CommandScaffold(
      eyebrow: 'Capacity to absorb the unexpected',
      title: 'Resilience field',
      slivers: [
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.monitor_heart_outlined,
              title: 'Score unavailable',
              message: '$error',
            ),
          ),
          data: (health) {
            final color = _color(context, health.score);
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverList.list(
                children: [
                  Container(
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
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${health.score}',
                              style: Theme.of(context).textTheme.displayLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onInverseSurface,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -2,
                                  ),
                            ),
                            Text(
                              '/100',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onInverseSurface
                                        .withValues(alpha: .55),
                                  ),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: AppRadius.all(99),
                              ),
                              child: Text(
                                '${health.grade} · ${health.gradeLabel}',
                                style: TextStyle(
                                  color:
                                      ThemeData.estimateBrightnessForColor(
                                            color,
                                          ) ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: AppRadius.all(99),
                          child: LinearProgressIndicator(
                            value: health.score / 100,
                            minHeight: 10,
                            color: color,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .onInverseSurface
                                .withValues(alpha: .13),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _summary(health.score),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onInverseSurface
                                    .withValues(alpha: .72),
                                height: 1.45,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SectionLabel('Forces shaping resilience'),
                  _Factor(
                    title: 'Savings capacity',
                    value: health.savingsRate,
                    weight: '40%',
                    caption:
                        '${(health.savingsRate * 100).round()}% of income remains',
                  ),
                  const SizedBox(height: 10),
                  _Factor(
                    title: 'Budget control',
                    value: health.budgetAdherence,
                    weight: '35%',
                    caption:
                        '${(health.budgetAdherence * 100).round()}% of limits are healthy',
                  ),
                  const SizedBox(height: 10),
                  _Factor(
                    title: 'Spending direction',
                    value: health.trendScore,
                    weight: '25%',
                    caption: health.trendScore >= .5
                        ? 'Moving in the right direction'
                        : 'Higher than your recent baseline',
                  ),
                  const SectionLabel('How to read this'),
                  Text(
                    'The score is directional, not a credit rating. It combines how much income remains, whether categories stay within plan, and whether spending is improving month over month.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Color _color(BuildContext context, int score) => score >= 75
      ? context.finance.income
      : score >= 50
      ? context.finance.warning
      : context.finance.expense;
  String _summary(int score) => score >= 75
      ? 'Your current habits create useful financial breathing room.'
      : score >= 50
      ? 'Your foundation is workable, with a few pressure points worth correcting.'
      : 'Cash flow and spending limits need attention. Start with one controllable category.';
}

class _Factor extends StatelessWidget {
  const _Factor({
    required this.title,
    required this.value,
    required this.weight,
    required this.caption,
  });
  final String title;
  final double value;
  final String weight;
  final String caption;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: .66),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(6),
        topRight: Radius.circular(26),
        bottomLeft: Radius.circular(26),
        bottomRight: Radius.circular(6),
      ),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .45),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              weight,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: AppRadius.all(99),
          child: LinearProgressIndicator(value: value, minHeight: 8),
        ),
        const SizedBox(height: 8),
        Text(
          caption,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}
