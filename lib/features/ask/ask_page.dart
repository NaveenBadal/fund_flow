import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_presentation.dart';
import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../../domain/conversation.dart';
import '../settings/intelligence_page.dart';
import '../shell/shell.dart';
import 'answer_parts.dart';
import 'composer.dart';
import 'proposal_card.dart';
import 'suggestions.dart';
import 'threads_page.dart';

/// Ask: the agent, its thread, and the one composer.
class AskPage extends ConsumerStatefulWidget {
  const AskPage({super.key});

  @override
  ConsumerState<AskPage> createState() => _AskPageState();
}

class _AskPageState extends ConsumerState<AskPage> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String question) {
    ref.read(appControllerProvider.notifier).ask(question);
    // Scroll after the frame that adds the message, not before it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: FluxMotion.normal,
      curve: FluxMotion.emphasized,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final snapshot = ref.watch(homeSnapshotProvider);

    // A question handed over from somewhere else in the app — an insight card, a
    // merchant page — is asked immediately. The person already tapped "ask
    // about this"; making them tap send again is a toll on their own intent.
    ref.listen<String?>(askSeedProvider, (previous, next) {
      if (next == null || next.isEmpty) return;
      ref.read(askSeedProvider.notifier).state = null;
      if (app?.asking ?? false) return;
      _send(next);
    });

    final messages = app?.conversation ?? const <ConversationMessage>[];
    final asking = app?.asking ?? false;
    final disconnected = app?.aiConnection == AiConnection.disconnected;

    return Stack(
      children: [
        Positioned.fill(
          child: FluxPage(
            title: 'Ask',
            controller: _scroll,
            bottomInset: shellBottomInset(context) + 68,
            actions: [
              if (messages.isNotEmpty)
                FluxIconButton(
                  icon: Icons.add_comment_outlined,
                  tooltip: 'New chat',
                  onPressed: () =>
                      ref.read(appControllerProvider.notifier).startNewChat(),
                ),
              FluxIconButton(
                icon: Icons.history_rounded,
                tooltip: 'Earlier chats',
                onPressed: () =>
                    fluxPush(context, (context) => const ThreadsPage()),
              ),
            ],
            slivers: [
              if (disconnected)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: FluxSpace.x2),
                    child: FluxBanner(
                      tone: FluxBannerTone.ai,
                      title: 'No provider connected',
                      message:
                          'Questions need a model to answer them. Your records '
                          'stay on the device either way.',
                      icon: Icons.link_off_rounded,
                      actionLabel: 'Connect',
                      onAction: () => fluxPush(
                        context,
                        (context) => const IntelligencePage(),
                      ),
                    ),
                  ),
                ),

              if (messages.isEmpty && !asking)
                SliverToBoxAdapter(
                  child: AskEmptyState(snapshot: snapshot, onAsk: _send),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.only(
                    left: FluxSpace.page,
                    right: FluxSpace.page,
                    top: FluxSpace.x4,
                  ),
                  sliver: SliverList.separated(
                    itemCount: messages.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: FluxSpace.x6),
                    itemBuilder: (context, index) => _MessageView(
                      message: messages[index],
                      onFollowUp: _send,
                    ),
                  ),
                ),

              if (asking)
                FluxSliverPadding(
                  top: FluxSpace.x6,
                  child: WorkingIndicator(
                    stage: app?.askStage ?? 'Working',
                    draft: app?.askDraft,
                  ),
                ),

              if (app?.pendingAgentProposal case final proposal?)
                FluxSliverPadding(
                  top: FluxSpace.x5,
                  child: ProposalCard(proposal: proposal),
                ),

              if (app?.lastAgentAction case final summary?)
                FluxSliverPadding(
                  top: FluxSpace.x4,
                  child: AppliedCard(
                    summary: summary,
                    canUndo: app?.lastAgentUndoId != null,
                  ),
                ),

              if (app?.error case final error?)
                FluxSliverPadding(
                  top: FluxSpace.x5,
                  child: FluxBanner(
                    tone: FluxBannerTone.danger,
                    message: error,
                    icon: Icons.error_outline_rounded,
                    actionLabel: app?.retryQuestion == null
                        ? null
                        : 'Ask again',
                    onAction: app?.retryQuestion == null
                        ? null
                        : () => _send(app!.retryQuestion!),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom:
              shellBottomInset(context) - MediaQuery.paddingOf(context).bottom,
          child: AskComposer(
            controller: _composer,
            busy: asking,
            onSend: _send,
            onStop: () => ref.read(appControllerProvider.notifier).stopAgent(),
          ),
        ),
        // The composer sits above the tab bar, so the strip between them has to
        // be filled or content scrolls through the gap.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height:
              shellBottomInset(context) - MediaQuery.paddingOf(context).bottom,
          child: IgnorePointer(
            child: ColoredBox(color: palette.background.withValues(alpha: 0)),
          ),
        ),
      ],
    );
  }
}

/// One turn in the thread.
class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.onFollowUp});
  final ConversationMessage message;
  final ValueChanged<String> onFollowUp;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;

    if (message.author == MessageAuthor.person) {
      // The question is a bubble; answers are not. Only one side of this
      // conversation is speaking — the other is reporting, and boxing a
      // report in a bubble makes it look like an opinion.
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: palette.irisSoft,
              shape: FluxRadius.shape(FluxRadius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FluxSpace.x4,
                vertical: FluxSpace.x3,
              ),
              child: Text(
                message.text,
                style: FluxType.body.copyWith(color: palette.text),
              ),
            ),
          ),
        ),
      );
    }

    final parts = message.parts;
    if (parts.isEmpty) {
      return Text(
        message.text,
        style: FluxType.body.copyWith(color: palette.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < parts.length; index++) ...[
          if (index > 0) SizedBox(height: _gapBefore(parts[index].kind)),
          AnswerPartView(part: parts[index], onFollowUp: onFollowUp),
        ],
        const SizedBox(height: FluxSpace.x3),
        _TraceRow(message: message),
      ],
    );
  }

  /// Parts are not equally related to each other; a source note needs more air
  /// than the chart it annotates.
  static double _gapBefore(AgentPartKind kind) => switch (kind) {
    AgentPartKind.sourceNote || AgentPartKind.followUps => FluxSpace.x5,
    AgentPartKind.conclusion || AgentPartKind.redirect => FluxSpace.x4,
    _ => FluxSpace.x4,
  };
}

/// What the answer was built from.
///
/// Every answer carries this line. It is the difference between a figure someone
/// has to take on faith and one they can see the working for — and the
/// unverified marker is how a fallback answer that skipped the structured path
/// announces itself instead of passing as a checked result.
class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.message});
  final ConversationMessage message;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final count = message.supportingTransactionIds.length;
    final verified = message.verified;

    return Row(
      children: [
        Icon(
          verified ? Icons.verified_outlined : Icons.help_outline_rounded,
          size: 13,
          color: verified ? palette.textFaint : palette.attention,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            verified
                ? (count == 0
                      ? 'Answered from your local records'
                      : 'Checked against $count '
                            '${count == 1 ? 'record' : 'records'} on this device')
                : 'Unverified — this answer did not come back in the '
                      'app\'s checked format',
            style: FluxType.caption.copyWith(
              color: verified ? palette.textFaint : palette.attention,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}
