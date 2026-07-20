import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/conversation.dart';
import '../../domain/transaction.dart';
import '../sheets/connect_intelligence_sheet.dart';
import '../chat/flow_answer_view.dart';
import '../sheets/category_sheet.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';
import 'transaction_detail_screen.dart';

/// The conversation, opened over whatever screen asked for it.
///
/// Chat is brought to the current context rather than navigated to, so this
/// renders inside the sheet the composer opens. Everything an answer cites
/// is a live route into the record itself: evidence rows push the
/// transaction detail over this sheet and pop back into the thread.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _question = TextEditingController();
  final _scroll = ScrollController();
  bool _openedAtLatest = false;

  /// Messages present when the sheet opened. Only answers that arrive after
  /// this animate in: replaying an entrance on history reads as a glitch.
  int? _openingCount;

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest content in view without fighting someone who has
  /// deliberately scrolled up. [force] is for the moment a question is sent,
  /// which is always an intent to move on.
  void _stickToLatest({bool force = false}) {
    if (!_scroll.hasClients) return;
    if (!force) {
      final position = _scroll.position;
      if (position.maxScrollExtent - position.pixels > 240) return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if ((_scroll.position.pixels - target).abs() < 2) return;
      // Streaming lands continuously; an animation would restart on every
      // token and never settle. Jump while streaming, glide on send.
      if (force) {
        _scroll.animateTo(
          target,
          duration: FlowMotion.standard,
          curve: FlowMotion.enter,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appControllerProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before == null || after == null) return;
      if (after.conversation.length != before.conversation.length) {
        _stickToLatest(force: true);
      } else if (after.askDraft != before.askDraft ||
          after.askStage != before.askStage ||
          after.asking != before.asking) {
        _stickToLatest();
      }
    });

    final app = ref.watch(appControllerProvider).requireValue;
    final flow = context.flow;
    _openingCount ??= app.conversation.length;
    if (!_openedAtLatest && app.conversation.isNotEmpty) {
      _openedAtLatest = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    final connected = app.aiConnection == AiConnection.connected;
    final proposal = app.pendingAgentProposal;
    final showStatus = app.asking || app.error != null;

    return Column(
      children: [
        const SizedBox(height: FlowSpace.sm),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: flow.line,
            borderRadius: FlowRadius.pill,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FlowSpace.xl,
            FlowSpace.sm,
            FlowSpace.md,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Ask',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              if (app.conversation.isNotEmpty)
                IconButton(
                  tooltip: 'New chat',
                  onPressed: () {
                    ref.read(appControllerProvider.notifier).startNewChat();
                    setState(() {
                      _openedAtLatest = false;
                      _openingCount = 0;
                    });
                  },
                  icon: const Icon(Icons.edit_square, size: 20),
                  color: flow.inkSoft,
                ),
              if (app.threads.isNotEmpty)
                IconButton(
                  tooltip: 'Chat history',
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history_rounded),
                  color: flow.inkSoft,
                ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: app.conversation.isEmpty && !showStatus
                  ? _EmptyChat(app: app, connected: connected, onAsk: _ask)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(
                        FlowSpace.xl,
                        FlowSpace.md,
                        FlowSpace.xl,
                        FlowSpace.lg,
                      ),
                      itemCount:
                          app.conversation.length +
                          (proposal != null ? 1 : 0) +
                          (showStatus ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index < app.conversation.length) {
                          final message = app.conversation[index];
                          return _MessageView(
                            key: ValueKey(message.id ?? index),
                            message: message,
                            transactions: app.transactions,
                            animate:
                                message.author == MessageAuthor.assistant &&
                                index >= (_openingCount ?? 0),
                            precedingQuestion:
                                index > 0 &&
                                    app.conversation[index - 1].author ==
                                        MessageAuthor.person
                                ? app.conversation[index - 1].text
                                : null,
                            onFollowUp: _ask,
                            onTransaction: _openTransaction,
                            onRecategorise: _recategorise,
                            onToggleReview: _toggleReview,
                          );
                        }
                        var slot = index - app.conversation.length;
                        if (proposal != null) {
                          if (slot == 0) {
                            return _ApprovalCard(
                              title: proposal.title,
                              explanation: proposal.explanation,
                              reversible: proposal.reversible,
                              locked: proposal.requiresAuthentication,
                              expiresAt: proposal.expiresAt,
                              onApprove: () => ref
                                  .read(appControllerProvider.notifier)
                                  .approveAgentProposal(),
                              onReject: () => ref
                                  .read(appControllerProvider.notifier)
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
                    ),
            ),
          ),
        ),
        if (app.lastAgentAction != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FlowSpace.xl,
              0,
              FlowSpace.md,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${app.lastAgentAction} was applied.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                  ),
                ),
                TextButton(
                  onPressed: () => ref
                      .read(appControllerProvider.notifier)
                      .undoLastAgentAction(),
                  child: const Text('Undo'),
                ),
              ],
            ),
          ),
        _Composer(
          controller: _question,
          connected: connected,
          busy: app.asking,
          onSubmit: _ask,
          onConnect: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: (sheet) => const ConnectIntelligenceSheet(),
          ),
        ),
      ],
    );
  }

  void _ask(String value) {
    if (value.trim().isEmpty) return;
    _question.clear();
    ref.read(appControllerProvider.notifier).ask(value);
  }

  /// Evidence opens the record itself — the same route every other surface
  /// uses — over this sheet, and the back gesture returns to the thread.
  void _openTransaction(MoneyTransaction item) {
    if (item.id != null) TransactionDetailScreen.open(context, item.id!);
  }

  Future<void> _recategorise(MoneyTransaction item) async {
    final choice = await pickCategory(
      context,
      title: 'Category for ${item.merchant}',
      current: item.category,
    );
    if (choice == null || !mounted) return;
    await ref
        .read(appControllerProvider.notifier)
        .saveTransaction(
          item.copyWith(
            category: choice,
            reviewState: ReviewState.confirmed,
            confidence: 1,
          ),
        );
  }

  Future<void> _toggleReview(MoneyTransaction item) async {
    final controller = ref.read(appControllerProvider.notifier);
    if (item.reviewState == ReviewState.needsReview) {
      await controller.confirmTransaction(item);
    } else {
      await controller.saveTransaction(
        item.copyWith(reviewState: ReviewState.needsReview),
      );
    }
  }

  Future<void> _openHistory() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (context, controller) => _HistorySheet(
        scroll: controller,
        onOpened: () {
          setState(() {
            _openedAtLatest = false;
            _openingCount = null;
          });
          if (sheet.mounted) Navigator.pop(sheet);
        },
      ),
    ),
  );
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.message,
    required this.transactions,
    required this.animate,
    required this.onFollowUp,
    required this.onTransaction,
    required this.onRecategorise,
    required this.onToggleReview,
    this.precedingQuestion,
  });

  final ConversationMessage message;
  final List<MoneyTransaction> transactions;
  final bool animate;
  final String? precedingQuestion;
  final ValueChanged<String> onFollowUp;
  final ValueChanged<MoneyTransaction> onTransaction;
  final ValueChanged<MoneyTransaction> onRecategorise;
  final ValueChanged<MoneyTransaction> onToggleReview;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    if (message.author == MessageAuthor.person) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(
            top: FlowSpace.md,
            bottom: FlowSpace.lg,
            left: FlowSpace.huge,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpace.lg,
            vertical: FlowSpace.md,
          ),
          decoration: BoxDecoration(
            color: flow.raised,
            borderRadius: FlowRadius.md,
            border: Border.all(color: flow.line),
          ),
          child: Text(
            message.text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: FlowSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.parts.isNotEmpty)
            FlowAnswerView(
              parts: message.parts,
              transactions: transactions,
              animate: animate,
              onFollowUp: onFollowUp,
              onTransaction: onTransaction,
              onRecategorise: onRecategorise,
              onToggleReview: onToggleReview,
            )
          else
            Text(message.text, style: Theme.of(context).textTheme.bodyLarge),
          _MessageFooter(
            message: message,
            precedingQuestion: precedingQuestion,
            onFollowUp: onFollowUp,
          ),
        ],
      ),
    );
  }
}

