import 'package:flutter/material.dart';

import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

enum FlowDestination {
  home,
  activity,
  ask;

  // Kept as source aliases while callers and tests migrate to the new
  // information architecture.
  static const today = home;
  static const review = ask;
}

/// Bottom navigation.
///
/// The three durable places in the product. Review is work that appears only
/// when needed; Ask is a core capability and therefore owns the third slot.
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
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        FlowSpace.xl,
        0,
        FlowSpace.xl,
        FlowSpace.md,
      ),
      child: Container(
        height: 64,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: flow.raised.withValues(alpha: .96),
          borderRadius: const BorderRadius.all(Radius.circular(22)),
          border: Border.all(color: flow.line.withValues(alpha: .8)),
          boxShadow: FlowElevation.low(Theme.of(context).brightness),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _Item(
                icon: Icons.home_outlined,
                activeIcon: Icons.home_rounded,
                label: 'Home',
                selected: destination == FlowDestination.home,
                onTap: () => onChanged(FlowDestination.home),
              ),
            ),
            Expanded(
              child: _Item(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long_rounded,
                label: 'Activity',
                selected: destination == FlowDestination.activity,
                onTap: () => onChanged(FlowDestination.activity),
              ),
            ),
            Expanded(
              child: _Item(
                icon: Icons.auto_awesome_outlined,
                activeIcon: Icons.auto_awesome_rounded,
                label: 'Ask',
                selected: destination == FlowDestination.ask,
                onTap: () => onChanged(FlowDestination.ask),
              ),
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
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final onPill = flow.onAccent;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.pill,
        child: AnimatedContainer(
          duration: FlowMotion.respecting(context, FlowMotion.quick),
          curve: FlowMotion.enter,
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpace.lg,
            vertical: FlowSpace.md,
          ),
          decoration: BoxDecoration(
            color: selected ? flow.accent : Colors.transparent,
            borderRadius: FlowRadius.pill,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? activeIcon : icon,
                  size: 22,
                  color: selected ? onPill : flow.inkFaint,
                ),
                const SizedBox(width: FlowSpace.sm),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: selected ? onPill : flow.inkSoft,
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
