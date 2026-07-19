import 'package:flutter/material.dart';

import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// The composer that sits on every screen.
///
/// Chat is an input surface rather than a destination. Putting it on every
/// screen means the agent is always one tap away, which is what an AI-first
/// app should feel like, without making conversation the place you have to
/// start from. The daily questions — where do I stand, what needs attention —
/// are answered by the screen behind it.
///
/// It also carries the context of whatever is on screen, so "why is this
/// higher?" means something without the person restating what they are
/// looking at.
class FlowComposer extends StatelessWidget {
  const FlowComposer({
    super.key,
    required this.onOpen,
    this.contextHint,
    this.busy = false,
    this.enabled = true,
  });

  /// Opens the full conversation. The composer itself never accepts a
  /// keystroke: tapping hands off to the surface that can show an answer,
  /// so text is never typed somewhere it cannot be replied to.
  final VoidCallback onOpen;

  /// What the screen behind is about, shown so the person can see the agent
  /// already has the context.
  final String? contextHint;

  final bool busy;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final label = busy
        ? 'Working on your answer'
        : contextHint == null
        ? 'Ask anything about your money'
        : 'Ask about $contextHint';

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FlowSpace.lg,
          FlowSpace.sm,
          FlowSpace.lg,
          FlowSpace.sm,
        ),
        child: Material(
          color: flow.raised,
          borderRadius: FlowRadius.pill,
          child: InkWell(
            onTap: enabled ? onOpen : null,
            borderRadius: FlowRadius.pill,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: FlowSpace.lg),
              decoration: BoxDecoration(
                borderRadius: FlowRadius.pill,
                border: Border.all(color: flow.line),
              ),
              child: Row(
                children: [
                  if (busy)
                    SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: flow.accent,
                      ),
                    )
                  else
                    Icon(
                      Icons.auto_awesome_outlined,
                      size: 17,
                      color: flow.accent,
                    ),
                  const SizedBox(width: FlowSpace.md),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: enabled ? flow.inkSoft : flow.inkFaint,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_upward_rounded,
                    size: 17,
                    color: flow.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
