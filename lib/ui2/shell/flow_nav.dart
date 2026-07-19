import 'package:flutter/material.dart';

import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

enum FlowDestination { today, activity, review }

/// Bottom navigation.
///
/// Three destinations, in the order the work actually happens: see where you
/// stand, browse what was captured, fix what was captured wrong. Settings is
/// not here because it is opened a few times ever, and a permanent slot for
/// it would cost a quarter of the bar.
class FlowNav extends StatelessWidget {
  const FlowNav({
    super.key,
    required this.destination,
    required this.onChanged,
    this.reviewCount = 0,
  });

  final FlowDestination destination;
  final ValueChanged<FlowDestination> onChanged;

  /// Shown as a badge. A backlog is the one thing in this app that actually
  /// needs someone, so it is visible from every screen rather than being
  /// discovered by opening the tab.
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      decoration: BoxDecoration(
        color: flow.canvas,
        border: Border(top: BorderSide(color: flow.line)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.symmetric(
          horizontal: FlowSpace.sm,
          vertical: FlowSpace.xs,
        ),
        child: Row(
          children: [
            _Item(
              icon: Icons.today_outlined,
              activeIcon: Icons.today_rounded,
              label: 'Today',
              selected: destination == FlowDestination.today,
              onTap: () => onChanged(FlowDestination.today),
            ),
            _Item(
              icon: Icons.receipt_long_outlined,
              activeIcon: Icons.receipt_long_rounded,
              label: 'Activity',
              selected: destination == FlowDestination.activity,
              onTap: () => onChanged(FlowDestination.activity),
            ),
            _Item(
              icon: Icons.rule_outlined,
              activeIcon: Icons.rule_rounded,
              label: 'Review',
              badge: reviewCount,
              selected: destination == FlowDestination.review,
              onTap: () => onChanged(FlowDestination.review),
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: badge > 0 ? '$label, $badge needing review' : label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: FlowRadius.md,
          child: SizedBox(
            // Grows with text scale so a label never clips at 200%.
            height: 56 + ((scale - 1).clamp(0, 1) * 26),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      selected ? activeIcon : icon,
                      size: 22,
                      color: selected ? flow.accent : flow.inkFaint,
                    ),
                    if (badge > 0)
                      Positioned(
                        right: -7,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: flow.attention,
                            borderRadius: FlowRadius.pill,
                          ),
                          child: Text(
                            // Not capped at 99: a review backlog is a job to
                            // be sized, and "99+" hides whether that means an
                            // evening or a minute.
                            badge > 999 ? '999+' : '$badge',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 10,
                                  height: 1.3,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: FlowSpace.xs),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? flow.ink : flow.inkFaint,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
