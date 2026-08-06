import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../agent/agent_presentation.dart';
import '../../agent/agent_proposal.dart';
import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/conversation.dart';
import '../../domain/money_format.dart';
import '../../domain/transaction.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_controls.dart';
import '../widgets/ff_group.dart';
import '../widgets/ff_notice.dart';
import '../widgets/ff_pressable.dart';
import '../widgets/ff_screen.dart';
import '../widgets/ff_sheet.dart';
import '../widgets/ff_transaction_row.dart';
import 'settings/intelligence.dart';
import 'shell.dart';
import 'transaction_detail.dart';

/// A question waiting to be asked on the Ask tab.
///
/// Set from anywhere — a transaction, an insight — so "ask about this" takes
/// someone to the conversation they already have rather than opening a second
/// one on top of it.
class AskSeed extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final askSeedProvider = NotifierProvider<AskSeed, String?>(AskSeed.new);

/// Send [seed] on the Ask tab, from wherever the person currently is.
void openAsk(BuildContext context, WidgetRef ref, {String? seed}) {
  ref.read(askSeedProvider.notifier).set(seed);
  ref.read(shellTabProvider.notifier).set(2);
  Navigator.of(context).popUntil((route) => route.isFirst);
}

/// The conversation.
///
/// Answers are documents, not chat bubbles: a conclusion, the figures behind
/// it, the transactions it rests on. Only the question is bubbled, because
/// only the question was said by a person.
class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});

  @override
  ConsumerState<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends ConsumerState<AskScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String value) async {
    final question = value.trim();
    if (question.isEmpty) return;
    _input.clear();
    FocusScope.of(context).unfocus();
    setState(() {});
    _toBottom();
    await ref.read(appControllerProvider.notifier).ask(question);
    _toBottom();
  }

  void _toBottom() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Duration(milliseconds: context.ffStill ? 0 : 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final connected = app.aiConnection == AiConnection.connected;
    final busy = app.asking;

    // A seed set by another screen is consumed once, after this frame, so the
    // tab is already on screen when the answer starts arriving.
    ref.listen<String?>(askSeedProvider, (_, seed) {
      if (seed == null || seed.isEmpty) return;
      ref.read(askSeedProvider.notifier).set(null);
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(seed));
    });

    final empty = app.conversation.isEmpty && !busy && app.error == null;

    return FFScreen(
      title: 'Ask',
      controller: _scroll,
      // Room for the composer, which floats over the content rather than
      // stealing a strip of it.
      extraBottom: 74,
      trailing: [
        if (app.threads.isNotEmpty)
          FFBarButton(
            icon: Icons.history_rounded,
            tooltip: 'Past conversations',
            onTap: () => _history(app),
          ),
        if (app.conversation.isNotEmpty)
          FFBarButton(
            icon: Icons.add_circle_outline_rounded,
            tooltip: 'New conversation',
            onTap: ref.read(appControllerProvider.notifier).startNewChat,
          ),
      ],
      slivers: [
        if (!connected)
          SliverToBoxAdapter(
            child: FFNotice(
              icon: Icons.link_rounded,
              title: 'No model connected',
              message:
                  'Answers are written by a provider you choose. Your '
                  'transactions stay on this device.',
              action: 'Connect a provider',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const IntelligenceScreen(),
                ),
              ),
            ),
          ),
        if (empty)
          SliverToBoxAdapter(child: _Suggestions(onAsk: _ask))
        else
          SliverList.builder(
            itemCount: app.conversation.length,
            itemBuilder: (context, index) => _Turn(
              message: app.conversation[index],
              transactions: app.transactions,
              onAsk: _ask,
            ),
          ),
        if (busy || app.error != null)
          SliverToBoxAdapter(
            child: _Progress(
              app: app,
              onRetry: app.retryQuestion == null
                  ? null
                  : () => _ask(app.retryQuestion!),
            ),
          ),
        if (app.pendingAgentProposal case final proposal?)
          SliverToBoxAdapter(child: _Proposal(proposal: proposal)),
        if (app.lastAgentAction case final action?)
          SliverToBoxAdapter(
            child: _Outcome(
              message: action,
              canUndo: app.lastAgentUndoId != null,
            ),
          ),
      ],
      bottom: _Composer(
        controller: _input,
        enabled: connected && !busy,
        busy: busy,
        onSend: () => _ask(_input.text),
        onStop: ref.read(appControllerProvider.notifier).stopAgent,
        onChanged: () => setState(() {}),
      ),
    );
  }

  Future<void> _history(AppState app) => showFFSheet<void>(
    context,
    builder: (sheet) => FFSheetScaffold(
      title: 'Conversations',
      leading: FFSheetAction(
        label: 'Done',
        onTap: () => Navigator.of(sheet).pop(),
      ),
      trailing: FFSheetAction(
        label: 'New',
        emphasis: true,
        onTap: () async {
          await ref.read(appControllerProvider.notifier).startNewChat();
          if (sheet.mounted) Navigator.of(sheet).pop();
        },
      ),
      child: FFGroup(
        margin: const EdgeInsets.all(FFSpace.gutter),
        children: [
          for (final thread in app.threads)
            FFRow(
              title: thread.title,
              subtitle:
                  '${thread.messageCount} messages · '
                  '${DateFormat.MMMd().format(thread.updatedAt)}',
              chevron: thread.id != app.activeThreadId,
              trailing: thread.id == app.activeThreadId
                  ? Icon(Icons.check_rounded, size: 20, color: sheet.ff.tint)
                  : null,
              onTap: () async {
                await ref
                    .read(appControllerProvider.notifier)
                    .openConversationThread(thread.id);
                if (sheet.mounted) Navigator.of(sheet).pop();
              },
            ),
        ],
      ),
    ),
  );
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.onAsk});
  final ValueChanged<String> onAsk;

  static const _questions = [
    ('What changed this month?', Icons.compare_arrows_rounded),
    ('Where did I overspend?', Icons.trending_up_rounded),
    ('Find unusual transactions', Icons.search_rounded),
    ('Show my subscriptions', Icons.autorenew_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FFSpace.gutter + FFSpace.xs,
            0,
            FFSpace.gutter + FFSpace.xs,
            FFSpace.xl,
          ),
          child: Text(
            'Answers are worked out from your own records, and cite the '
            'transactions they rest on.',
            style: FFText.subhead.copyWith(color: c.secondaryLabel),
          ),
        ),
        FFGroup(
          header: 'Try asking',
          separatorIndent: 57,
          children: [
            for (final (question, icon) in _questions)
              FFRow(
                title: question,
                icon: icon,
                iconColor: c.tint,
                onTap: () => onAsk(question),
              ),
          ],
        ),
      ],
    );
  }
}

