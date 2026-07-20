import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../../domain/insight_engine.dart';
import '../../domain/money_format.dart';
import '../charts/flow_charts.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';
import '../tokens/flow_type.dart';
import 'transaction_detail_screen.dart';

/// Where you stand.
///
/// This is the daily surface. The previous build answered it through a model
/// round trip, which is the wrong shape for a question asked every morning
/// and answerable from records already on the device. Everything here is
/// computed locally and rendered without waiting for anything.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({
    super.key,
    required this.onReview,
    required this.onOpenSettings,
    required this.onAsk,
  });

  final VoidCallback onReview;
  final VoidCallback onOpenSettings;

  /// Opens the conversation on a question, so a noticed thing can be
  /// explained by the agent rather than dead-ending on the card.
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final flow = context.flow;
    final summary = TodaySummary.of(app.transactions, DateTime.now());
    final hidden = app.preferences.hideAmounts;
    final review = app.transactions
        .where((item) => item.reviewState == ReviewState.needsReview)
        .length;
    // Deterministic, so this costs a pass over the ledger rather than a
    // model round trip: the screen can say something useful in its first
    // frame instead of waiting to be asked.
    final noticed = InsightEngine.insights(app.transactions, DateTime.now());

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FlowSpace.xl,
              FlowSpace.lg,
              FlowSpace.lg,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _greeting(DateTime.now()),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  onPressed: onOpenSettings,
                  tooltip: 'Settings',
                  icon: const Icon(Icons.tune_rounded),
                  color: flow.inkSoft,
                ),
              ],
            ),
          ),
        ),

        if (summary == null)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _NothingYet(onReview: onReview),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                FlowSpace.xl,
                FlowSpace.lg,
                FlowSpace.xl,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Spent this month',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                  ),
                  const SizedBox(height: FlowSpace.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          hidden
                              ? '••••••'
                              : formatMoney(
                                  summary.spentMinor,
                                  summary.currency,
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FlowType.amountHero.copyWith(color: flow.ink),
                        ),
                      ),
                      if (summary.change != null && !hidden) ...[
                        const SizedBox(width: FlowSpace.md),
                        FlowDelta(fraction: summary.change!),
                      ],
                    ],
                  ),
                  if (!hidden && summary.daily.length > 1) ...[
                    const SizedBox(height: FlowSpace.md),
                    FlowSpark(values: summary.daily),
                  ],
                ],
              ),
            ),
          ),

          // Placed directly under the headline figure: a backlog is the only
          // thing on this screen that asks something of the person, so it
          // sits above the detail rather than after it.
          if (review > 0)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FlowSpace.xl,
                  FlowSpace.xl,
                  FlowSpace.xl,
                  0,
                ),
                child: _ReviewCallout(count: review, onTap: onReview),
              ),
            ),

          // Below the review backlog, which asks something of the person, and
          // above the breakdowns, which only describe. This is the screen
          // speaking first rather than waiting for a question.
          if (noticed.isNotEmpty)
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
                      'What I noticed',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: FlowSpace.sm),
                    for (final insight in noticed)
                      _InsightCard(
                        insight: insight,
                        hidden: hidden,
                        onTap: () => onAsk(insight.question),
                      ),
                  ],
                ),
              ),
            ),

          if (summary.categories.isNotEmpty)
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
                      'Where it went',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: FlowSpace.sm),
                    for (var i = 0; i < summary.categories.length; i++)
                      FlowBarRow(
                        label: summary.categories[i].label,
                        amount: hidden
                            ? '••••'
                            : formatMoney(
                                summary.categories[i].amountMinor,
                                summary.currency,
                              ),
                        fraction:
                            summary.categories[i].amountMinor /
                            summary.categories.first.amountMinor,
                        share: summary.spentMinor == 0
                            ? null
                            : summary.categories[i].amountMinor /
                                  summary.spentMinor,
                        color: flow.seriesAt(i),
                      ),
                  ],
                ),
              ),
            ),

          if (summary.recent.isNotEmpty)
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
                      'Just captured',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: FlowSpace.xs),
                    Text(
                      'Read from your messages, no entry needed.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                    ),
                    const SizedBox(height: FlowSpace.md),
                    for (final item in summary.recent)
                      _CaptureRow(item: item, hidden: hidden),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: FlowSpace.xl)),
        ],
      ],
    );
  }

  static String _greeting(DateTime now) => switch (now.hour) {
    < 5 => 'Late night',
    < 12 => 'Good morning',
    < 17 => 'Good afternoon',
    _ => 'Good evening',
  };
}