/// The quiet line under a finished answer: verification when it applies,
/// and the two occasionally useful actions at low contrast.
class _MessageFooter extends StatelessWidget {
  const _MessageFooter({
    required this.message,
    required this.precedingQuestion,
    required this.onFollowUp,
  });

  final ConversationMessage message;
  final String? precedingQuestion;
  final ValueChanged<String> onFollowUp;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = message.providerContent.trim();
    return Padding(
      padding: const EdgeInsets.only(top: FlowSpace.xs),
      child: Row(
        children: [
          if (message.verified) ...[
            Icon(
              Icons.check_circle_outline_rounded,
              size: 15,
              color: flow.income,
            ),
            const SizedBox(width: FlowSpace.xs + 2),
            Expanded(
              child: Text(
                message.supportingTransactionIds.length == 1
                    ? 'Checked against 1 local transaction'
                    : 'Checked against '
                          '${message.supportingTransactionIds.length} '
                          'local transactions',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
              ),
            ),
          ] else
            const Spacer(),
          if (text.isNotEmpty)
            IconButton(
              tooltip: 'Copy answer',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: flow.inkFaint,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Answer copied')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded),
            ),
          if (precedingQuestion != null)
            IconButton(
              tooltip: 'Ask again',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              color: flow.inkFaint,
              onPressed: () => onFollowUp(precedingQuestion!),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }
}

class _WorkingOrError extends StatelessWidget {
  const _WorkingOrError({required this.app, required this.onStop});
  final AppState app;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final failed = app.error != null;
    final draft = failed ? null : app.askDraft?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlowSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (failed)
                Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: flow.attention,
                )
              else
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: flow.accent,
                  ),
                ),
              const SizedBox(width: FlowSpace.md),
              Expanded(
                child: Text(
                  app.error ?? app.askStage ?? 'Working',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (app.asking)
                TextButton(onPressed: onStop, child: const Text('Stop')),
            ],
          ),
          // The draft is the answer being written; it streams here and is
          // replaced by the structured parts the moment they land.
          if (draft != null && draft.isNotEmpty) ...[
            const SizedBox(height: FlowSpace.md),
            Text(
              draft,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: flow.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.title,
    required this.explanation,
    required this.reversible,
    required this.locked,
    required this.expiresAt,
    required this.onApprove,
    required this.onReject,
  });

