import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/analytics.dart';
import '../../domain/transaction.dart';
import '../activity/activity_filter.dart';
import '../common/formatting.dart';
import '../shell/shell.dart';

/// The full breakdown for a period, in one currency, ranked.
///
/// The donut on Home shows five slices and folds the rest; this is where the
/// rest lives, with the comparison against the previous period that a donut
/// cannot express.
class BreakdownPage extends ConsumerStatefulWidget {
  const BreakdownPage({super.key, required this.currency});
  final String currency;

  @override
  ConsumerState<BreakdownPage> createState() => _BreakdownPageState();
}

class _BreakdownPageState extends ConsumerState<BreakdownPage> {
  ActivityPeriod _period = ActivityPeriod.thisMonth;
  TransactionDirection _direction = TransactionDirection.outgoing;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);
    final transactions =
        ref.watch(appControllerProvider).value?.transactions ??
        const <MoneyTransaction>[];

    final filter = ActivityFilter(period: _period);
    final (from, to) = filter.range;
    final now = DateTime.now();
    final start = from ?? DateTime(2000);
    final end = to ?? now.add(const Duration(days: 1));

    final rows = Analytics.byCategory(
      transactions: transactions,
      from: start,
      to: end,
      currency: widget.currency,
      direction: _direction,
    );

    // The same length of time immediately before the period on screen, so the
    // delta beside each row compares like with like.
    final span = end.difference(start);
    final previous = Analytics.byCategory(
      transactions: transactions,
      from: start.subtract(span),
      to: start,
      currency: widget.currency,
      direction: _direction,
    );
    final previousByCategory = {
      for (final row in previous) row.category.toLowerCase(): row.amountMinor,
    };

    final total = rows.fold<int>(0, (sum, row) => sum + row.amountMinor);
    final largest = rows.isEmpty ? 0 : rows.first.amountMinor;

    return FluxDetailPage(
      title: 'Breakdown',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FluxSegmented<ActivityPeriod>(
                value: _period,
                onChanged: (value) => setState(() => _period = value),
                options: const [
                  (ActivityPeriod.thisMonth, 'Month'),
                  (ActivityPeriod.lastMonth, 'Last'),
                  (ActivityPeriod.last90, '90 days'),
                  (ActivityPeriod.all, 'All'),
                ],
              ),
              const SizedBox(height: FluxSpace.x3),
              FluxSegmented<TransactionDirection>(
                value: _direction,
                onChanged: (value) => setState(() => _direction = value),
                options: const [
                  (TransactionDirection.outgoing, 'Spending'),
                  (TransactionDirection.incoming, 'Income'),
                ],
              ),
              const SizedBox(height: FluxSpace.x5),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      _direction == TransactionDirection.outgoing
                          ? 'Total spent'
                          : 'Total received',
                      style: FluxType.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                  MoneyText(
                    money(total, widget.currency),
                    style: FluxType.moneyLarge,
                    incoming: _direction == TransactionDirection.incoming,
                  ),
                ],
              ),
              const SizedBox(height: FluxSpace.x2),
              Text(
                'Every group, largest first. ${widget.currency} only — '
                'currencies are never added together.',
                style: FluxType.caption.copyWith(color: palette.textFaint),
              ),
            ],
          ),
        ),
        if (rows.isEmpty)
          const SliverToBoxAdapter(
            child: FluxEmpty(
              icon: Icons.donut_large_outlined,
              title: 'Nothing in this period',
              message: 'Try a wider period.',
              compact: true,
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: FluxSpace.x6),
              child: FluxGroup(
                children: [
                  for (final row in rows)
                    _BreakdownRow(
                      row: row,
                      currency: widget.currency,
                      fraction: largest <= 0 ? 0 : row.amountMinor / largest,
                      previousMinor:
                          previousByCategory[row.category.toLowerCase()],
                      label: money(row.amountMinor, widget.currency),
                      onTap: () {
                        ref
                            .read(activityFilterProvider.notifier)
                            .state = ActivityFilter(
                          period: _period,
                          direction: _direction,
                          category: row.category,
                        );
                        ref.read(shellTabProvider.notifier).state = 1;
                        Navigator.of(context).maybePop();
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.row,
    required this.currency,
    required this.fraction,
    required this.previousMinor,
    required this.label,
    required this.onTap,
  });

  final CategoryTotal row;
  final String currency;
  final double fraction;
  final int? previousMinor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final color = palette.forCategory(row.category);
    final change = (previousMinor == null || previousMinor! <= 0)
        ? null
        : (row.amountMinor - previousMinor!) / previousMinor!;

    return FluxPressable(
      onTap: onTap,
      feedback: PressFeedback.wash,
      haptic: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FluxSpace.x4,
          vertical: FluxSpace.x3 + 1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: ShapeDecoration(
                    color: color,
                    shape: const CircleBorder(),
                  ),
                ),
                const SizedBox(width: FluxSpace.x2),
                Expanded(
                  child: Text(
                    row.category,
                    style: FluxType.body.copyWith(color: palette.text),
                  ),
                ),
                if (change != null) ...[
                  FluxDelta(fraction: change, compact: true),
                  const SizedBox(width: FluxSpace.x2),
                ],
                MoneyText(label),
              ],
            ),
            const SizedBox(height: FluxSpace.x2),
            Row(
              children: [
                Expanded(
                  child: FluxProportion(fraction: fraction, color: color),
                ),
                const SizedBox(width: FluxSpace.x3),
                Text(
                  '${row.transactionCount}',
                  style: FluxType.caption.copyWith(color: palette.textFaint),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
