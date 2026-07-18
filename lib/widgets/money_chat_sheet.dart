import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../providers/assistant_conversation_provider.dart';
import '../services/app_control_service.dart';
import '../services/local_money_mcp.dart';
import '../services/money_chat_service.dart';
import '../services/ollama_cloud_service.dart';
import '../models/agent_artifact.dart';
import '../models/assistant_message.dart';
import '../models/transaction_query.dart';
import '../flow_os/ask/flow_masthead.dart';
import '../flow_os/ask/query_dock.dart';
import '../flow_os/foundation/flow_color.dart';
import '../flow_os/ingestion/evidence_consent_sheet.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../flow_os/primitives/loom_mark.dart';
import '../theme/app_tokens.dart';
import '../screens/settings_screen.dart';
import '../utils/currency_utils.dart';
import 'agent_artifact_card.dart';
import 'ui/flow_ui.dart';

class MoneyChatSheet extends ConsumerStatefulWidget {
  const MoneyChatSheet({
    super.key,
    this.initialPrompt,
    this.fullScreen = false,
    this.onOpenSettings,
    this.onOpenActivity,
  });
  final String? initialPrompt;
  final bool fullScreen;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenActivity;
  @override
  ConsumerState<MoneyChatSheet> createState() => _MoneyChatSheetState();
}

