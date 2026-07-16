import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../services/local_money_mcp.dart';
import '../services/money_chat_service.dart';
import '../services/ollama_cloud_service.dart';

class MoneyChatSheet extends ConsumerStatefulWidget {
  const MoneyChatSheet({super.key, this.initialPrompt});
  final String? initialPrompt;
  @override
  ConsumerState<MoneyChatSheet> createState() => _MoneyChatSheetState();
}

class _MoneyChatSheetState extends ConsumerState<MoneyChatSheet> {
  final _controller = TextEditingController();
  final _messages = <({bool user, String text, int sources, bool verified})>[];
  bool _thinking = false;

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
    _controller.clear();
    setState(() {
      _messages.add((user: true, text: question, sources: 0, verified: false));
      _thinking = true;
    });
    try {
      final service = MoneyChatService(
        OllamaCloudService(
          apiKey: ref.read(ollamaApiKeyProvider),
          baseUrl: ref.read(ollamaBaseUrlProvider),
          model: ref.read(ollamaModelProvider),
        ),
        mcpClient: LocalMoneyMcpClient(
          LocalMoneyMcpServer(ref.read(databaseProvider)),
        ),
      );
      final answer = await service.ask(question);
      if (!mounted) return;
      setState(
        () => _messages.add((
          user: false,
          text: answer.text,
          sources: answer.sources.length,
          verified: answer.verified,
        )),
      );
    } catch (error) {
      if (!mounted) return;
      final missingKey = ref.read(ollamaApiKeyProvider).trim().isEmpty;
      setState(
        () => _messages.add((
          user: false,
          text: missingKey
              ? 'Connect your AI model in Settings, then I can reason over your money.'
              : 'I could not complete that analysis. Your transaction data was not changed.',
          sources: 0,
          verified: false,
        )),
      );
    } finally {
      if (mounted) setState(() => _thinking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      height: MediaQuery.sizeOf(context).height * .88,
      padding: EdgeInsets.fromLTRB(20, 14, 20, 16 + bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF090D16),
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.blur_circular_rounded, color: Color(0xFFC7FF4A)),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ask your money',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Grounded in your private transaction memory',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _messages.isEmpty
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
                    itemCount: _messages.length + (_thinking ? 1 : 0),
                    itemBuilder: (_, index) {
                      if (index == _messages.length) {
                        return const Padding(
                          padding: EdgeInsets.all(18),
                          child: Text(
                            'Tracing your money…',
                            style: TextStyle(color: Color(0xFFC7FF4A)),
                          ),
                        );
                      }
                      final message = _messages[index];
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
                                  data: message.text,
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
                                      backgroundColor: Colors.black.withValues(
                                        alpha: .35,
                                      ),
                                      fontFamily: 'monospace',
                                    ),
                                    blockquoteDecoration: const BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: Color(0xFFC7FF4A),
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    blockquotePadding: const EdgeInsets.only(
                                      left: 12,
                                    ),
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
                    hintText: 'Ask about any transaction…',
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
    );
  }
}
