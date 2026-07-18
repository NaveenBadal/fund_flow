import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/conversation.dart';
import '../../domain/finance_summary.dart';
import '../../ui/components/current_button.dart';
import '../../ui/components/current_field.dart';
import '../../ui/components/current_header.dart';
import '../../ui/foundation/current_colors.dart';
import '../../ui/format/money_format.dart';
import '../you/connect_intelligence_sheet.dart';

class AskScreen extends ConsumerStatefulWidget {
  const AskScreen({super.key});
  @override
  ConsumerState<AskScreen> createState() => _State();
}

class _State extends ConsumerState<AskScreen> {
  final _question = TextEditingController();
  final _scroll = ScrollController();
  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final connected = app.aiConnection == AiConnection.connected;
    return Column(
      children: [
        CurrentHeader(
          title: 'Ask',
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
          ],
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Column(
                children: [
                  Expanded(
                    child: app.conversation.isEmpty
                        ? _EmptyAsk(
                            app: app,
                            connected: connected,
                            onConnect: _connect,
                            onAsk: _ask,
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.only(bottom: 18),
                            itemCount:
                                app.conversation.length +
                                (app.asking || app.error != null ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i == app.conversation.length) {
                                return _WorkingOrError(app: app);
                              }
                              return _MessageView(message: app.conversation[i]);
                            },
                          ),
                  ),
                  CurrentField(
                    controller: _question,
                    hint: connected
                        ? 'Ask about your money'
                        : 'Connect intelligence to ask',
                    helper: connected
                        ? 'Answers use only the activity you allow'
                        : 'Your activity stays on this device',
                    enabled: connected && !app.asking,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _ask(_question.text),
                    suffix: Semantics(
                      button: true,
                      label: 'Send question',
                      child: IconButton(
                        onPressed: connected && !app.asking
                            ? () => _ask(_question.text)
                            : null,
                        icon: const Icon(Icons.arrow_upward_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _connect() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ConnectIntelligenceSheet(),
  );
  void _ask(String value) {
    if (value.trim().isEmpty) return;
    _question.clear();
    ref.read(appControllerProvider.notifier).ask(value);
  }
}

class _EmptyAsk extends StatelessWidget {
  const _EmptyAsk({
    required this.app,
    required this.connected,
    required this.onConnect,
    required this.onAsk,
  });
  final AppState app;
  final bool connected;
  final VoidCallback onConnect;
  final ValueChanged<String> onAsk;
  @override
  Widget build(BuildContext context) {
    if (!connected) {
      return ListView(
        children: [
          const SizedBox(height: 58),
          Icon(
            Icons.lock_outline_rounded,
            size: 32,
            color: context.current.intelligence,
          ),
          const SizedBox(height: 20),
          Text(
            'Connect intelligence to start asking.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 14),
          Text(
            'Your provider helps understand transaction messages and answer questions. '
            'Normalized activity and conversation history stay on this device.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: CurrentButton(
              label: 'Connect intelligence',
              icon: Icons.link_rounded,
              onPressed: onConnect,
            ),
          ),
        ],
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
        for (final prompt in [
          'Where did most of my money go?',
          'What changed from last month?',
          'Are there any unusual transactions?',
        ])
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

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message});
  final ConversationMessage message;
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
          Text(message.text, style: Theme.of(context).textTheme.bodyLarge),
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
                  'Calculated from ${message.supportingTransactionIds.length} local transactions',
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

class _WorkingOrError extends StatelessWidget {
  const _WorkingOrError({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Row(
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
      ],
    ),
  );
}