class _MoneyChatSheetState extends ConsumerState<MoneyChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _thinking = false;
  String? _failedQuestion;
  String _failureDetail = 'Check your connection and try again.';
  bool _didScrollToInitialHistory = false;
  String _stage = 'Understanding your request…';
  String _streamingText = '';
  AgentCancellationToken? _cancellationToken;
  late final LocalMoneyMcpClient _mcp;
  late Future<_FlowBrief> _briefFuture;

  List<(IconData, String)> _promptsFor(_FlowBrief brief) => [
    (Icons.compare_arrows_rounded, 'What changed from last month?'),
    if (brief.recurring > 0)
      (Icons.autorenew_rounded, 'Explain my recurring payments')
    else
      (Icons.pie_chart_outline_rounded, 'Where did most of my money go?'),
    if (brief.anomalies > 0)
      (
        Icons.warning_amber_rounded,
        'Help me review ${brief.anomalies} unusual ${brief.anomalies == 1 ? 'transaction' : 'transactions'}',
      ),
    if (brief.transactions >= 10)
      (Icons.trending_up_rounded, 'What might the next 30 days look like?'),
  ];

  @override
  void initState() {
    super.initState();
    _mcp = LocalMoneyMcpClient(
      LocalMoneyMcpServer(
        ref.read(databaseProvider),
        appToolHandler: _handleAppTool,
      ),
    );
    _briefFuture = ref.read(ollamaApiKeyProvider).trim().isEmpty
        ? Future.value(const _FlowBrief.empty())
        : _loadBrief();
    final prompt = widget.initialPrompt?.trim();
    if (prompt != null && prompt.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(prompt));
    }
  }

  Future<_FlowBrief> _loadBrief() async {
    final database = ref.read(databaseProvider);
    final now = DateTime.now();
    final month = await database.summarizeTransactions(
      TransactionQuery(from: DateTime(now.year, now.month), to: now),
    );
    final anomalies = await database.detectAnomalies();
    final recurring = await database.detectRecurringTransactions();
    final budgets = await database.budgetStatus();
    final lastSyncRaw = await database.getAppMetadata('last_sync_at');
    return _FlowBrief(
      totals: (month['totals_by_currency'] as Map).cast<String, dynamic>(),
      transactions: (month['matched_count'] as num?)?.toInt() ?? 0,
      anomalies: (anomalies['anomalies'] as List<dynamic>? ?? const []).length,
      recurring: (recurring['recurring'] as List<dynamic>? ?? const []).length,
      budgets: (budgets['budgets'] as List<dynamic>? ?? const []).length,
      lastSyncAt: DateTime.tryParse(lastSyncRaw ?? ''),
    );
  }

  Future<void> _startSmsAnalysis() async {
    final proceed =
        await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: FlowColor.canvas(context),
          builder: (_) => const EvidenceConsentSheet(),
        ) ??
        false;
    if (!proceed || !mounted) return;
    await ref.read(syncProvider.notifier).sync();
    if (!mounted) return;
    setState(() => _briefFuture = _loadBrief());
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animate && !MediaQuery.disableAnimationsOf(context)) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      }
      _jumpToLatestAfterLayout(3);
    });
  }

  void _jumpToLatestAfterLayout(int remainingFrames) {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    if (remainingFrames <= 1) return;

    // A lazily built list can discover a larger extent after the first jump.
    // Repeat across layout frames so a long conversation reaches its true end.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _jumpToLatestAfterLayout(remainingFrames - 1),
    );
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _ask([String? suggested, bool recordUser = true]) async {
    final question = (suggested ?? _controller.text).trim();
    if (question.isEmpty || _thinking) return;
    final history = ref.read(assistantConversationProvider).value ?? const [];
    _controller.clear();
    setState(() {
      _thinking = true;
      _failedQuestion = null;
      _stage = 'Understanding your request…';
      _streamingText = '';
    });
    if (recordUser) {
      await ref.read(assistantConversationProvider.notifier).addUser(question);
    }
    _scrollToLatest();
    try {
      final token = AgentCancellationToken();
      _cancellationToken = token;
      final service = MoneyChatService(
        ref.read(ollamaCloudProvider),
        mcpClient: _mcp,
        approveTool: _approveTool,
        onProgress: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
        onDelta: (text) {
          if (mounted) setState(() => _streamingText = text);
          _scrollToLatest();
        },
        cancellationToken: token,
        onToolCompleted: (name, result) {
          if (result['changed'] != true) return;
          if ({
            'create_transaction',
            'update_transaction',
            'delete_transaction',
            'bulk_update_transactions',
          }.contains(name)) {
            ref.invalidate(expenseListProvider);
          }
          if (mounted &&
              {
                'create_transaction',
                'update_transaction',
                'delete_transaction',
                'create_budget',
                'delete_budget',
                'bulk_update_transactions',
                'remember_preference',
                'forget_preference',
              }.contains(name)) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Change applied'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => _ask('Undo my last change'),
                ),
              ),
            );
          }
        },
      );
      final answer = await service.ask(question, history: history);
      if (!mounted) return;
      await ref
          .read(assistantConversationProvider.notifier)
          .addAssistant(
            text: answer.text,
            sources: answer.checkedRecords,
            verified: answer.verified,
            filterDetails: jsonEncode(
              answer.appliedFilters.map((filter) => filter.toJson()).toList(),
            ),
            artifactJson: answer.artifact.encode(),
          );
      if (!mounted) return;
      setState(() {});
      _scrollToLatest();
    } on AgentCancelledException {
      if (!mounted) return;
      setState(() {
        _failedQuestion = null;
        _streamingText = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _failedQuestion = question;
        _failureDetail = switch (error) {
          OllamaRequestException(statusCode: 401 || 403) =>
            'Your AI key was rejected. Reconnect it in You.',
          OllamaRequestException(statusCode: 429) =>
            'The AI service is busy. Wait a moment and retry.',
          OllamaRequestException() =>
            'The AI service could not complete this request.',
          FormatException() =>
            'The AI returned an invalid response. Nothing was changed.',
          _ => 'Check your connection and try again.',
        };
      });
      _scrollToLatest();
    } finally {
      _cancellationToken = null;
      if (mounted) setState(() => _thinking = false);
    }
  }

  void _cancel() {
    _cancellationToken?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _streamingText = '';
      _stage = 'Stopping…';
    });
  }

  Future<bool> _approveTool(String name, Map<String, dynamic> arguments) async {
    final action = switch (name) {
      'set_app_lock' =>
        arguments['enabled'] == true
            ? 'enable the app lock'
            : 'disable the app lock',
      'set_notification_capture' =>
        arguments['enabled'] == true
            ? 'enable notification transaction capture'
            : 'disable notification transaction capture',
      'create_transaction' => 'create this transaction',
      'update_transaction' => 'change transaction #${arguments['id'] ?? ''}',
      'delete_transaction' =>
        'permanently delete transaction #${arguments['id'] ?? ''}',
      'create_budget' =>
        'create “${arguments['name'] ?? 'this'}” budget for ${arguments['currency'] ?? ''} ${arguments['amount'] ?? ''}',
      'delete_budget' => 'delete budget #${arguments['id'] ?? ''}',
      'bulk_update_transactions' => _describeBulkUpdate(arguments),
      'remember_preference' =>
        'remember “${arguments['key']}” as “${arguments['value']}” on this device',
      'forget_preference' => 'forget “${arguments['key']}”',
      'reanalyze_transaction_sms' =>
        'send transaction #${arguments['id'] ?? ''} original SMS to your configured Ollama endpoint for re-analysis',
      _ => 'perform this sensitive action',
    };
    return await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FlowSheetHeader(
                    leading: name.contains('delete')
                        ? Icon(
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                          )
                        : const FlowOrb(size: 44),
                    title: 'Review Flow’s action',
                    description: 'Flow will $action.',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name.contains('delete')
                        ? 'You can undo this until another change is made.'
                        : 'Only the fields shown in this request will change. You can undo it afterward.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(sheetContext, false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          child: Text(
                            name.contains('delete') ? 'Delete' : 'Apply',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  String _describeBulkUpdate(Map<String, dynamic> arguments) {
    final filter = (arguments['filter'] as Map?) ?? const {};
    final changes = (arguments['changes'] as Map?) ?? const {};
    final scope = <String>[
      if (filter['merchant'] != null) 'merchant “${filter['merchant']}”',
      if (filter['category'] != null) 'category “${filter['category']}”',
      if (filter['from'] != null || filter['to'] != null)
        'the selected date range',
      if (filter['text'] != null) 'matching “${filter['text']}”',
    ];
    final updates = changes.entries
        .map((entry) => '${entry.key.replaceAll('_', ' ')} to “${entry.value}”')
        .join(', ');
    return 'update transactions for ${scope.isEmpty ? 'the selected filter' : scope.join(', ')} and set $updates';
  }

  void _openSettings() {
    final callback = widget.onOpenSettings;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _clearConversation() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear conversation?'),
            content: const Text(
              'This removes your Flow conversation history from this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    await ref.read(assistantConversationProvider.notifier).clear();
    if (mounted) setState(() => _failedQuestion = null);
  }

  Future<void> _copyAnswer(String answer) async {
    await Clipboard.setData(ClipboardData(text: answer));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Answer copied')));
  }

  Future<Map<String, dynamic>> _handleAppTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    if (name == 'navigate_to') {
      final destination = arguments['destination']?.toString();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (destination == 'settings') {
          _openSettings();
        } else if (destination == 'activity') {
          widget.onOpenActivity?.call();
        }
      });
      return {'changed': true, 'destination': destination};
    }
    final service = ref.read(appControlServiceProvider);
    final result = await service.handle(name, arguments);
    if (result['undo_available'] == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('App setting changed'),
          action: SnackBarAction(label: 'Undo', onPressed: service.undoLast),
        ),
      );
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(assistantConversationProvider).value ?? const [];
    final connected = ref.watch(ollamaApiKeyProvider).trim().isNotEmpty;
    final sync = ref.watch(syncProvider);
    if (messages.isNotEmpty && !_didScrollToInitialHistory) {
      _didScrollToInitialHistory = true;
      _scrollToLatest(animate: false);
    }
    final scheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentInset = screenWidth > AppBreakpoint.contentMax + 40
        ? (screenWidth - AppBreakpoint.contentMax) / 2
        : AppSpacing.page;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          FlowMasthead(
            connected: connected,
            thinking: _thinking,
            onStatePressed: connected ? _startSmsAnalysis : _openSettings,
            onClear: messages.isEmpty ? null : _clearConversation,
          ),
          Expanded(
            child: FlowAtmosphere(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    contentInset,
                    14,
                    contentInset,
                    16,
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: messages.isEmpty
                            ? ListView(
                                controller: _scrollController,
                                children: [
                                  if (connected)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        4,
                                        32,
                                        4,
                                        26,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          FlowOrb(
                                            size: 64,
                                            state: connected
                                                ? FlowOrbState.ready
                                                : FlowOrbState.offline,
                                          ),
                                          const SizedBox(height: 20),
                                          Text(
                                            connected
                                                ? 'What should we understand?'
                                                : 'Connect Flow intelligence',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.headlineSmall,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            connected
                                                ? 'Flow analyzes transaction messages, verifies answers against local records, and safely acts with your approval.'
                                                : 'AI analysis is the core of Fund Flow. Connect Ollama to understand transaction SMS and ask questions about your money.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (!connected)
                                    _ActivationCanvas(onConnect: _openSettings),
                                  FutureBuilder<_FlowBrief>(
                                    future: _briefFuture,
                                    builder: (context, snapshot) {
                                      final brief = snapshot.data;
                                      if (brief == null ||
                                          brief.transactions == 0) {
                                        return const SizedBox.shrink();
                                      }
                                      return Column(
                                        children: [
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 18,
                                            ),
                                            child: _FinancialBriefCard(
                                              brief: brief,
                                              onPrompt: _ask,
                                            ),
                                          ),
                                          for (final prompt in _promptsFor(
                                            brief,
                                          ))
                                            _QuestionTile(
                                              icon: prompt.$1,
                                              label: prompt.$2,
                                              onPressed: () => _ask(prompt.$2),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                  if (connected && sync.phase != SyncPhase.idle)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 18,
                                      ),
                                      child: _SyncStateCard(
                                        sync: sync,
                                        onRetry: _startSmsAnalysis,
                                        onStop: () => ref
                                            .read(syncProvider.notifier)
                                            .cancel(),
                                      ),
                                    ),
                                  if (connected && sync.phase == SyncPhase.idle)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 18,
                                      ),
                                      child: _AnalyzeMessagesCard(
                                        onPressed: _startSmsAnalysis,
                                      ),
                                    ),
                                ],
                              )
                            : ListView.builder(
                                controller: _scrollController,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 16,
                                ),
                                itemCount:
                                    messages.length +
                                    (_thinking || _failedQuestion != null
                                        ? 1
                                        : 0),
                                itemBuilder: (_, index) {
                                  if (index == messages.length) {
                                    if (!_thinking) {
                                      return _RetryMessage(
                                        onRetry: () =>
                                            _ask(_failedQuestion, false),
                                        detail: _failureDetail,
                                      );
                                    }
                                    return _ThinkingCanvas(
                                      stage: _stage,
                                      streamingText: _streamingText,
                                      onStop: _cancel,
                                    );
                                  }
                                  final message = messages[index];
                                  final artifact = AgentArtifact.decode(
                                    message.artifactJson,
                                  );
                                  return _AnimatedMessage(
                                    key: ValueKey(
                                      message.id ??
                                          message
                                              .timestamp
                                              .millisecondsSinceEpoch,
                                    ),
                                    child: _AnswerCanvas(
                                      message: message,
                                      artifact: artifact,
                                      onPrompt: _ask,
                                      onOpenEvidence: widget.onOpenActivity,
                                      onCopy: () => _copyAnswer(message.text),
                                    ),
                                  );
                                },
                              ),
                      ),
                      QueryDock(
                        controller: _controller,
                        enabled: connected && !_thinking,
                        connected: connected,
                        onAsk: _ask,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingCanvas extends StatelessWidget {
  const _ThinkingCanvas({
    required this.stage,
    required this.streamingText,
    required this.onStop,
  });

  final String stage;
  final String streamingText;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LoomMark(size: 36, state: LoomState.checking),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FLOW IS CHECKING',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: FlowColor.proof,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(stage, style: Theme.of(context).textTheme.titleMedium),
                if (streamingText.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  MarkdownBody(
                    data: mobileFriendlyMarkdown(streamingText),
                    styleSheet: MarkdownStyleSheet(
                      p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: FlowColor.content(context),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onStop,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      '■ STOP SAFELY',
                      style: TextStyle(
                        color: FlowColor.quiet(context),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .7,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnswerCanvas extends StatelessWidget {
  const _AnswerCanvas({
    required this.message,
    required this.artifact,
    required this.onPrompt,
    required this.onCopy,
    this.onOpenEvidence,
  });

  final AssistantMessage message;
  final AgentArtifact artifact;
  final ValueChanged<String> onPrompt;
  final VoidCallback onCopy;
  final VoidCallback? onOpenEvidence;

  @override
  Widget build(BuildContext context) {
    if (message.user) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 22),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 2),
              color: FlowColor.proof,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOU ASKED',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: FlowColor.proof,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.15,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    message.text,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: FlowColor.content(context),
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 30),
      constraints: const BoxConstraints(maxWidth: 620),
      child: Stack(
        children: [
          PositionedDirectional(
            start: 13,
            top: 32,
            bottom: 0,
            width: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    FlowColor.proof.withValues(alpha: .8),
                    FlowColor.loom.withValues(alpha: .12),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Transform.translate(
                  offset: const Offset(-44, 0),
                  child: Row(
                    children: [
                      const LoomMark(size: 30, state: LoomState.proven),
                      const SizedBox(width: 16),
                      Text(
                        'FLOW ANSWER',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: FlowColor.proof,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.15,
                        ),
                      ),
                      const Spacer(),
                      if (message.verified)
                        _ProofStamp(
                          icon: Icons.verified_rounded,
                          label: 'VERIFIED',
                          color: FlowColor.mint,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (!artifact.isEmpty) ...[
                  AgentArtifactCard(artifact: artifact, onPrompt: onPrompt),
                  const SizedBox(height: 16),
                ],
                MarkdownBody(
                  data: mobileFriendlyMarkdown(message.text),
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: FlowColor.content(context),
                      height: 1.55,
                    ),
                    strong: TextStyle(
                      color: FlowColor.loomBright,
                      fontWeight: FontWeight.w800,
                    ),
                    listBullet: TextStyle(
                      color: FlowColor.proof,
                      fontWeight: FontWeight.w900,
                    ),
                    code: TextStyle(
                      color: FlowColor.content(context),
                      backgroundColor: FlowColor.plane(context),
                      fontFamily: 'monospace',
                    ),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: FlowColor.proof, width: 3),
                      ),
                    ),
                    blockquotePadding: const EdgeInsets.only(left: 12),
                  ),
                ),
                if (message.sources > 0) ...[
                  const SizedBox(height: 18),
                  CutSurface(
                    color: FlowColor.plane(context),
                    accent: FlowColor.proof.withValues(alpha: .5),
                    cut: 10,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${message.verified ? 'Verified against' : 'Checked against'} ${message.sources} local records',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (message.filterDetails.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            _formatFilterDetails(message.filterDetails),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: FlowColor.quiet(context)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (onOpenEvidence != null)
                      TextButton.icon(
                        onPressed: onOpenEvidence,
                        icon: const Icon(Icons.receipt_long_outlined, size: 18),
                        label: const Text('Open evidence'),
                      ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Copy answer',
                      visualDensity: VisualDensity.compact,
                      onPressed: onCopy,
                      icon: const Icon(Icons.content_copy_rounded, size: 18),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivationCanvas extends StatelessWidget {
  const _ActivationCanvas({required this.onConnect});

  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 36, 0, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CoordinateLabel('ACTIVATION / PRIVATE INTELLIGENCE'),
          const SizedBox(height: 13),
          Text(
            'YOUR MONEY\nCAN EXPLAIN ITSELF.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: FlowColor.content(context),
              fontWeight: FontWeight.w900,
              height: .98,
              letterSpacing: -.8,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Flow turns transaction messages into a private evidence network, then answers questions against what it can prove.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 30),
          CutSurface(
            cut: 18,
            color: FlowColor.plane(context),
            accent: FlowColor.rule(context),
            padding: const EdgeInsets.fromLTRB(17, 18, 17, 5),
            child: const Column(
              children: [
                _ActivationStep(
                  number: '01',
                  title: 'Attach intelligence',
                  detail: 'Encrypted credential · controlled by you',
                  active: true,
                ),
                _ActivationStep(
                  number: '02',
                  title: 'Open an evidence channel',
                  detail: 'Transaction SMS only · explicit consent',
                ),
                _ActivationStep(
                  number: '03',
                  title: 'Ask. Trace. Decide.',
                  detail: 'Every conclusion links back to local proof',
                  last: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: 'Connect AI securely',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onConnect,
              child: CutSurface(
                cut: 14,
                color: FlowColor.loom,
                accent: FlowColor.proof,
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 15,
                ),
                child: const Row(
                  children: [
                    LoomMark(size: 30),
                    SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        'ATTACH INTELLIGENCE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    Text(
                      '01 →',
                      style: TextStyle(
                        color: FlowColor.proof,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 11),
          const Center(child: CoordinateLabel('NO ANALYSIS BEFORE CONSENT')),
        ],
      ),
    );
  }
}

class _ActivationStep extends StatelessWidget {
  const _ActivationStep({
    required this.number,
    required this.title,
    required this.detail,
    this.active = false,
    this.last = false,
  });

  final String number;
  final String title;
  final String detail;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = active ? FlowColor.proof : FlowColor.quiet(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 28,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? FlowColor.loom : Colors.transparent,
                  border: Border.all(color: color.withValues(alpha: .4)),
                ),
                child: Text(
                  number,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active ? Colors.white : color,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (!last)
                Container(
                  width: 2,
                  height: 42,
                  color: color.withValues(alpha: .22),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: FlowColor.content(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FlowColor.quiet(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ProofStamp extends StatelessWidget {
  const _ProofStamp({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 9,
            letterSpacing: .65,
          ),
        ),
      ],
    ),
  );
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: CutSurface(
            cut: 9,
            color: FlowColor.plane(context),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 16, color: FlowColor.proof),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: FlowColor.content(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Text(
                  'ASK →',
                  style: TextStyle(
                    color: FlowColor.proof,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnalyzeMessagesCard extends StatelessWidget {
  const _AnalyzeMessagesCard({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Analyze transaction messages',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: CutSurface(
          cut: 14,
          color: FlowColor.plane(context),
          accent: FlowColor.proof,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const LoomMark(size: 42),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CoordinateLabel('INGEST / SMS'),
                    const SizedBox(height: 4),
                    Text(
                      'Build the evidence field',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: FlowColor.content(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Find transaction signals. Keep structured proof local.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: FlowColor.quiet(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'OPEN →',
                style: TextStyle(
                  color: FlowColor.proof,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncStateCard extends StatelessWidget {
  const _SyncStateCard({
    required this.sync,
    required this.onRetry,
    required this.onStop,
  });
  final SyncState sync;
  final VoidCallback onRetry;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final running = {
      SyncPhase.requestingPermissions,
      SyncPhase.fetchingSms,
      SyncPhase.analyzing,
    }.contains(sync.phase);
    final error = sync.phase == SyncPhase.error;
    final incomplete = sync.failed > 0;
    final progress = sync.total > 0 ? sync.current / sync.total : null;
    final signal = error || incomplete
        ? FlowColor.amber
        : running
        ? FlowColor.proof
        : FlowColor.mint;
    return CutSurface(
      cut: 13,
      color: FlowColor.plane(context),
      accent: signal,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LoomMark(
                size: 42,
                state: error || incomplete
                    ? LoomState.review
                    : running
                    ? LoomState.checking
                    : LoomState.proven,
                progress: progress,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoordinateLabel(
                      running ? 'INGEST / ACTIVE' : 'INGEST / RESULT',
                      color: signal,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      error
                          ? 'Analysis needs intervention'
                          : incomplete
                          ? 'Some signals remain unresolved'
                          : running
                          ? 'Building the evidence field'
                          : 'Evidence field updated',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: FlowColor.content(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            error
                ? sync.errorMessage ?? 'Flow could not finish this analysis.'
                : sync.detail ?? 'Preparing analysis…',
            style: TextStyle(color: FlowColor.quiet(context)),
          ),
          if (running && progress != null) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(
                    height: 5,
                    color: FlowColor.raised(context),
                  ),
                  Container(
                    width: constraints.maxWidth * progress.clamp(0, 1),
                    height: 5,
                    color: FlowColor.proof,
                  ),
                ],
              ),
            ),
          ],
          if (sync.total > 0) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                CoordinateLabel('${sync.imported} / UNDERSTOOD'),
                CoordinateLabel('${sync.skipped} / SKIPPED'),
                if (sync.failed > 0)
                  CoordinateLabel(
                    '${sync.failed} / RETRYABLE',
                    color: FlowColor.amber,
                  ),
                CoordinateLabel('${sync.current}:${sync.total} / CHECKED'),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: running ? onStop : onRetry,
              child: Text(
                '${running
                    ? 'Stop safely'
                    : error
                    ? 'Try again'
                    : incomplete
                    ? 'Retry unfinished'
                    : 'Sync again'} →'
                    .toUpperCase(),
                style: TextStyle(
                  color: signal,
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowBrief {
  const _FlowBrief({
    required this.totals,
    required this.transactions,
    required this.anomalies,
    required this.recurring,
    required this.budgets,
    required this.lastSyncAt,
  });
  const _FlowBrief.empty()
    : totals = const {},
      transactions = 0,
      anomalies = 0,
      recurring = 0,
      budgets = 0,
      lastSyncAt = null;
  final Map<String, dynamic> totals;
  final int transactions;
  final int anomalies;
  final int recurring;
  final int budgets;
  final DateTime? lastSyncAt;
}

class _FinancialBriefCard extends StatelessWidget {
  const _FinancialBriefCard({required this.brief, required this.onPrompt});
  final _FlowBrief brief;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final spending = <String>[];
    for (final entry in brief.totals.entries) {
      final values = (entry.value as Map).cast<String, dynamic>();
      final amount = (values['expense'] as num?)?.toDouble() ?? 0;
      if (amount > 0) spending.add(formatAmount(amount, entry.key));
    }
    return Material(
      color: scheme.primaryContainer,
      shape: ExpressiveShape.card(radius: AppRadius.xl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onPrompt('Give me my financial briefing for this month'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FlowOrb(size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your financial briefing',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: scheme.onPrimaryContainer,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                spending.isEmpty
                    ? '${brief.transactions} transactions this month'
                    : '${spending.join(' + ')} spent this month',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _BriefPill(label: '${brief.transactions} transactions'),
                  if (brief.recurring > 0)
                    _BriefPill(label: '${brief.recurring} recurring'),
                  if (brief.anomalies > 0)
                    _BriefPill(label: '${brief.anomalies} need review'),
                  if (brief.budgets > 0)
                    _BriefPill(label: '${brief.budgets} budgets'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                brief.lastSyncAt == null
                    ? 'Based on local transaction records'
                    : 'SMS updated ${_relativeTime(brief.lastSyncAt!)} · records stay local',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: .78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeTime(DateTime value) {
  final difference = DateTime.now().difference(value.toLocal());
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
  if (difference.inHours < 24) return '${difference.inHours} hr ago';
  return '${difference.inDays} d ago';
}

class _BriefPill extends StatelessWidget {
  const _BriefPill({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.48),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

class _RetryMessage extends StatelessWidget {
  const _RetryMessage({required this.onRetry, required this.detail});

  final VoidCallback onRetry;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: scheme.errorContainer,
        shape: ExpressiveShape.card(radius: AppRadius.xl),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Flow couldn’t answer',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    Text(
                      'Nothing was changed. $detail',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Converts model-produced Markdown tables into stacked, phone-friendly rows.
/// The prompt forbids tables, but this keeps responses readable if a model
/// ignores that instruction.
String mobileFriendlyMarkdown(String input) {
  final lines = input.split('\n');
  final output = <String>[];
  var index = 0;
  List<String> cells(String line) => line
      .split('|')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  bool separator(String line) {
    final values = cells(line);
    return values.isNotEmpty &&
        values.every((value) => RegExp(r'^:?-{3,}:?$').hasMatch(value));
  }

  while (index < lines.length) {
    if (index + 1 < lines.length &&
        lines[index].contains('|') &&
        separator(lines[index + 1])) {
      final headers = cells(lines[index]);
      index += 2;
      while (index < lines.length && lines[index].contains('|')) {
        final values = cells(lines[index]);
        final fields = <String>[];
        for (
          var cellIndex = 0;
          cellIndex < values.length && cellIndex < headers.length;
          cellIndex++
        ) {
          fields.add('**${headers[cellIndex]}:** ${values[cellIndex]}');
        }
        if (fields.isNotEmpty) output.add('- ${fields.join(' · ')}');
        index++;
      }
      continue;
    }
    output.add(lines[index]);
    index++;
  }
  return output.join('\n');
}

String _formatFilterDetails(String raw) {
  try {
    final filters = jsonDecode(raw) as List<dynamic>;
    if (filters.isEmpty) return 'No transaction filter was needed.';
    return filters
        .map((entry) {
          final filter = (entry as Map).cast<String, dynamic>();
          final parts = <String>[];
          if (filter['from'] != null || filter['to'] != null) {
            parts.add(
              'Date: ${filter['from'] ?? 'start'} to ${filter['to'] ?? 'now'}',
            );
          }
          for (final key in [
            'merchant',
            'category',
            'direction',
            'currency',
            'text',
          ]) {
            if (filter[key] != null) {
              parts.add(
                '${key[0].toUpperCase()}${key.substring(1)}: ${filter[key]}',
              );
            }
          }
          return parts.isEmpty ? 'All matching transactions' : parts.join('\n');
        })
        .join('\n\n');
  } catch (_) {
    return 'Verified local transaction filters were applied.';
  }
}

class _AnimatedMessage extends StatelessWidget {
  const _AnimatedMessage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