  final String title;
  final String explanation;
  final bool reversible;
  final bool locked;
  final DateTime expiresAt;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    // An expired proposal cannot be applied, so offering Approve only earns
    // the person a tap and a refusal.
    final expired = !DateTime.now().isBefore(expiresAt);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: FlowSpace.lg),
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: flow.raised,
        borderRadius: FlowRadius.md,
        border: Border.all(color: flow.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                locked
                    ? Icons.lock_outline_rounded
                    : Icons.pending_actions_rounded,
                size: 16,
                color: flow.accent,
              ),
              const SizedBox(width: FlowSpace.sm),
              Text(
                expired ? 'This proposal expired' : 'Needs your approval',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: flow.accent),
              ),
            ],
          ),
          const SizedBox(height: FlowSpace.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: FlowSpace.xs),
          Text(
            explanation,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
          ),
          if (reversible && !expired) ...[
            const SizedBox(height: FlowSpace.xs),
            Text(
              'This can be undone.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: flow.inkFaint),
            ),
          ],
          const SizedBox(height: FlowSpace.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(
                      FlowDensity.minimumTarget,
                    ),
                    side: BorderSide(color: flow.line),
                    foregroundColor: flow.inkSoft,
                    shape: const RoundedRectangleBorder(
                      borderRadius: FlowRadius.sm,
                    ),
                  ),
                  child: Text(expired ? 'Dismiss' : 'Not now'),
                ),
              ),
              if (!expired) ...[
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: onApprove,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        FlowDensity.minimumTarget,
                      ),
                      backgroundColor: flow.accent,
                      foregroundColor: flow.onAccent,
                      shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadius.sm,
                      ),
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.connected,
    required this.busy,
    required this.onSubmit,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool connected;
  final bool busy;
  final ValueChanged<String> onSubmit;
  final VoidCallback onConnect;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    if (!widget.connected) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          FlowSpace.xl,
          FlowSpace.sm,
          FlowSpace.xl,
          FlowSpace.lg + MediaQuery.paddingOf(context).bottom,
        ),
        child: FilledButton.icon(
          onPressed: widget.onConnect,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(FlowDensity.minimumTarget),
            backgroundColor: flow.accent,
            foregroundColor: flow.onAccent,
            shape: const RoundedRectangleBorder(borderRadius: FlowRadius.sm),
          ),
          icon: const Icon(Icons.auto_awesome_outlined, size: 18),
          label: const Text('Connect intelligence to ask'),
        ),
      );
    }
    final hasText = widget.controller.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FlowSpace.lg,
        FlowSpace.sm,
        FlowSpace.lg,
        FlowSpace.md + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: widget.busy ? null : widget.onSubmit,
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: widget.busy ? 'Answering…' : 'Ask about your money',
                hintStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: flow.inkFaint),
                isDense: true,
                filled: true,
                fillColor: flow.sunken,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: FlowSpace.lg,
                  vertical: FlowSpace.md,
                ),
                border: const OutlineInputBorder(
                  borderRadius: FlowRadius.lg,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: FlowSpace.sm),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: widget.busy || !hasText
                ? null
                : () => widget.onSubmit(widget.controller.text),
            style: IconButton.styleFrom(
              backgroundColor: flow.accent,
              foregroundColor: flow.onAccent,
              disabledBackgroundColor: flow.sunken,
              disabledForegroundColor: flow.inkFaint,
              minimumSize: const Size.square(FlowDensity.minimumTarget),
            ),
            icon: const Icon(Icons.arrow_upward_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({
    required this.app,
    required this.connected,
    required this.onAsk,
  });

  final AppState app;
  final bool connected;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    if (!connected) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_outlined, size: 28, color: flow.accent),
              const SizedBox(height: FlowSpace.lg),
              Text(
                'Ask anything about your money.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: FlowSpace.sm),
              Text(
                'Connect a provider to answer questions in your own words, '
                'grounded in your own records.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: flow.inkSoft),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        FlowSpace.xl,
        FlowSpace.lg,
        FlowSpace.xl,
        FlowSpace.lg,
      ),
      children: [
        Text(
          'What would you like to understand?',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: FlowSpace.sm),
        Text(
          'Answers come from your own records and cite the transactions '
          'they rest on.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: flow.inkSoft),
        ),
        const SizedBox(height: FlowSpace.xl),
        for (final prompt in _suggestions(app))
          InkWell(
            onTap: () => onAsk(prompt),
            borderRadius: FlowRadius.sm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FlowSpace.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      prompt,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 17,
                    color: flow.inkFaint,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Openers drawn from the records actually present: naming the category
  /// someone actually spends in shows the app has already read their data,
  /// which is the claim this screen is making.
  static List<String> _suggestions(AppState app) {
    final now = DateTime.now();
    final month = app.transactions.where(
      (item) =>
          item.direction == TransactionDirection.outgoing &&
          item.occurredAt.year == now.year &&
          item.occurredAt.month == now.month,
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
        .where((item) => item.reviewState == ReviewState.needsReview)
        .length;
    return [
      'Give me my complete financial briefing',
      if (leading != null) 'Why is $leading my biggest category?',
      if (review > 0) 'Show the $review transactions needing review',
      'What changed from last month?',
      'Are there any unusual transactions?',
    ].take(4).toList();
  }
}

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.scroll, required this.onOpened});
  final ScrollController scroll;
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final flow = context.flow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FlowSpace.xl,
            FlowSpace.lg,
            FlowSpace.xl,
            FlowSpace.sm,
          ),
          child: Text(
            'Chat history',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: app.threads.length,
            itemBuilder: (context, index) {
              final thread = app.threads[index];
              return InkWell(
                onTap: () async {
                  await ref
                      .read(appControllerProvider.notifier)
                      .openConversationThread(thread.id);
                  onOpened();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FlowSpace.xl,
                    vertical: FlowSpace.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              thread.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if ((thread.preview ?? '').isNotEmpty)
                              Text(
                                thread.preview!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: flow.inkFaint),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Delete chat',
                        iconSize: 18,
                        color: flow.inkFaint,
                        onPressed: () => ref
                            .read(appControllerProvider.notifier)
                            .deleteConversationThread(thread.id),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
