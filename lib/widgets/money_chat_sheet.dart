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
import '../models/transaction_query.dart';
import '../theme/app_tokens.dart';
import '../screens/settings_screen.dart';
import '../utils/currency_utils.dart';
import 'agent_artifact_card.dart';

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
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sms_outlined,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Analyze transaction messages',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Flow scans recent SMS on this device for supported bank and payment messages. Candidate message text is sent to your configured Ollama endpoint for extraction; structured records and provenance stay on this device.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Android will ask for SMS access if it has not already been granted.',
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
                          child: const Text('Not now'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(sheetContext, true),
                          child: const Text('Analyze messages'),
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
      if (animate) {
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
                  Icon(
                    name.contains('delete')
                        ? Icons.delete_outline_rounded
                        : Icons.blur_on_rounded,
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Review Flow’s action',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Flow will $action.',
                    style: Theme.of(context).textTheme.bodyLarge,
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
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.blur_on_rounded, color: scheme.primary),
            const SizedBox(width: 10),
            const Text('Flow'),
          ],
        ),
        actions: [
          _AgentStateButton(
            connected: connected,
            sync: sync,
            compact: screenWidth < 380,
            onPressed: connected ? _startSmsAnalysis : _openSettings,
          ),
          if (messages.isNotEmpty)
            IconButton(
              tooltip: 'Clear conversation',
              onPressed: _clearConversation,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(contentInset, 14, contentInset, 16),
          child: Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? ListView(
                        controller: _scrollController,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 32, 4, 26),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: scheme.primaryContainer,
                                    borderRadius: AppRadius.all(AppRadius.lg),
                                  ),
                                  child: Icon(
                                    Icons.blur_on_rounded,
                                    size: 28,
                                    color: scheme.onPrimaryContainer,
                                  ),
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
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (!connected)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Material(
                                color: scheme.primaryContainer,
                                shape: ExpressiveShape.card(
                                  radius: AppRadius.xl,
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: _openSettings,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.cloud_outlined,
                                          color: scheme.onPrimaryContainer,
                                        ),
                                        const SizedBox(width: 14),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Connect intelligence',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onPrimaryContainer,
                                                    ),
                                              ),
                                              Text(
                                                'Required for SMS understanding and verified answers.',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onPrimaryContainer,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.arrow_forward_rounded,
                                          color: scheme.onPrimaryContainer,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          FutureBuilder<_FlowBrief>(
                            future: _briefFuture,
                            builder: (context, snapshot) {
                              final brief = snapshot.data;
                              if (brief == null || brief.transactions == 0) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 18),
                                    child: _FinancialBriefCard(
                                      brief: brief,
                                      onPrompt: _ask,
                                    ),
                                  ),
                                  for (final prompt in _promptsFor(brief))
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
                              padding: const EdgeInsets.only(bottom: 18),
                              child: _SyncStateCard(
                                sync: sync,
                                onRetry: _startSmsAnalysis,
                                onStop: () =>
                                    ref.read(syncProvider.notifier).cancel(),
                              ),
                            ),
                          if (connected && sync.phase == SyncPhase.idle)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 18),
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
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount:
                            messages.length +
                            (_thinking || _failedQuestion != null ? 1 : 0),
                        itemBuilder: (_, index) {
                          if (index == messages.length) {
                            if (!_thinking) {
                              return _RetryMessage(
                                onRetry: () => _ask(_failedQuestion, false),
                                detail: _failureDetail,
                              );
                            }
                            return Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: scheme.primary,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _stage,
                                          style: TextStyle(
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _cancel,
                                        child: const Text('Stop'),
                                      ),
                                    ],
                                  ),
                                  if (_streamingText.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    MarkdownBody(
                                      data: mobileFriendlyMarkdown(
                                        _streamingText,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }
                          final message = messages[index];
                          final artifact = AgentArtifact.decode(
                            message.artifactJson,
                          );
                          return _AnimatedMessage(
                            key: ValueKey(
                              message.id ??
                                  message.timestamp.millisecondsSinceEpoch,
                            ),
                            child: Align(
                              alignment: message.user
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(18),
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                decoration: message.user
                                    ? BoxDecoration(
                                        color: scheme.primaryContainer,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(24),
                                          topRight: Radius.circular(24),
                                          bottomLeft: Radius.circular(24),
                                          bottomRight: Radius.circular(6),
                                        ),
                                      )
                                    : BoxDecoration(
                                        color: scheme.surfaceContainerLow,
                                        borderRadius: const BorderRadius.only(
                                          topLeft: Radius.circular(24),
                                          topRight: Radius.circular(48),
                                          bottomLeft: Radius.circular(48),
                                          bottomRight: Radius.circular(16),
                                        ),
                                        border: Border.all(
                                          color: scheme.outlineVariant
                                              .withValues(alpha: 0.5),
                                          width: 1.0,
                                        ),
                                        boxShadow: PremiumShadows.soft(context),
                                      ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (message.user)
                                      Text(
                                        message.text,
                                        style: TextStyle(
                                          color: scheme.onPrimaryContainer,
                                          height: 1.45,
                                        ),
                                      )
                                    else
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (!artifact.isEmpty)
                                            AgentArtifactCard(
                                              artifact: artifact,
                                              onPrompt: _ask,
                                            ),
                                          MarkdownBody(
                                            data: mobileFriendlyMarkdown(
                                              message.text,
                                            ),
                                            selectable: true,
                                            styleSheet: MarkdownStyleSheet(
                                              p: TextStyle(
                                                color: scheme.onSurface,
                                                height: 1.5,
                                                fontSize: 14,
                                              ),
                                              strong: TextStyle(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                              em: TextStyle(
                                                color: scheme.secondary,
                                                fontStyle: FontStyle.italic,
                                              ),
                                              listBullet: TextStyle(
                                                color: scheme.primary,
                                                fontWeight: FontWeight.w800,
                                              ),
                                              code: TextStyle(
                                                color: scheme.onSurface,
                                                backgroundColor: scheme
                                                    .surfaceContainerHighest,
                                                fontFamily: 'monospace',
                                              ),
                                              blockquoteDecoration:
                                                  BoxDecoration(
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: scheme.primary,
                                                        width: 3,
                                                      ),
                                                    ),
                                                  ),
                                              blockquotePadding:
                                                  const EdgeInsets.only(
                                                    left: 12,
                                                  ),
                                            ),
                                          ),
                                          if (widget.onOpenActivity != null)
                                            TextButton(
                                              onPressed: widget.onOpenActivity,
                                              child: const Text('View'),
                                            ),
                                        ],
                                      ),
                                    if (message.sources > 0) ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Icon(
                                            message.verified
                                                ? Icons.verified_outlined
                                                : Icons.fact_check_outlined,
                                            size: 16,
                                            color: scheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${message.verified ? 'Verified' : 'Checked'} with ${message.sources} local records',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (message.filterDetails.isNotEmpty)
                                        Theme(
                                          data: Theme.of(context).copyWith(
                                            dividerColor: Colors.transparent,
                                          ),
                                          child: ExpansionTile(
                                            tilePadding: EdgeInsets.zero,
                                            childrenPadding: EdgeInsets.zero,
                                            dense: true,
                                            title: Text(
                                              'How this was answered',
                                              style: TextStyle(
                                                color: scheme.onSurfaceVariant,
                                                fontSize: 11,
                                              ),
                                            ),
                                            children: [
                                              Align(
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  _formatFilterDetails(
                                                    message.filterDetails,
                                                  ),
                                                  style: TextStyle(
                                                    color:
                                                        scheme.onSurfaceVariant,
                                                    fontSize: 11,
                                                    height: 1.45,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                    if (!message.user) ...[
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: IconButton(
                                          tooltip: 'Copy answer',
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _copyAnswer(message.text),
                                          icon: const Icon(
                                            Icons.content_copy_rounded,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: connected && !_thinking,
                      onSubmitted: (_) => _ask(),
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: connected
                            ? 'Ask about your money…'
                            : 'Connect intelligence to ask Flow',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: !connected || _thinking ? null : _ask,
                    style: IconButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      fixedSize: const Size(52, 52),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: ExpressiveShape.card(radius: AppRadius.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Icon(
                  Icons.arrow_outward_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentStateButton extends StatelessWidget {
  const _AgentStateButton({
    required this.connected,
    required this.sync,
    required this.compact,
    required this.onPressed,
  });
  final bool connected;
  final SyncState sync;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = !connected
        ? ('Connect AI', Icons.link_off_rounded, scheme.error)
        : switch (sync.phase) {
            SyncPhase.requestingPermissions ||
            SyncPhase.fetchingSms ||
            SyncPhase.analyzing => (
              'Syncing',
              Icons.sync_rounded,
              scheme.primary,
            ),
            SyncPhase.error => (
              'Needs help',
              Icons.error_outline_rounded,
              scheme.error,
            ),
            SyncPhase.complete => (
              'Updated',
              Icons.check_circle_outline_rounded,
              context.finance.income,
            ),
            _ => ('Ready', Icons.circle, context.finance.income),
          };
    if (compact) {
      return IconButton(
        onPressed: onPressed,
        tooltip: label,
        icon: Icon(icon, color: color),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ActionChip(
        onPressed: onPressed,
        avatar: Icon(icon, size: 16, color: color),
        label: Text(label),
        tooltip: connected
            ? 'Analyze transaction messages'
            : 'Connect Flow intelligence',
      ),
    );
  }
}

class _AnalyzeMessagesCard extends StatelessWidget {
  const _AnalyzeMessagesCard({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      shape: ExpressiveShape.hero(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: ExpressiveShape.hero(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.sms_outlined),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Understand transaction SMS',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Analyze recent bank messages and build your private financial picture.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_rounded),
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
    final scheme = Theme.of(context).colorScheme;
    final running = {
      SyncPhase.requestingPermissions,
      SyncPhase.fetchingSms,
      SyncPhase.analyzing,
    }.contains(sync.phase);
    final error = sync.phase == SyncPhase.error;
    final progress = sync.total > 0 ? sync.current / sync.total : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: error ? scheme.errorContainer : scheme.surfaceContainerHigh,
        borderRadius: AppRadius.all(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                error
                    ? Icons.error_outline_rounded
                    : running
                    ? Icons.blur_on_rounded
                    : Icons.verified_rounded,
                color: error ? scheme.error : scheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  error
                      ? 'Analysis needs your help'
                      : running
                      ? 'Flow is understanding messages'
                      : 'Transaction messages updated',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            error
                ? sync.errorMessage ?? 'Flow could not finish this analysis.'
                : sync.detail ?? 'Preparing analysis…',
          ),
          if (running) ...[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: progress),
          ],
          if (sync.total > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _BriefPill(label: '${sync.imported} understood'),
                _BriefPill(label: '${sync.skipped} skipped'),
                _BriefPill(label: '${sync.current}/${sync.total} checked'),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: running ? onStop : onRetry,
              child: Text(
                running
                    ? 'Stop safely'
                    : error
                    ? 'Try again'
                    : 'Sync again',
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
                  Icon(Icons.blur_on_rounded, color: scheme.onPrimaryContainer),
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

class _AnimatedMessage extends StatefulWidget {
  const _AnimatedMessage({super.key, required this.child});
  final Widget child;

  @override
  State<_AnimatedMessage> createState() => _AnimatedMessageState();
}

class _AnimatedMessageState extends State<_AnimatedMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0.0, 0.12), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: AppMotion.emphasizedDecelerate,
          ),
        );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
