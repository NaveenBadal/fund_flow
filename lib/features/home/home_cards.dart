import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../../domain/analytics.dart';
import '../../domain/budget.dart';
import '../../domain/insight_engine.dart';
import '../budgets/budgets_page.dart';
import '../common/formatting.dart';
import '../subscriptions/subscriptions_page.dart';
import 'breakdown_page.dart';

/// Things that need a person, and nothing else.
///
/// Absent when it has nothing to say. A permanent "you're all caught up" card
/// costs 80 vertical pixels forever to deliver no information, and trains the
/// eye to skip the region where the real warnings appear.
class AttentionStrip extends ConsumerWidget {
  const AttentionStrip({
    super.key,
    required this.snapshot,
    required this.onReview,
    required this.onDuplicates,
    required this.onBudget,
  });

  final HomeSnapshot snapshot;
  final VoidCallback onReview;
  final VoidCallback onDuplicates;
  final ValueChanged<BudgetStatus> onBudget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);
    final overBudget = snapshot.budgets.where((status) => status.over).toList();

    final items = <_AttentionItem>[
      if (snapshot.reviewCount > 0)
        _AttentionItem(
          label: snapshot.reviewCount == 1
              ? '1 transaction needs review'
              : '${snapshot.reviewCount} transactions need review',
          detail: 'The extraction was unsure about these',
          icon: Icons.rule_rounded,
          onTap: onReview,
        ),
      for (final status in overBudget.take(2))
        _AttentionItem(
          label:
              '${status.category} is at ${(status.fraction * 100).round()}% of its limit',
          detail:
              '${money(status.spentMinor, status.currency)} of '
              '${money(status.limitMinor, status.currency)}',
          icon: Icons.error_outline_rounded,
          onTap: () => onBudget(status),
        ),
      if (snapshot.duplicateCount > 0)
        _AttentionItem(
          label: snapshot.duplicateCount == 1
              ? '1 possible duplicate charge'
              : '${snapshot.duplicateCount} possible duplicate charges',
          detail: 'Same merchant, same amount, close together',
          icon: Icons.copy_all_rounded,
          onTap: onDuplicates,
        ),
    ];

    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: FluxSpace.x4),
      child: FluxCard(
        padding: EdgeInsets.zero,
        clip: true,
        border: palette.attention.withValues(alpha: 0.25),
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++) ...[
              if (index > 0) const FluxLine(indent: FluxSpace.x10),
              FluxPressable(
                feedback: PressFeedback.wash,
                onTap: items[index].onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluxSpace.x4,
                    vertical: FluxSpace.x3 + 1,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        items[index].icon,
                        size: 18,
                        color: palette.attention,
                      ),
                      const SizedBox(width: FluxSpace.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              items[index].label,
                              style: FluxType.body.copyWith(
                                color: palette.text,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              items[index].detail,
                              style: FluxType.caption.copyWith(
                                color: palette.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: palette.textFaint,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttentionItem {
  const _AttentionItem({
    required this.label,
    required this.detail,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final String detail;
  final IconData icon;
  final VoidCallback onTap;
}

/// Where the month's money went: a donut plus a named, priced legend.
class BreakdownCard extends ConsumerWidget {
  const BreakdownCard({
    super.key,
    required this.snapshot,
    required this.onCategory,
  });

  final HomeSnapshot snapshot;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);

    if (snapshot.categories.isEmpty) return const SizedBox.shrink();

    // Past the eight validated hues, categories fold into one neutral "Other"
    // slice. Generating a ninth colour is how a chart stops being readable.
    const visible = 5;
    final top = snapshot.categories.take(visible).toList();
    final rest = snapshot.categories.skip(visible).toList();
    final restTotal = rest.fold<int>(0, (sum, row) => sum + row.amountMinor);

    final slices = [
      for (final row in top)
        FluxSlice(
          label: row.category,
          value: row.amountMinor.toDouble(),
          color: palette.forCategory(row.category),
          display: money(row.amountMinor, snapshot.currency),
        ),
      if (restTotal > 0)
        FluxSlice(
          label: rest.length == 1 ? rest.first.category : '${rest.length} more',
          value: restTotal.toDouble(),
          color: palette.neutralCategory,
          display: money(restTotal, snapshot.currency),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluxSectionHeader(
          title: 'Where it went',
          action: 'All',
          onAction: () => fluxPush(
            context,
            (context) => BreakdownPage(currency: snapshot.currency),
          ),
          padding: const EdgeInsets.only(
            top: FluxSpace.x6,
            bottom: FluxSpace.x2,
          ),
        ),
        FluxCard(
          child: Row(
            children: [
              FluxDonut(
                slices: slices,
                size: 116,
                thickness: 15,
                // Rounded to whole units for the hole: the exact figure with
                // paise in it is wider than the ring's diameter, and the total
                // is repeated exactly in the flow card above.
                centreValue: money(
                  (snapshot.month.outgoingMinor ~/ 100) * 100,
                  snapshot.currency,
                ),
                centreLabel: 'spent',
              ),
              const SizedBox(width: FluxSpace.x5),
              Expanded(
                child: FluxDonutLegend(
                  slices: slices,
                  max: 6,
                  onTap: (slice) {
                    // "3 more" is not a category, so it opens the full
                    // breakdown rather than filtering to a name that does not
                    // exist.
                    final known = snapshot.categories.any(
                      (row) => row.category == slice.label,
                    );
                    if (known) {
                      onCategory(slice.label);
                    } else {
                      fluxPush(
                        context,
                        (context) => BreakdownPage(currency: snapshot.currency),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Daily spend across the month, with today picked out.
class DailyCard extends ConsumerWidget {
  const DailyCard({super.key, required this.snapshot});
  final HomeSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);
    if (snapshot.daily.length < 3) return const SizedBox.shrink();
    // Nothing spent yet this month: a row of empty stubs under a "busiest day"
    // of zero is worse than no card at all.
    if (snapshot.month.outgoingMinor <= 0) return const SizedBox.shrink();
    final today = DateTime.now().day;

    final busiest = snapshot.daily.reduce(
      (a, b) => a.amountMinor >= b.amountMinor ? a : b,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FluxSectionHeader(
          title: 'Day by day',
          padding: EdgeInsets.only(top: FluxSpace.x6, bottom: FluxSpace.x2),
        ),
        FluxCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Busiest day',
                          style: FluxType.caption.copyWith(
                            color: palette.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          shortDay(busiest.day),
                          style: FluxType.subtitle.copyWith(
                            color: palette.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  MoneyText(
                    money(busiest.amountMinor, snapshot.currency),
                    style: FluxType.moneyLarge,
                  ),
                ],
              ),
              const SizedBox(height: FluxSpace.x4),
              FluxBars(
                height: 64,
                bars: [
                  for (final (index, day) in snapshot.daily.indexed)
                    FluxBar(
                      value: day.amountMinor.toDouble(),
                      // Short months of data get every other day labelled; a
                      // full month gets every fifth, so the axis never turns
                      // into a solid run of digits.
                      label: _dayLabelFor(
                        index,
                        snapshot.daily.length,
                        day.day,
                      ),
                      highlight: day.day.day == today,
                    ),
                ],
                showLabels: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _dayLabelFor(int index, int count, DateTime day) {
  final step = count <= 10 ? 2 : 5;
  return index == count - 1 || index % step == 0 ? '${day.day}' : '';
}

/// Budget rings, or the one row that offers to create the first budget.
class BudgetsCard extends ConsumerWidget {
  const BudgetsCard({super.key, required this.snapshot});
  final HomeSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final money = ref.watch(moneyProvider);
    final palette = context.flux;

    if (snapshot.budgets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: FluxSpace.x4),
        child: FluxCard(
          onTap: () => fluxPush(context, (context) => const BudgetsPage()),
          child: Row(
            children: [
              Icon(Icons.track_changes_rounded, size: 20, color: palette.iris),
              const SizedBox(width: FluxSpace.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Set a monthly limit',
                      style: FluxType.body.copyWith(color: palette.text),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      'Then "how am I doing?" has an answer',
                      style: FluxType.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: palette.textFaint,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluxSectionHeader(
          title: 'Limits',
          action: 'Manage',
          onAction: () => fluxPush(context, (context) => const BudgetsPage()),
          padding: const EdgeInsets.only(
            top: FluxSpace.x6,
            bottom: FluxSpace.x2,
          ),
        ),
        FluxCard(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpace.x4,
            vertical: FluxSpace.x4,
          ),
          child: SizedBox(
            height: 116,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: snapshot.budgets.length,
              separatorBuilder: (context, index) =>
                  const SizedBox(width: FluxSpace.x4),
              itemBuilder: (context, index) {
                final status = snapshot.budgets[index];
                return FluxRing(
                  fraction: status.fraction,
                  label: status.category,
                  detail:
                      '${money(status.spentMinor, status.currency)} / '
                      '${money(status.limitMinor, status.currency)}',
                  size: 76,
                  onTap: () =>
                      fluxPush(context, (context) => const BudgetsPage()),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Confirmed-looking repeat charges landing in the next fortnight.
class UpcomingCard extends ConsumerWidget {
  const UpcomingCard({super.key, required this.snapshot});
  final HomeSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);
    if (snapshot.upcoming.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FluxSectionHeader(
          title: 'Coming up',
          action: 'All',
          onAction: () =>
              fluxPush(context, (context) => const SubscriptionsPage()),
          padding: const EdgeInsets.only(
            top: FluxSpace.x6,
            bottom: FluxSpace.x2,
          ),
        ),
        FluxCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: Column(
            children: [
              for (
                var index = 0;
                index < snapshot.upcoming.length;
                index++
              ) ...[
                if (index > 0) const FluxLine(indent: FluxSpace.x4),
                _UpcomingRow(
                  charge: snapshot.upcoming[index],
                  now: now,
                  money: money,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: FluxSpace.x2, left: FluxSpace.x1),
          child: Text(
            'Estimated from repeat charges, not from the merchant.',
            style: FluxType.caption.copyWith(color: palette.textFaint),
          ),
        ),
      ],
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({
    required this.charge,
    required this.now,
    required this.money,
  });

  final RecurringCharge charge;
  final DateTime now;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpace.x4,
        vertical: FluxSpace.x3,
      ),
      child: Row(
        children: [
          FluxAvatar(
            name: charge.merchant,
            tint: palette.forCategory(charge.category),
            size: 34,
          ),
          const SizedBox(width: FluxSpace.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  charge.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FluxType.body.copyWith(color: palette.text),
                ),
                const SizedBox(height: 1),
                Text(
                  '${relativeDays(charge.daysUntilNext(now))} · about every '
                  '${charge.averageGapDays} days',
                  style: FluxType.caption.copyWith(color: palette.textMuted),
                ),
              ],
            ),
          ),
          MoneyText(money(charge.typicalMinor, charge.currency)),
        ],
      ),
    );
  }
}

/// One observation, computed locally, that hands off to the agent when tapped.
class InsightCard extends ConsumerWidget {
  const InsightCard({super.key, required this.insight, required this.onAsk});

  final Insight insight;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    return Padding(
      padding: const EdgeInsets.only(top: FluxSpace.x6),
      child: FluxCard(
        onTap: () => onAsk(insight.question),
        border: palette.iris.withValues(alpha: 0.2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) =>
                      FluxPalette.ai.createShader(bounds),
                  blendMode: BlendMode.srcIn,
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 15,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
                const SizedBox(width: FluxSpace.x2),
                Text(
                  'NOTICED',
                  style: FluxType.overline.copyWith(color: palette.iris),
                ),
              ],
            ),
            const SizedBox(height: FluxSpace.x3),
            Text(
              insight.title,
              style: FluxType.subtitle.copyWith(color: palette.text),
            ),
            const SizedBox(height: FluxSpace.x1),
            Text(
              insight.detail,
              style: FluxType.body.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: FluxSpace.x4),
            Row(
              children: [
                Text(
                  'Ask about this',
                  style: FluxType.label.copyWith(color: palette.iris),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 14,
                  color: palette.iris,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