/// Something the app noticed without being asked.
///
/// Tapping hands the finding to the agent, which is the part that can
/// actually explain it — the card states what, the conversation answers why.
class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.insight,
    required this.hidden,
    required this.onTap,
  });

  final Insight insight;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final tone = switch (insight.kind) {
      InsightKind.duplicate => flow.attention,
      InsightKind.anomaly => flow.attention,
      InsightKind.pace => flow.accent,
    };
    final icon = switch (insight.kind) {
      InsightKind.duplicate => Icons.copy_all_rounded,
      InsightKind.anomaly => Icons.trending_up_rounded,
      InsightKind.pace => Icons.speed_rounded,
    };
    return Semantics(
      button: true,
      label: '${insight.title}. ${insight.detail}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.md,
        child: Container(
          margin: const EdgeInsets.only(bottom: FlowSpace.sm),
          padding: const EdgeInsets.all(FlowSpace.lg),
          decoration: BoxDecoration(
            color: flow.raised,
            borderRadius: FlowRadius.md,
            border: Border.all(color: flow.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: tone),
              const SizedBox(width: FlowSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      insight.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      insight.detail,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FlowSpace.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(
                      insight.amountMinor,
                      insight.currency,
                      hidden: hidden,
                    ),
                    style: FlowType.amountRow.copyWith(color: flow.ink),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 14,
                    color: flow.inkFaint,
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

/// Prompts the one job that needs a person.
class _ReviewCallout extends StatelessWidget {
  const _ReviewCallout({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Semantics(
      button: true,
      label: '$count transactions need review',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.md,
        child: Container(
          padding: const EdgeInsets.all(FlowSpace.lg),
          decoration: BoxDecoration(
            color: flow.raised,
            borderRadius: FlowRadius.md,
            border: Border.all(color: flow.attention.withValues(alpha: .45)),
          ),
          child: Row(
            children: [
              Icon(Icons.rule_rounded, size: 20, color: flow.attention),
              const SizedBox(width: FlowSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 1
                          ? '1 transaction needs a look'
                          : '$count transactions need a look',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Confirm or correct what was read.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: flow.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaptureRow extends StatelessWidget {
  const _CaptureRow({required this.item, required this.hidden});
  final MoneyTransaction item;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final incoming = item.direction == TransactionDirection.incoming;
    final confident = item.reviewState != ReviewState.needsReview;
    return InkWell(
      // A capture is a claim, and the detail route is where the claim can be
      // checked — so the row that announces it also opens it.
      onTap: item.id == null
          ? null
          : () => TransactionDetailScreen.open(context, item.id!),
      child: Padding(
        padding: const EdgeInsets.only(bottom: FlowSpace.sm),
        child: Row(
          children: [
            // Confidence is stated with an icon and a word, never colour alone.
            Icon(
              confident
                  ? Icons.check_circle_outline_rounded
                  : Icons.help_outline_rounded,
              size: 17,
              color: confident ? flow.income : flow.attention,
            ),
            const SizedBox(width: FlowSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Text(
                    confident
                        ? item.category
                        : '${item.category} · needs a look',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: confident ? flow.inkFaint : flow.attention,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              hidden
                  ? '••••'
                  : '${incoming ? '+' : '−'}'
                        '${formatMoney(item.amountMinor, item.currency)}',
              style: FlowType.amountRow.copyWith(
                color: incoming ? flow.income : flow.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet({required this.onReview});
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlowSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 28, color: flow.accent),
            const SizedBox(height: FlowSpace.lg),
            Text(
              'Nothing tracked yet.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: FlowSpace.sm),
            Text(
              'Fund Flow reads your transaction messages and builds your '
              'ledger for you. You never add anything by hand.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: flow.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// Locally computed position for the current month.
class TodaySummary {
  const TodaySummary({
    required this.spentMinor,
    required this.currency,
    required this.change,
    required this.daily,
    required this.categories,
    required this.recent,
  });

  final int spentMinor;
  final String currency;

  /// Change against the previous month, null without one to compare.
  final double? change;
  final List<int> daily;
  final List<CategoryTotal> categories;
  final List<MoneyTransaction> recent;

  /// Summarises [values] for the month containing [now].
  ///
  /// Only the most common currency is totalled. Summing across rates would
  /// state a number the records do not support.
  static TodaySummary? of(List<MoneyTransaction> values, DateTime now) {
    final outgoing = values.where(
      (item) => item.direction == TransactionDirection.outgoing,
    );
    if (outgoing.isEmpty) return null;

    final counts = <String, int>{};
    for (final item in outgoing) {
      counts[item.currency] = (counts[item.currency] ?? 0) + 1;
    }
    final currency = counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    final monthStart = DateTime(now.year, now.month);
    final previousStart = DateTime(now.year, now.month - 1);
    var spent = 0;
    var previous = 0;
    final daily = List<int>.filled(now.day, 0);
    final byCategory = <String, int>{};

    for (final item in outgoing.where((e) => e.currency == currency)) {
      final at = item.occurredAt;
      if (!at.isBefore(monthStart)) {
        spent += item.amountMinor;
        final index = at.day - 1;
        if (index >= 0 && index < daily.length) {
          daily[index] += item.amountMinor;
        }
        byCategory[item.category] =
            (byCategory[item.category] ?? 0) + item.amountMinor;
      } else if (!at.isBefore(previousStart)) {
        previous += item.amountMinor;
      }
    }
    if (spent == 0) return null;

    final categories =
        byCategory.entries
            .map((e) => CategoryTotal(label: e.key, amountMinor: e.value))
            .toList()
          ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    final recent = [...values]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return TodaySummary(
      spentMinor: spent,
      currency: currency,
      change: previous == 0 ? null : (spent - previous) / previous,
      daily: daily,
      categories: categories.take(5).toList(),
      recent: recent.take(4).toList(),
    );
  }
}

class CategoryTotal {
  const CategoryTotal({required this.label, required this.amountMinor});
  final String label;
  final int amountMinor;
}
