import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/conversation.dart';
import '../../domain/finance_summary.dart';
import '../../domain/transaction.dart';
import '../../ui/components/current_button.dart';
import '../../ui/components/current_edge_fade.dart';
import '../../ui/components/current_header.dart';
import '../../ui/foundation/current_colors.dart';
import '../../ui/format/money_format.dart';
import '../../ui/layout/chat_shell.dart';
import '../activity/activity_screen.dart';
import '../activity/transaction_editor_sheet.dart';
import '../you/connect_intelligence_sheet.dart';
import '../you/you_screen.dart';
import 'agent_answer_view.dart';
import 'ask_composer.dart';
import 'money_pulse.dart';
import 'agent_approval_card.dart';

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});
  @override
  ConsumerState<AskScreen> createState() => _State();
}

class _State extends ConsumerState<AskScreen> {
  final _question = TextEditingController();
  final _scroll = ScrollController();

  /// Set once the opening frame has been pinned to the newest message.
  bool _openedAtLatest = false;

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest content in view.
  ///
  /// A conversation reads from the bottom: the question just sent and the
  /// answer arriving after it are what matters, and starting at the top left
  /// someone scrolling to find their own message.
  ///
  /// Someone who has deliberately scrolled up to reread something is left
  /// alone, because yanking the view down mid-sentence is worse than a new
  /// answer arriving off screen. [force] overrides that for the moment a
  /// question is sent, which is always an intent to move on.
  void _stickToLatest({bool force = false}) {
    if (!_scroll.hasClients) return;
    if (!force) {
      final position = _scroll.position;
      if (position.maxScrollExtent - position.pixels > 240) return;
    }
    // Deferred: content added this frame has not been laid out yet, so
    // maxScrollExtent is still the previous value.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if ((_scroll.position.pixels - target).abs() < 2) return;
      // Streaming updates land continuously, so an animation would restart on
      // every token and never settle. Jump while streaming, glide otherwise.
      if (force) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // A new message is an intent to move on; streaming and stage changes just
    // keep the tail visible.
    ref.listen(appControllerProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (after == null) return;
      if (before == null) return;
      if (after.conversation.length != before.conversation.length) {
        _stickToLatest(force: true);
      } else if (after.askDraft != before.askDraft ||
          after.askStage != before.askStage ||
          after.asking != before.asking) {
        _stickToLatest();
      }
    });