class _Turn extends StatelessWidget {
  const _Turn({
    required this.message,
    required this.transactions,
    required this.onAsk,
  });

  final ConversationMessage message;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;

    if (message.author == MessageAuthor.person) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          FFSpace.huge,
          FFSpace.sm,
          FFSpace.gutter,
          FFSpace.xl,
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              color: c.tint,
              borderRadius: BorderRadius.circular(19),
            ),
            child: Text(
              message.text,
              style: FFText.body.copyWith(color: c.onTint),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: FFSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.parts.isEmpty)
            _Prose(message.text)
          else
            for (final part in message.parts)
              _Part(part: part, transactions: transactions, onAsk: onAsk),
          if (message.verified)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFSpace.gutter + FFSpace.xs,
                FFSpace.md,
                FFSpace.gutter,
                0,
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_rounded, size: 14, color: c.green),
                  const SizedBox(width: 5),
                  Text(
                    'Checked against your records',
                    style: FFText.caption.copyWith(color: c.green),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Prose extends StatelessWidget {
  const _Prose(this.text, {this.style, this.color});
  final String text;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FFSpace.gutter + FFSpace.xs,
      0,
      FFSpace.gutter + FFSpace.xs,
      FFSpace.md,
    ),
    child: Text(
      text,
      style: (style ?? FFText.body).copyWith(color: color ?? context.ff.label),
    ),
  );
}

class _Part extends StatelessWidget {
  const _Part({
    required this.part,
    required this.transactions,
    required this.onAsk,
  });

  final AgentPart part;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final data = part.data;

    switch (part.kind) {
      case AgentPartKind.followUps:
        final raw = data['questions'];
        final questions = raw is List
            ? raw.map((e) => '$e').toList()
            : const <String>[];
        if (questions.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(
            FFSpace.gutter,
            FFSpace.sm,
            FFSpace.gutter,
            0,
          ),
          child: Wrap(
            spacing: FFSpace.sm,
            runSpacing: FFSpace.sm,
            children: [
              for (final question in questions)
                FFChip(
                  label: question,
                  selected: false,
                  onTap: () => onAsk(question),
                ),
            ],
          ),
        );

      case AgentPartKind.transactionList:
        final raw = data['transactionIds'];
        final ids = raw is List
            ? raw.whereType<num>().map((e) => e.toInt()).toSet()
            : <int>{};
        final rows = transactions.where((t) => ids.contains(t.id)).toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: FFSpace.sm),
          child: FFGroup(
            separatorIndent: 64,
            children: [
              for (final item in rows)
                FFTransactionRow(
                  item: item,
                  hidden: false,
                  showDay: true,
                  onTap: () => openTransaction(context, item),
                ),
            ],
          ),
        );

      case AgentPartKind.breakdown:
      case AgentPartKind.metricRow:
      case AgentPartKind.comparison:
        final raw = data['rows'] ?? data['metrics'] ?? data['values'];
        final rows = raw is List ? raw.whereType<Map>().toList() : const [];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: FFSpace.sm),
          child: FFGroup(
            header: data['title']?.toString(),
            children: [
              for (final row in rows)
                FFRow(
                  title: '${row['label'] ?? row['title'] ?? ''}',
                  value: row['amountMinor'] is num
                      ? formatMoney(
                          (row['amountMinor'] as num).toInt(),
                          isPlausibleCurrency('${row['currency']}')
                              ? '${row['currency']}'
                              : 'INR',
                        )
                      : '${row['value'] ?? ''}',
                  chevron: false,
                ),
            ],
          ),
        );

      case AgentPartKind.conclusion:
        final text = data['text']?.toString().trim() ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return _Prose(text, style: FFText.title3);

      case AgentPartKind.sourceNote:
        final text = data['text']?.toString().trim() ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return _Prose(
          text,
          style: FFText.footnote,
          color: c.secondaryLabel,
        );

      case AgentPartKind.warning:
        final text = data['text']?.toString().trim() ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return FFNotice(
          icon: Icons.warning_rounded,
          tone: FFNoticeTone.attention,
          title: text,
        );

      case AgentPartKind.narrative:
      case AgentPartKind.insight:
      case AgentPartKind.proposal:
        final text = (data['text'] ?? data['title'])?.toString().trim() ?? '';
        if (text.isEmpty) return const SizedBox.shrink();
        return _Prose(text);
    }
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.app, required this.onRetry});
  final AppState app;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (app.error != null) {
      return FFNotice(
        icon: Icons.error_rounded,
        tone: FFNoticeTone.problem,
        title: 'That did not go through',
        message: app.error,
        action: onRetry == null ? null : 'Try again',
        onAction: onRetry,
      );
    }
    return FFNotice(
      busy: true,
      title: app.askStage ?? 'Reading your records…',
      message: 'Working through the transactions this depends on.',
    );
  }
}

