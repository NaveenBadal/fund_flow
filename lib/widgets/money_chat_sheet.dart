import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../providers/assistant_conversation_provider.dart';
import '../services/app_control_service.dart';
import '../services/local_money_mcp.dart';
import '../services/money_chat_service.dart';
import '../services/ollama_cloud_service.dart';

class MoneyChatSheet extends ConsumerStatefulWidget {
  const MoneyChatSheet({
    super.key,
    this.initialPrompt,
    this.fullScreen = false,
  });
  final String? initialPrompt;
  final bool fullScreen;
  @override
  ConsumerState<MoneyChatSheet> createState() => _MoneyChatSheetState();
}

class _MoneyChatSheetState extends ConsumerState<MoneyChatSheet> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _thinking = false;
  String _stage = 'Understanding your request…';

  static const _prompts = [
    'Summarize this month',
    'Find transactions that need review',
    'Where can I spend less?',
  ];

  @override
  void initState() {
    super.initState();
    final prompt = widget.initialPrompt?.trim();
    if (prompt != null && prompt.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(prompt));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _ask([String? suggested]) async {
    final question = (suggested ?? _controller.text).trim();
    if (question.isEmpty || _thinking) return;
    final history = ref.read(assistantConversationProvider).value ?? const [];
    _controller.clear();
    setState(() => _thinking = true);
    await ref.read(assistantConversationProvider.notifier).addUser(question);
    _scrollToLatest();
    try {
      final service = MoneyChatService(
        OllamaCloudService(
          apiKey: ref.read(ollamaApiKeyProvider),
          baseUrl: ref.read(ollamaBaseUrlProvider),
          model: ref.read(ollamaModelProvider),
        ),
        mcpClient: LocalMoneyMcpClient(
          LocalMoneyMcpServer(
            ref.read(databaseProvider),
            appToolHandler: _handleAppTool,
          ),
        ),
        approveTool: _approveTool,
        onProgress: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
        onToolCompleted: (name, result) {
          if (result['changed'] != true) return;
          if ({
            'create_transaction',
            'update_transaction',
            'delete_transaction',
          }.contains(name)) {
            ref.invalidate(expenseListProvider);
          }
          if (name == 'manage_budget') ref.invalidate(budgetListProvider);
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
          );
      if (!mounted) return;
      setState(() {});
      _scrollToLatest();
    } catch (error) {
      if (!mounted) return;
      final missingKey = ref.read(ollamaApiKeyProvider).trim().isEmpty;
      await ref
          .read(assistantConversationProvider.notifier)
          .addAssistant(
            text: missingKey
                ? 'Connect your AI model in Settings, then I can reason over your money.'
                : 'I could not complete that analysis. Your transaction data was not changed.',
            sources: 0,
            verified: false,
          );
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
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
      'manage_budget' =>
        arguments['remove'] == true
            ? 'remove the ${arguments['category']} budget'
            : 'set the ${arguments['category']} budget',
      'reanalyze_transaction_sms' =>
        'send transaction #${arguments['id'] ?? ''} original SMS to your configured Ollama endpoint for re-analysis',
      _ => 'perform this sensitive action',
    };
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirm app change'),
            content: Text('Allow Flow to $action?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<Map<String, dynamic>> _handleAppTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Ask Flow'),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            onPressed: messages.isEmpty
                ? null
                : () =>
                      ref.read(assistantConversationProvider.notifier).clear(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: Column(
            children: [
              Expanded(
                child: messages.isEmpty
                    ? ListView(
                        controller: _scrollController,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 40, 4, 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 34,
                                  color: scheme.primary,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  'How can I help with your money?',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Ask about transactions, find patterns, correct details, or change app settings.',
                                  style: Theme.of(context).textTheme.bodyLarge
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          for (final prompt in _prompts)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: OutlinedButton(
                                onPressed: () => _ask(prompt),
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.all(17),
                                ),
                                child: Text(prompt),
                              ),
                            ),
                        ],
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        itemCount: messages.length + (_thinking ? 1 : 0),
                        itemBuilder: (_, index) {
                          if (index == messages.length) {
                            return Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                _stage,
                                style: TextStyle(color: scheme.primary),
                              ),
                            );
                          }
                          final message = messages[index];
                          return Align(
                            alignment: message.user
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(16),
                              constraints: const BoxConstraints(maxWidth: 520),
                              decoration: BoxDecoration(
                                color: message.user
                                    ? scheme.primaryContainer
                                    : scheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(18),
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
                                          backgroundColor:
                                              scheme.surfaceContainerHighest,
                                          fontFamily: 'monospace',
                                        ),
                                        blockquoteDecoration: BoxDecoration(
                                          border: Border(
                                            left: BorderSide(
                                              color: scheme.primary,
                                              width: 3,
                                            ),
                                          ),
                                        ),
                                        blockquotePadding:
                                            const EdgeInsets.only(left: 12),
                                      ),
                                    ),
                                  if (message.sources > 0) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      '${message.verified ? 'Verified' : 'Checked'} against '
                                      '${message.sources} matching local records',
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                        fontSize: 10,
                                      ),
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
                                ],
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
                      enabled: !_thinking,
                      onSubmitted: (_) => _ask(),
                      decoration: InputDecoration(
                        hintText: 'Ask about your activity…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _thinking ? null : _ask,
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