    final app = ref.watch(appControllerProvider).requireValue;
    // Opening an existing conversation lands on the latest exchange rather
    // than the oldest one.
    if (!_openedAtLatest && app.conversation.isNotEmpty) {
      _openedAtLatest = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    final connected = app.aiConnection == AiConnection.connected;
    return Column(
      children: [
        CurrentHeader(
          title: 'Fund Flow',
          contextLine: 'Your money, made clearer',
          actions: [
            if (app.conversation.isNotEmpty)
              CurrentIconAction(
                icon: Icons.delete_sweep_outlined,
                label: 'Clear conversation',
                onPressed: () => ref
                    .read(appControllerProvider.notifier)
                    .clearConversation(),
              ),
            CurrentIconAction(
              icon: Icons.tune_rounded,
              label: 'Settings',
              onPressed: _openSettings,
            ),
          ],
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Column(
                children: [
                  // The pulse answers the unasked question. Once the person
                  // scrolls into an answer it becomes a third copy of the
                  // same figure, so it yields to the conversation.
                  AnimatedBuilder(
                    animation: _scroll,
                    builder: (context, child) {
                      final offset = _scroll.hasClients ? _scroll.offset : 0.0;
                      final t = (offset / 72).clamp(0.0, 1.0);
                      if (t == 1) return const SizedBox.shrink();
                      return Opacity(
                        opacity: 1 - t,
                        child: Align(
                          alignment: Alignment.topCenter,
                          heightFactor: 1 - t,
                          child: child,
                        ),
                      );
                    },
                    child: MoneyPulse(
                      transactions: app.transactions,
                      hideAmounts: app.preferences.hideAmounts,
                      onTap: _openActivity,
                    ),
                  ),
                  Expanded(
                    child: app.conversation.isEmpty
                        ? _EmptyAsk(
                            app: app,
                            connected: connected,
                            onAsk: _ask,
                          )
                        : CurrentEdgeFade(
                            child: Builder(
                            builder: (context) {
                              final proposal = app.pendingAgentProposal;
                              final showStatus =
                                  app.asking || app.error != null;
                              return ListView.builder(
                                controller: _scroll,
                                padding: const EdgeInsets.only(bottom: 18),
                                itemCount:
                                    app.conversation.length +
                                    (proposal != null ? 1 : 0) +
                                    (showStatus ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (i < app.conversation.length) {
                                    return _MessageView(
                                      message: app.conversation[i],
                                      transactions: app.transactions,
                                      precedingQuestion: i > 0 &&
                                              app.conversation[i - 1].author ==
                                                  MessageAuthor.person
                                          ? app.conversation[i - 1].text
                                          : null,
                                      onFollowUp: _ask,
                                      onTransaction: _showTransaction,
                                    );
                                  }
                                  var slot = i - app.conversation.length;
                                  if (proposal != null) {
                                    if (slot == 0) {
                                      return AgentApprovalCard(
                                        proposal: proposal,
                                        onApprove: () => ref
                                            .read(
                                              appControllerProvider.notifier,
                                            )
                                            .approveAgentProposal(),
                                        onReject: () => ref
                                            .read(
                                              appControllerProvider.notifier,
                                            )
                                            .rejectAgentProposal(),
                                      );
                                    }
                                    slot--;
                                  }
                                  return _WorkingOrError(
                                    app: app,
                                    onStop: () => ref
                                        .read(appControllerProvider.notifier)
                                        .stopAgent(),
                                  );
                                },
                              );
                            },
                          ),
                          ),
                  ),
                  AskComposer(
                    controller: _question,
                    connected: connected,
                    busy: app.asking,
                    onSubmit: _ask,
                    onConnect: _connect,
                  ),
                  if (app.lastAgentAction != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${app.lastAgentAction} was applied.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        CurrentButton(
                          label: 'Undo',
                          compact: true,
                          style: CurrentButtonStyle.text,
                          onPressed: () => ref
                              .read(appControllerProvider.notifier)
                              .undoLastAgentAction(),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openActivity() => ChatShell.openActivitySheet(
    context,
    (_) => const ActivityScreen(),
  );

  Future<void> _connect() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ConnectIntelligenceSheet(),
  );

  /// Settings live over the conversation rather than beside it, so adjusting
  /// something never costs the thread someone is in the middle of.
  Future<void> _openSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .5,
      maxChildSize: .96,
      builder: (context, controller) => PrimaryScrollController(
        controller: controller,
        child: const YouScreen(),
      ),
    ),
  );
  void _ask(String value) {
    if (value.trim().isEmpty) return;
    _question.clear();
    ref.read(appControllerProvider.notifier).ask(value);
  }

  /// Evidence cited in an answer opens the same editor the record uses.
  /// A transaction reached through chat is not a different kind of thing, and
  /// showing it read-only made the conversation a dead end for corrections.
  Future<void> _showTransaction(MoneyTransaction item) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => TransactionEditorSheet(transaction: item),
      );
}

class _EmptyAsk extends StatelessWidget {
  const _EmptyAsk({
    required this.app,
    required this.connected,
    required this.onAsk,
  });
  final AppState app;
  final bool connected;
  final ValueChanged<String> onAsk;
  @override
  Widget build(BuildContext context) {
    if (!connected) {
      // Centred rather than top-aligned: a short message pinned to the top
      // of a tall screen leaves a void that reads as content failing to load.
      return Center(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 30,
                color: context.current.intelligence,
              ),
              const SizedBox(height: 18),
              Text(
                'Ask anything about your money.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Connect a provider to read transaction messages and answer '
                'questions in your own words.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
              ),
              // No button here: the composer below is the single, always
              // present place to act. Two calls to action for one step read
              // as two different steps.
            ],
          ),
        ),
      );
    }
    final now = DateTime.now();
    final month = app.transactions.where(
      (e) => e.occurredAt.year == now.year && e.occurredAt.month == now.month,
    );
    final summaries = FinanceEngine.summarize(month);
    return ListView(
      children: [
        const SizedBox(height: 34),
        Text(
          summaries.isEmpty
              ? 'What would you like to understand?'
              : 'A quick look at this month',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        if (summaries.isEmpty)
          Text(
            'Check messages or add activity, then ask in your own words.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
          )
        else
          for (final value in summaries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${formatMoney(value.outgoingMinor, value.currency)} spent across '
                '${value.transactionCount} transactions.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
        const SizedBox(height: 28),
        for (final prompt in _suggestions(app))
          InkWell(
            onTap: () => onAsk(prompt),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(child: Text(prompt)),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: context.current.muted,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Openers drawn from the records actually present.
///
/// A fixed list asks the same four questions of an empty ledger and a busy
/// one. Naming the category someone actually spends in shows the app has
/// already read their data, which is the claim the screen is making.
List<String> _suggestions(AppState app) {
  final now = DateTime.now();
  final month = app.transactions.where(
    (e) =>
        e.direction == TransactionDirection.outgoing &&
        e.occurredAt.year == now.year &&
        e.occurredAt.month == now.month,
  );
  final byCategory = <String, int>{};
  for (final item in month) {
    byCategory[item.category] =
        (byCategory[item.category] ?? 0) + item.amountMinor;
  }
  final leading = byCategory.entries.isEmpty
      ? null
      : byCategory.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final review = app.transactions
      .where((e) => e.reviewState == ReviewState.needsReview)
      .length;

  return [
    'Give me my complete financial briefing',
    if (leading != null) 'Why is $leading my biggest category?',
    if (review > 0) 'Show the $review transactions needing review',
    'What changed from last month?',
    'Are there any unusual transactions?',
  ].take(4).toList();
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.message,
    required this.transactions,
    required this.onFollowUp,
    required this.onTransaction,
    this.precedingQuestion,
  });
  final ConversationMessage message;

  /// The question this answer replied to, so it can be asked again.
  final String? precedingQuestion;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onFollowUp;
  final ValueChanged<MoneyTransaction> onTransaction;
  @override
  Widget build(BuildContext context) {
    if (message.author == MessageAuthor.person) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, bottom: 18, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: context.current.subtle,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(15),
            ),
          ),
          child: Text(message.text),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.parts.isNotEmpty)
            AgentAnswerView(
              parts: message.parts,
              transactions: transactions,
              onFollowUp: onFollowUp,
              onTransaction: onTransaction,
            )
          else
            Text(message.text, style: Theme.of(context).textTheme.bodyLarge),
          if (message.author == MessageAuthor.assistant)
            _MessageActions(
              message: message,
              precedingQuestion: precedingQuestion,
              onFollowUp: onFollowUp,
            ),
          if (message.verified) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 16,
                  color: context.current.income,
                ),
                const SizedBox(width: 6),
                Text(
                  // Counts the records cited as evidence, not everything the
                  // answer examined. The source note states the full scope,
                  // and the two must not appear to disagree.
                  message.supportingTransactionIds.length == 1
                      ? 'Checked against 1 local transaction'
                      : 'Checked against '
                            '${message.supportingTransactionIds.length} '
                            'local transactions',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.current.muted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Actions on a finished answer.
///
/// Kept quiet until the answer is complete and shown as low-contrast icons:
/// they are occasionally useful and should not compete with the figures.
class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.message,
    required this.precedingQuestion,
    required this.onFollowUp,
  });
  final ConversationMessage message;
  final String? precedingQuestion;
  final ValueChanged<String> onFollowUp;

  @override
  Widget build(BuildContext context) {
    // providerContent carries the figures too, so a copied answer is not
    // reduced to its prose.
    final text = message.providerContent.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          _MessageAction(
            icon: Icons.copy_rounded,
            label: 'Copy answer',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Answer copied')),
                );
              }
            },
          ),
          // Offered only when the original question is known: re-sending the
          // answer as a question would be nonsense.
          if (precedingQuestion != null) ...[
            const SizedBox(width: 4),
            _MessageAction(
              icon: Icons.refresh_rounded,
              label: 'Ask again',
              onPressed: () => onFollowUp(precedingQuestion!),
            ),
          ],
        ],
      ),
    );
  }

}

class _MessageAction extends StatelessWidget {
  const _MessageAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: label,
    visualDensity: VisualDensity.compact,
    iconSize: 17,
    color: context.current.muted,
    icon: Icon(icon),
  );
}

class _WorkingOrError extends StatelessWidget {
  const _WorkingOrError({required this.app, required this.onStop});
  final AppState app;
  final VoidCallback onStop;
  @override
  Widget build(BuildContext context) {
    final draft = app.error == null ? app.askDraft?.trim() : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                app.error == null
                    ? Icons.manage_search_rounded
                    : Icons.error_outline_rounded,
                color: app.error == null
                    ? context.current.intelligence
                    : context.current.review,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(app.error ?? app.askStage ?? 'Working')),
              if (app.asking)
                CurrentButton(
                  label: 'Stop',
                  compact: true,
                  style: CurrentButtonStyle.text,
                  onPressed: onStop,
                ),
            ],
          ),
          if (draft != null && draft.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              draft,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.current.muted),
            ),
          ],
        ],
      ),
    );
  }
}
