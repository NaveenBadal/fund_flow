import 'package:flutter/material.dart' show Icons, SelectionArea;
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
import 'answer_actions.dart';
import 'answer_parts.dart';
import 'composer.dart';
import 'proposal_card.dart';
import 'suggestions.dart';
import 'threads_page.dart';
import 'trace.dart';

/// Ask: the agent, its thread, and the one composer.
class AskPage extends ConsumerStatefulWidget {
  const AskPage({super.key});

  @override
  ConsumerState<AskPage> createState() => _AskPageState();
}

class _AskPageState extends ConsumerState<AskPage> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  /// The newest turn, so it can be brought to the top of the screen rather
  /// than the bottom.
  final _latest = GlobalKey();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send(String question) {
    ref.read(appControllerProvider.notifier).ask(question);
    // Scroll after the frame that adds the message, not before it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest());
  }

  /// Puts the newest turn at the top of the viewport.
  ///
  /// Scrolling to the very bottom instead — which is what a chat app does, and
  /// what this did — lands on the end of the answer. For a breakdown of twelve
  /// categories that means opening on the source note, with the sentence that
  /// actually answered the question somewhere above the fold. Every answer here
  /// is written conclusion-first, so the top of it is the part to show.
  void _toLatest() {
    final target = _latest.currentContext;
    if (target == null) return _toBottom();
    Scrollable.ensureVisible(
      target,
      alignment: 0,
      duration: FluxMotion.normal,
      curve: FluxMotion.emphasized,
    );
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: FluxMotion.normal,
      curve: FluxMotion.emphasized,
    );
  }

  /// Puts a question back in the composer to be reworded.
  ///
  /// An answer that missed usually missed because the question was ambiguous,
  /// and retyping thirty words to change two of them is the moment people give
  /// up on asking.
  void _edit(String question) {
    _composer.text = question;
    _composer.selection = TextSelection.collapsed(offset: question.length);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).value;
    final snapshot = ref.watch(homeSnapshotProvider);

    // Follow the conversation as it grows. Scrolling in `_send` fires before the
    // answer exists, so an instant local answer landed below the fold and looked
    // like nothing had happened.
    ref.listen<int>(
      appControllerProvider.select(
        (value) => value.value?.conversation.length ?? 0,
      ),
      (previous, next) {
        if (next > (previous ?? 0)) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _toLatest());
        }
      },
    );

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
    final anchorIndex = messages.lastIndexWhere(
      (message) => message.author == MessageAuthor.person,
    );

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
                          'Everyday questions — totals, categories, comparisons '
                          '— are answered on this device without one. Connect a '
                          'provider for anything more open-ended.',
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
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      // The question that produced an answer is the one above
                      // it, and only if it is actually a question — a thread
                      // reloaded mid-run can end on an answer with no pair.
                      final previous = index == 0 ? null : messages[index - 1];
                      final question =
                          previous != null &&
                              previous.author == MessageAuthor.person
                          ? previous.text
                          : null;
                      final view = _MessageView(
                        // The anchor is the newest question, not the newest
                        // message: keeping it pinned at the top means the
                        // answer arrives underneath it with nothing jumping,
                        // and the question stays on screen as the context for
                        // what is being read.
                        key: index == anchorIndex ? _latest : null,
                        message: message,
                        question: question,
                        onFollowUp: _send,
                        onEdit: _edit,
                      );
                      if (index != messages.length - 1) return view;
                      // The approval card, the applied receipt and a failure
                      // all belong to the turn that produced them. Held in
                      // their own slivers below the list they detached from it
                      // the moment anyone scrolled, leaving an approval
                      // floating with no visible question attached.
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          view,
                          if (app?.pendingAgentProposal case final proposal?)
                            Padding(
                              padding: const EdgeInsets.only(top: FluxSpace.x5),
                              child: ProposalCard(proposal: proposal),
                            ),
                          if (app?.lastAgentAction case final summary?)
                            Padding(
                              padding: const EdgeInsets.only(top: FluxSpace.x4),
                              child: AppliedCard(
                                summary: summary,
                                canUndo: app?.lastAgentUndoId != null,
                              ),
                            ),
                          if (app?.error case final error?)
                            Padding(
                              padding: const EdgeInsets.only(top: FluxSpace.x5),
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
                      );
                    },
                  ),
                ),

              if (asking)
                FluxSliverPadding(
                  top: FluxSpace.x6,
                  child: WorkingIndicator(
                    stage: app?.askStage ?? 'Working',
                    draft: app?.askDraft,
                    parts: app?.askParts ?? const [],
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
        // Nothing goes between the composer and the tab bar: the shell paints
        // its glass nav bar over this whole strip, above this page in the
        // stack. The filler that used to sit here was fully transparent and
        // painted nothing, and an opaque one would have blocked the blur.
      ],
    );
  }
}

/// One turn in the thread.
class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.message,
    required this.question,
    required this.onFollowUp,
    required this.onEdit,
  });
  final ConversationMessage message;

  /// The question this answer came from, for asking it again.
  final String? question;
  final ValueChanged<String> onFollowUp;
  final ValueChanged<String> onEdit;

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
          child: Semantics(
            button: true,
            label: '${message.text}. Edit this question',
            excludeSemantics: true,
            child: FluxPressable(
              // Tapping a question puts it back in the composer. An answer
              // that missed usually missed on a word or two of the question,
              // and retyping the whole thing to change them is where people
              // stop asking.
              onTap: () => onEdit(message.text),
              borderRadius: BorderRadius.circular(FluxRadius.md),
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
          ),
        ),
      );
    }

    final parts = message.parts;
    // Selectable, and scoped to this one answer. A figure someone wants to put
    // in a message to their bank is not reachable through the copy button,
    // which takes the whole thing.
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No parts means a message written before typed answers existed, or
          // one salvaged as plain text. It still gets its provenance line —
          // that line is where "unverified" is said, so leaving it off hid the
          // warning in exactly the case it was built for.
          if (parts.isEmpty)
            Text(
              message.text,
              style: FluxType.body.copyWith(color: palette.textMuted),
            )
          else
            for (var index = 0; index < parts.length; index++) ...[
              if (index > 0) SizedBox(height: _gapBefore(parts[index].kind)),
              AnswerPartView(part: parts[index], onFollowUp: onFollowUp),
            ],
          const SizedBox(height: FluxSpace.x3),
          AnswerTraceRow(message: message),
          const SizedBox(height: FluxSpace.x1),
          AnswerActions(
            message: message,
            question: question,
            onAskAgain: onFollowUp,
          ),
        ],
      ),
    );
  }

  /// Parts are not equally related to each other; a source note needs more air
  /// than the chart it annotates.
  static double _gapBefore(AgentPartKind kind) => switch (kind) {
    AgentPartKind.sourceNote || AgentPartKind.followUps => FluxSpace.x5,
    _ => FluxSpace.x4,
  };
}
