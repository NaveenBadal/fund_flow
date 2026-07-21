import 'package:flutter/material.dart';

import '../motion/flow_motion_widgets.dart';
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
    // A floating pill rather than a full-width bar with a top rule. The bar
    // read as a boundary drawn under the content; a pill reads as a control
    // resting on it, which is the whole difference in register.
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        FlowSpace.xxl,
        0,
        FlowSpace.xxl,
        FlowSpace.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(FlowSpace.xs),
        decoration: BoxDecoration(
          color: flow.raised,
          borderRadius: FlowRadius.pill,
          border: Border.all(color: flow.line),
          boxShadow: FlowElevation.card(Theme.of(context).brightness),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
    // The active destination is a filled accent pill with its label beside
    // the icon; the others are icon only. The label appearing on selection
    // is what animates the switch and keeps the bar quiet the rest of the
    // time.
    final onPill = flow.onAccent;
    return Semantics(
      button: true,
      selected: selected,
      label: badge > 0 ? '$label, $badge needing review' : label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.pill,
        child: AnimatedContainer(
          duration: FlowMotion.respecting(context, FlowMotion.quick),
          curve: FlowMotion.enter,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? FlowSpace.lg : FlowSpace.md,
            vertical: FlowSpace.md,
          ),
          decoration: BoxDecoration(
            color: selected ? flow.accent : Colors.transparent,
            borderRadius: FlowRadius.pill,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected ? activeIcon : icon,
                    size: 22,
                    color: selected ? onPill : flow.inkFaint,
                  ),
                  if (badge > 0 && !selected)
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
                        child: FlowAnimatedCount(
                          text: badge > 999 ? '999+' : '$badge',
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
              if (selected) ...[
                const SizedBox(width: FlowSpace.sm),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: onPill,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