class _Proposal extends ConsumerWidget {
  const _Proposal({required this.proposal});
  final AgentProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ff;
    final destructive =
        proposal.kind == AgentProposalKind.deleteTransaction ||
        proposal.kind == AgentProposalKind.clearConversation ||
        proposal.kind == AgentProposalKind.deleteMemory;
    final controller = ref.read(appControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FFSpace.gutter,
        0,
        FFSpace.gutter,
        FFSpace.xl,
      ),
      child: Container(
        padding: const EdgeInsets.all(FFSpace.lg),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(FFRadius.group),
          border: Border.all(
            color: destructive ? c.red : c.tint,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  destructive
                      ? Icons.delete_outline_rounded
                      : Icons.edit_outlined,
                  size: 19,
                  color: destructive ? c.red : c.tint,
                ),
                const SizedBox(width: FFSpace.sm),
                Expanded(
                  child: Text(
                    destructive ? 'Remove data?' : 'Change something?',
                    style: FFText.caption2.copyWith(
                      color: destructive ? c.red : c.tint,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFSpace.sm),
            Text(proposal.title, style: FFText.headline),
            const SizedBox(height: 3),
            Text(
              proposal.explanation,
              style: FFText.footnote.copyWith(color: c.secondaryLabel),
            ),
            for (final detail in proposal.details.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '·  ',
                      style: FFText.footnote.copyWith(color: c.tertiaryLabel),
                    ),
                    Expanded(
                      child: Text(detail, style: FFText.footnote),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: FFSpace.lg),
            Row(
              children: [
                Expanded(
                  child: FFButton(
                    'Not now',
                    style: FFButtonStyle.tinted,
                    onTap: controller.rejectAgentProposal,
                  ),
                ),
                const SizedBox(width: FFSpace.sm),
                Expanded(
                  child: FFButton(
                    destructive ? 'Remove' : 'Apply',
                    style: destructive
                        ? FFButtonStyle.destructive
                        : FFButtonStyle.filled,
                    onTap: controller.approveAgentProposal,
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

class _Outcome extends ConsumerWidget {
  const _Outcome({required this.message, required this.canUndo});
  final String message;
  final bool canUndo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FFNotice(
    icon: Icons.check_circle_rounded,
    tone: FFNoticeTone.positive,
    title: message,
    action: canUndo ? 'Undo' : null,
    onAction: ref.read(appControllerProvider.notifier).undoLastAgentAction,
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.busy,
    required this.onSend,
    required this.onStop,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    final ready = controller.text.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        FFSpace.md,
        FFSpace.sm,
        FFSpace.md,
        FFSpace.sm + (keyboard ? 0 : MediaQuery.paddingOf(context).bottom),
      ),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(
          top: BorderSide(
            color: c.separator,
            width: 1 / MediaQuery.devicePixelRatioOf(context),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: FFField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 5,
              onChanged: (_) => onChanged(),
              placeholder: enabled
                  ? 'Ask about your money'
                  : busy
                  ? 'Working…'
                  : 'Connect a provider to ask',
            ),
          ),
          const SizedBox(width: FFSpace.sm),
          FFPressable(
            onTap: busy
                ? onStop
                : enabled && ready
                ? onSend
                : null,
            semanticLabel: busy ? 'Stop' : 'Send',
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: busy
                    ? c.fill
                    : ready && enabled
                    ? c.tint
                    : c.quaternaryLabel,
                shape: BoxShape.circle,
              ),
              child: Icon(
                busy ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                size: 19,
                color: busy ? c.label : c.onTint,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
