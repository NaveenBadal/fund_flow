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
  bool _thinking = false;
  String _stage = 'Understanding your request…';

  static const _prompts = [
    'What changed in my spending this month?',
    'Where can I safely spend less?',
    'Find subscriptions I may have forgotten',
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
    super.dispose();
  }

  Future<void> _ask([String? suggested]) async {
    final question = (suggested ?? _controller.text).trim();
    if (question.isEmpty || _thinking) return;
    final history = ref.read(assistantConversationProvider).value ?? const [];
    _controller.clear();
    setState(() => _thinking = true);
    await ref.read(assistantConversationProvider.notifier).addUser(question);
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final messages = ref.watch(assistantConversationProvider).value ?? const [];
    return Scaffold(
      backgroundColor: const Color(0xFF090D16),
      body: SafeArea(
        child: Container(
          height: widget.fullScreen
              ? MediaQuery.sizeOf(context).height
              : MediaQuery.sizeOf(context).height * .88,
          padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + bottom),
          decoration: const BoxDecoration(color: Color(0xFF090D16)),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.blur_circular_rounded,
                    color: Color(0xFFC7FF4A),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ask Flow',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Your transactions and app controls, in one place',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear conversation',
                    onPressed: messages.isEmpty
                        ? null
                        : () => ref
                              .read(assistantConversationProvider.notifier)
                              .clear(),
                    icon: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Colors.white54,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close assistant',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: messages.isEmpty
                    ? ListView(
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'I can calculate, compare, trace patterns, and explain.\nWhat do you want to know?',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          for (final prompt in _prompts)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 9),
                              child: OutlinedButton(
                                onPressed: () => _ask(prompt),
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  foregroundColor: Colors.white70,
                                  side: const BorderSide(color: Colors.white12),
                                  padding: const EdgeInsets.all(17),
                                ),
                                child: Text(prompt),
                              ),
                            ),
                        ],
                      )
                    : ListView.builder(
                        itemCount: messages.length + (_thinking ? 1 : 0),
                        itemBuilder: (_, index) {
                          if (index == messages.length) {
                            return Padding(
                              padding: const EdgeInsets.all(18),
                              child: Text(
                                _stage,
                                style: const TextStyle(
                                  color: Color(0xFFC7FF4A),
                                ),
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
                                    ? const Color(0xFFC7FF4A)
                                    : Colors.white.withValues(alpha: .07),
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (message.user)
                                    Text(
                                      message.text,
                                      style: const TextStyle(
                                        color: Colors.black,
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
                                        p: const TextStyle(
                                          color: Colors.white,
                                          height: 1.5,
                                          fontSize: 14,
                                        ),
                                        strong: const TextStyle(
                                          color: Color(0xFFC7FF4A),
                                          fontWeight: FontWeight.w800,
                                        ),
                                        em: const TextStyle(
                                          color: Color(0xFF65EAD1),
                                          fontStyle: FontStyle.italic,
                                        ),
                                        listBullet: const TextStyle(
                                          color: Color(0xFFC7FF4A),
                                          fontWeight: FontWeight.w800,
                                        ),
                                        code: TextStyle(
                                          color: const Color(0xFF65EAD1),
                                          backgroundColor: Colors.black
                                              .withValues(alpha: .35),
                                          fontFamily: 'monospace',
                                        ),
                                        blockquoteDecoration:
                                            const BoxDecoration(
                                              border: Border(
                                                left: BorderSide(
                                                  color: Color(0xFFC7FF4A),
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
                                      style: const TextStyle(
                                        color: Colors.white38,
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
                                          title: const Text(
                                            'How this was answered',
                                            style: TextStyle(
                                              color: Colors.white54,
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
                                                style: const TextStyle(
                                                  color: Colors.white54,
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
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ask about your money or control the app…',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: .07),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(99),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _thinking ? null : _ask,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFC7FF4A),
                      foregroundColor: Colors.black,
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
