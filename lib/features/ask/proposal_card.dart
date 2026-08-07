import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_proposal.dart';
import '../../app/app_controller.dart';
import '../../design/flux.dart';

/// The approval card.
///
/// The agent never changes anything; it prepares a change and this card is the
/// only thing that can apply it. Two rules make that meaningful:
///
/// * The card shows the change itself, in the app's own words, from
///   [AgentProposal.details] — not a summary the model wrote. A card reading
///   "Add a transaction" asks someone to approve something they cannot see, and
///   the model once proposed forty dollars as forty cents.
/// * Approval re-checks that the affected records still look as they did when
///   the proposal was made, so an edit made in between refuses rather than
///   silently overwriting something else.
class ProposalCard extends ConsumerStatefulWidget {
  const ProposalCard({super.key, required this.proposal});
  final AgentProposal proposal;

  @override
  ConsumerState<ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends ConsumerState<ProposalCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // A change waiting on you is worth a tap on the wrist.
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final proposal = widget.proposal;
    final controller = ref.read(appControllerProvider.notifier);

    return _Entrance(
      child: FluxCard(
        raised: true,
        border: palette.iris.withValues(alpha: 0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 17, color: palette.iris),
                const SizedBox(width: FluxSpace.x2),
                Expanded(
                  child: Text(
                    'NEEDS YOUR APPROVAL',
                    style: FluxType.overline.copyWith(color: palette.iris),
                  ),
                ),
                if (!proposal.reversible)
                  Text(
                    'Cannot be undone',
                    style: FluxType.caption.copyWith(color: palette.attention),
                  ),
              ],
            ),
            const SizedBox(height: FluxSpace.x3),
            Text(
              proposal.title,
              style: FluxType.subtitle.copyWith(color: palette.text),
            ),
            if (proposal.details.isNotEmpty) ...[
              const SizedBox(height: FluxSpace.x3),
              Container(
                decoration: ShapeDecoration(
                  color: palette.isDark
                      ? palette.background
                      : palette.surfaceHighest,
                  shape: FluxRadius.shape(FluxRadius.xs),
                ),
                padding: const EdgeInsets.all(FluxSpace.x3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final line in proposal.details)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          line,
                          style: FluxType.caption.copyWith(
                            color: palette.text,
                            height: 1.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (proposal.requiresAuthentication) ...[
              const SizedBox(height: FluxSpace.x3),
              Row(
                children: [
                  Icon(
                    Icons.fingerprint_rounded,
                    size: 15,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: FluxSpace.x2),
                  Text(
                    'Asks for your device unlock',
                    style: FluxType.caption.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ],
            const SizedBox(height: FluxSpace.x4),
            Row(
              children: [
                Expanded(
                  child: FluxButton(
                    label: 'Approve',
                    busy: _busy,
                    onPressed: () async {
                      setState(() => _busy = true);
                      await controller.approveAgentProposal();
                      if (mounted) setState(() => _busy = false);
                    },
                  ),
                ),
                const SizedBox(width: FluxSpace.x3),
                Expanded(
                  child: FluxButton(
                    label: 'Dismiss',
                    kind: FluxButtonKind.secondary,
                    onPressed: _busy
                        ? null
                        : () => controller.rejectAgentProposal(),
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

/// What an applied change looks like afterwards, with undo attached.
///
/// The undo lives on the card rather than only in a snackbar: a snackbar that
/// has scrolled away or timed out leaves someone with a change they did not
/// want and no way back that they can find.
class AppliedCard extends ConsumerWidget {
  const AppliedCard({super.key, required this.summary, required this.canUndo});
  final String summary;
  final bool canUndo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    return FluxCard(
      color: palette.isDark ? palette.surfaceRaised : palette.surfaceHighest,
      radius: FluxRadius.sm,
      padding: const EdgeInsets.symmetric(
        horizontal: FluxSpace.x4,
        vertical: FluxSpace.x3,
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 16, color: palette.income),
          const SizedBox(width: FluxSpace.x2),
          Expanded(
            child: Text(
              summary,
              style: FluxType.caption.copyWith(color: palette.text),
            ),
          ),
          if (canUndo)
            FluxPressable(
              onTap: () => ref
                  .read(appControllerProvider.notifier)
                  .undoLastAgentAction(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FluxSpace.x2,
                  vertical: FluxSpace.x1,
                ),
                child: Text(
                  'Undo',
                  style: FluxType.label.copyWith(color: palette.iris),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Entrance extends StatefulWidget {
  const _Entrance({required this.child});
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FluxMotion.large,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (FluxMotion.reduced(context)) return widget.child;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: FluxMotion.overshoot,
    );
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: FluxMotion.emphasized,
      ),
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(curved),
        child: widget.child,
      ),
    );
  }
}
