import 'package:flutter/material.dart';

import '../motion/flow_motion_widgets.dart';
import '../tokens/flow_palette.dart';
import 'flow_nav.dart';

/// Assembles the destinations, the composer and the navigation bar.
///
/// Destinations are kept alive in an [IndexedStack] rather than rebuilt on
/// each switch. Activity holds scroll position over hundreds of rows, and
/// losing that place every time someone checks Today would make browsing the
/// ledger unusable.
///
/// Wide layouts move navigation to the side and let the composer keep the
/// full width, since a bar of three items across a tablet reads as an
/// unfinished phone layout.
class FlowShell extends StatelessWidget {
  const FlowShell({
    super.key,
    required this.destination,
    required this.onDestinationChanged,
    required this.today,
    required this.activity,
    required this.review,
    required this.onOpenChat,
    this.reviewCount = 0,
    this.composerHint,
    this.composerBusy = false,
    this.composerEnabled = true,
  });

  final FlowDestination destination;
  final ValueChanged<FlowDestination> onDestinationChanged;

  final Widget today;
  final Widget activity;
  final Widget review;

  final VoidCallback onOpenChat;
  final int reviewCount;
  final String? composerHint;
  final bool composerBusy;
  final bool composerEnabled;

  static const double wideBreakpoint = 760;

  int get _index => switch (destination) {
    FlowDestination.home => 0,
    FlowDestination.activity => 1,
    FlowDestination.ask => 2,
  };

  @override
  Widget build(BuildContext context) {
    // The fade wraps the stack rather than replacing it: destinations stay
    // alive and keep their scroll position, and the switch reads as arrival.
    final stack = FlowIndexFade(
      index: _index,
      child: IndexedStack(index: _index, children: [today, activity, review]),
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= wideBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                _SideNav(
                  destination: destination,
                  onChanged: onDestinationChanged,
                  reviewCount: reviewCount,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(child: SafeArea(bottom: false, child: stack)),
                      SizedBox(height: MediaQuery.paddingOf(context).bottom),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          body: Column(
            children: [
              Expanded(child: SafeArea(bottom: false, child: stack)),
              FlowNav(
                destination: destination,
                onChanged: onDestinationChanged,
                reviewCount: reviewCount,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.destination,
    required this.onChanged,
    required this.reviewCount,
  });

  final FlowDestination destination;
  final ValueChanged<FlowDestination> onChanged;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      width: 84,
      decoration: BoxDecoration(
        color: flow.canvas,
        border: Border(right: BorderSide(color: flow.line)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            for (final entry in const [
              (FlowDestination.home, Icons.home_rounded, 'Home'),
              (
                FlowDestination.activity,
                Icons.receipt_long_rounded,
                'Activity',
              ),
              (FlowDestination.ask, Icons.auto_awesome_rounded, 'Ask'),
            ])
              _SideItem(
                icon: entry.$2,
                label: entry.$3,
                selected: destination == entry.$1,
                onTap: () => onChanged(entry.$1),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? flow.accent : flow.inkFaint,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: selected ? flow.ink : flow.inkFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
