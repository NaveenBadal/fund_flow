import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../common/formatting.dart';

/// The hero: what this month has done to your money.
///
/// Net rather than spend, because net is the question — spending ₹80,000 on a
/// month you earned ₹200,000 is not the same fact as spending it on a month you
/// earned nothing, and a spend-only headline cannot tell them apart.
///
/// The month-progress arc under the figure is what stops the number lying by
/// omission: ₹42,000 spent means something different on the 3rd than the 28th.
class FlowCard extends ConsumerStatefulWidget {
  const FlowCard({super.key, required this.snapshot});
  final HomeSnapshot snapshot;

  @override
  ConsumerState<FlowCard> createState() => _FlowCardState();
}

class _FlowCardState extends ConsumerState<FlowCard> {
  /// Long-press peeks past the hide-amounts preference.
  ///
  /// Someone who hid amounts did it so a glance over their shoulder shows
  /// nothing — not so they can never see their own money. Holding to look is
  /// the smallest affordance that respects both.
  bool _peek = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final snapshot = widget.snapshot;
    final money = ref.watch(moneyProvider);
    final hidden = money.hidden && !_peek;
    final now = DateTime.now();

    String show(int minor) =>
        hidden ? '••••' : money.exact(minor, snapshot.currency);

    final net = snapshot.month.netMinor;
    final spendSeries = [
      for (final day in snapshot.daily) day.amountMinor.toDouble(),
    ];

    return GestureDetector(
      onLongPressStart: money.hidden
          ? (_) {
              HapticFeedback.lightImpact();
              setState(() => _peek = true);
            }
          : null,
      onLongPressEnd: money.hidden
          ? (_) => setState(() => _peek = false)
          : null,
      child: FluxCard(
        padding: const EdgeInsets.fromLTRB(
          FluxSpace.x5,
          FluxSpace.x5,
          FluxSpace.x5,
          FluxSpace.x4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${monthLabel(now)} so far',
                    style: FluxType.overline.copyWith(color: palette.textMuted),
                  ),
                ),
                // Suppressed when this month has nothing in it: "-100% spend"
                // against an empty month is arithmetic, not information, and it
                // reads as a triumph on the 1st of every month.
                if (snapshot.spendChange != null && !snapshot.month.empty)
                  FluxDelta(fraction: snapshot.spendChange!, suffix: 'spend'),
              ],
            ),
            const SizedBox(height: FluxSpace.x3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: MoneyOdometer(
                show(net.abs()),
                prefix: net == 0 ? '' : (net > 0 ? '+' : '−'),
                color: net >= 0 ? palette.text : palette.text,
              ),
            ),
            const SizedBox(height: FluxSpace.x1),
            Text(
              snapshot.month.empty
                  ? 'nothing recorded this month yet'
                  : (net >= 0
                        ? 'net, money in hand'
                        : 'net, spent more than you took in'),
              style: FluxType.caption.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: FluxSpace.x5),
            // An all-zero series drawn as a flat line reads as a chart that
            // failed to load rather than as a month with no spending in it.
            if (spendSeries.length > 1 &&
                spendSeries.any((value) => value > 0)) ...[
              FluxSparkline(
                values: spendSeries,
                color: palette.iris,
                height: 40,
              ),
              const SizedBox(height: FluxSpace.x3),
            ],
            FluxProgressArc(fraction: snapshot.elapsedFraction),
            const SizedBox(height: FluxSpace.x4),
            Row(
              children: [
                Expanded(
                  child: _Leg(
                    label: 'In',
                    value: show(snapshot.month.incomingMinor),
                    color: palette.income,
                    icon: Icons.south_west_rounded,
                  ),
                ),
                Container(width: 1, height: 30, color: palette.line),
                Expanded(
                  child: _Leg(
                    label: 'Out',
                    value: show(snapshot.month.outgoingMinor),
                    color: palette.text,
                    icon: Icons.north_east_rounded,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: FluxType.caption.copyWith(color: palette.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(value, style: FluxType.moneyRow.copyWith(color: palette.text)),
      ],
    );
  }
}
