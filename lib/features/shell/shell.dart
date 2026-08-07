import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../design/flux.dart';
import '../activity/activity_page.dart';
import '../ask/ask_page.dart';
import '../home/home_page.dart';
import 'glass_nav_bar.dart';

/// Which tab is showing. Held outside the widget so anything, anywhere, can
/// send someone to the agent with a question already in the composer.
final shellTabProvider = StateProvider<int>((ref) => 0);

/// A question waiting to be asked, set by whatever sent the person to Ask.
///
/// This is what makes "why was this higher?" work from an insight card: the tap
/// lands in the conversation someone already has, with the question in place,
/// rather than opening a second empty one.
final askSeedProvider = StateProvider<String?>((ref) => null);

/// Sends someone to Ask, optionally with a question ready to send.
void openAsk(BuildContext context, WidgetRef ref, {String? seed}) {
  if (seed != null) ref.read(askSeedProvider.notifier).state = seed;
  ref.read(shellTabProvider.notifier).state = 2;
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// The height the tab bar occupies, so pages can pad their content past it.
double shellBottomInset(BuildContext context) =>
    kFluxNavBarHeight + MediaQuery.paddingOf(context).bottom;

class FluxShell extends ConsumerStatefulWidget {
  const FluxShell({super.key});

  @override
  ConsumerState<FluxShell> createState() => _FluxShellState();
}

class _FluxShellState extends ConsumerState<FluxShell> {
  @override
  Widget build(BuildContext context) {
    final index = ref.watch(shellTabProvider);
    final palette = context.flux;

    return ColoredBox(
      color: palette.background,
      child: Stack(
        children: [
          // Tabs are kept alive rather than rebuilt: switching away from a
          // half-scrolled ledger and back to find it at the top is the kind of
          // small betrayal that makes an app feel cheap.
          Positioned.fill(
            child: _TabSwitcher(
              index: index,
              children: const [HomePage(), ActivityPage(), AskPage()],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FluxNavBar(
              index: index,
              onChanged: (value) {
                if (value == index) return;
                ref.read(shellTabProvider.notifier).state = value;
              },
              items: const [
                FluxNavItem(
                  icon: Icons.donut_small_outlined,
                  activeIcon: Icons.donut_small_rounded,
                  label: 'Home',
                ),
                FluxNavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long_rounded,
                  label: 'Activity',
                ),
                FluxNavItem(
                  icon: Icons.auto_awesome_outlined,
                  activeIcon: Icons.auto_awesome_rounded,
                  label: 'Ask',
                  gradient: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Slides between tabs on the shared axis, keeping every tab's state alive
/// underneath.
///
/// Deliberately a slide with no fade. An opacity layer here composites badly
/// with the tab bar's BackdropFilter underneath it: the blur re-samples the
/// faded content and every tab switch left the whole app 7.5% darker than the
/// one before, permanently. Transform-based motion allocates no save layer and
/// has no such interaction.
class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final reduced = FluxMotion.reduced(context);
    return Stack(
      children: [
        for (var slot = 0; slot < children.length; slot++)
          Offstage(
            offstage: slot != index,
            child: TickerMode(
              enabled: slot == index,
              child: reduced
                  ? children[slot]
                  : _Entering(active: slot == index, child: children[slot]),
            ),
          ),
      ],
    );
  }
}

class _Entering extends StatefulWidget {
  const _Entering({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_Entering> createState() => _EnteringState();
}

class _EnteringState extends State<_Entering>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FluxMotion.normal,
    value: widget.active ? 1 : 0,
  );

  @override
  void didUpdateWidget(_Entering oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.forward();
    } else {
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween(begin: const Offset(0, 0.014), end: Offset.zero).animate(
        CurvedAnimation(parent: _controller, curve: FluxMotion.emphasized),
      ),
      child: widget.child,
    );
  }
}
