import 'dart:convert';

import '../models/expense.dart';
import '../models/assistant_message.dart';
import '../models/transaction_query.dart';
import 'local_money_mcp.dart';
import 'ollama_cloud_service.dart';

typedef ToolApproval =
    Future<bool> Function(String name, Map<String, dynamic> arguments);
typedef AssistantProgress = void Function(String stage);
typedef ToolCompleted = void Function(String name, Map<String, dynamic> result);

class MoneyChatAnswer {
  const MoneyChatAnswer({
    required this.text,
    required this.sources,
    this.checkedRecords = 0,
    this.appliedFilters = const [],
    this.verified = false,
  });

  final String text;
  final List<Expense> sources;
  final int checkedRecords;
  final List<TransactionQuery> appliedFilters;
  final bool verified;
}

/// Ollama-native tool loop backed by an embedded, read-only MCP server.
class MoneyChatService {
  const MoneyChatService(
    this.cloud, {
    this.mcpClient,
    this.approveTool,
    this.onProgress,
    this.onToolCompleted,
  });

  final OllamaCloudService cloud;
  final MoneyMcpClient? mcpClient;
  final ToolApproval? approveTool;
  final AssistantProgress? onProgress;
  final ToolCompleted? onToolCompleted;

  static const _confirmationRequired = {
    'set_app_lock',
    'set_notification_capture',
    'create_transaction',
    'update_transaction',
    'delete_transaction',
    'manage_budget',
    'reanalyze_transaction_sms',
  };

  Future<MoneyChatAnswer> ask(
    String question, {
    List<AssistantMessage> history = const [],
  }) async {
    if (question.trim().isEmpty) {
      throw ArgumentError('Question cannot be empty.');
    }
    final mcp = mcpClient;
    if (mcp == null) throw StateError('The local MCP client is unavailable.');

    onProgress?.call('Discovering secure tools…');
    final mcpTools = await mcp.listTools();
    final allowedNames = mcpTools.map((tool) => tool.name).toSet();
    final ollamaTools = mcpTools
        .map((tool) => tool.toOllamaFunction())
        .toList();
    final now = DateTime.now();
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are Flow, the single authoritative assistant for a private '
            'personal-finance app. Today is ${now.toIso8601String()} and the device timezone '
            'offset is ${now.timeZoneOffset}. For every question that depends on '
            'transaction data, you MUST call the provided tools before answering. '
            'Use search_transactions for transaction lists and '
            'summarize_transactions for authoritative counts and totals. For '
            'comparisons, call tools once for each period. Resolve relative dates '
            'from today and expand a requested day to local start/end timestamps. '
            'For every request to inspect or change app settings, use the relevant '
            'app tool. Never claim a setting changed unless its tool returned '
            'changed=true. If asked what you can do or which tools are available, '
            'explain the provided tools accurately without inventing capabilities. '
            'For transaction corrections, creation, deletion, recurring flags, or '
            'budgets, first search when an id or exact target is not already known, '
            'then call the matching mutation tool. The host will request confirmation. '
            'When the user explicitly asks to re-analyze a transaction from its original '
            'SMS, first find its id, call reanalyze_transaction_sms, and infer only fields '
            'supported by that SMS. Then show the current and proposed values and ask whether '
            'the user wants to update them. STOP and wait for their reply. Never call '
            'update_transaction in the same user turn as reanalyze_transaction_sms. If the '
            'user replies yes, call update_transaction using the previously proposed values. '
            'Never inspect source SMS for an ordinary search or summary. '
            'Never imply a mutation succeeded unless changed=true was returned. '
            'If essential date information is genuinely ambiguous, ask one short '
            'clarifying question without calling a tool. Never write SQL. Never '
            'invent transactions, totals, balances, or tool results. Mention when '
            'records are truncated. Questions about app settings, privacy, imports, '
            'updates, and usage do not require a transaction tool unless an app '
            'state tool is relevant. Politely refuse requests unrelated to this '
            'app or the user’s personal finances, but understand natural wording '
            'rather than relying on keywords. Be concise and use mobile-friendly '
            'Markdown with short paragraphs and bullets. NEVER use Markdown tables. '
            'Never quote raw SMS in your answer or retain it beyond the tool interaction.',
      },
      for (final message in history.reversed.take(12).toList().reversed)
        {'role': message.user ? 'user' : 'assistant', 'content': message.text},
      {'role': 'user', 'content': question},
    ];
    final toolAudit = <Map<String, dynamic>>[];
    final appliedFilters = <TransactionQuery>[];
    final sourceByKey = <String, Expense>{};
    var checkedRecords = 0;
    var reanalyzedSmsThisTurn = false;
    String? draft;

    for (var turn = 0; turn < 4; turn++) {
      onProgress?.call(
        turn == 0 ? 'Understanding your request…' : 'Reviewing tool results…',
      );
      final response = await cloud.chatWithTools(
        messages: messages,
        tools: ollamaTools,
      );
      messages.add(response.assistantMessage);
      if (response.toolCalls.isEmpty) {
        if (response.content.isEmpty) {
          throw const FormatException('The model returned no final answer.');
        }
        draft = response.content;
        break;
      }

      for (final call in response.toolCalls) {
        onProgress?.call('Using ${_friendlyToolName(call.name)}…');
        McpToolResult result;
        if (!allowedNames.contains(call.name)) {
          result = McpToolResult(
            content: 'Unknown tool: ${call.name}',
            structuredContent: const {},
            isError: true,
          );
        } else if (call.name == 'update_transaction' && reanalyzedSmsThisTurn) {
          result = const McpToolResult(
            content:
                'Do not update yet. Present the proposed corrections and ask the user to approve them. Wait for the next user message.',
            structuredContent: {
              'changed': false,
              'awaiting_user_confirmation': true,
            },
            isError: false,
          );
        } else {
          final allowed =
              !_confirmationRequired.contains(call.name) ||
              await (approveTool?.call(call.name, call.arguments) ??
                  Future<bool>.value(false));
          result = allowed
              ? await mcp.callTool(call.name, call.arguments)
              : const McpToolResult(
                  content: 'The user did not approve this sensitive action.',
                  structuredContent: {'changed': false, 'cancelled': true},
                  isError: true,
                );
        }
        final structured = result.structuredContent;
        if (call.name == 'reanalyze_transaction_sms' && !result.isError) {
          reanalyzedSmsThisTurn = true;
        }
        if (!result.isError) onToolCompleted?.call(call.name, structured);
        checkedRecords += (structured['matched_count'] as num?)?.toInt() ?? 0;
        if (structured['applied_filter'] is Map) {
          appliedFilters.add(
            TransactionQuery.fromJson(
              (structured['applied_filter'] as Map).cast<String, dynamic>(),
            ),
          );
        }
        for (final raw in structured['records'] as List<dynamic>? ?? const []) {
          if (raw is! Map) continue;
          final record = _expenseFromTool(raw.cast<String, dynamic>());
          sourceByKey['${record.id}:${record.date.toIso8601String()}'] = record;
        }
        toolAudit.add({
          'tool': call.name,
          'arguments': call.arguments,
          'result': structured,
          'is_error': result.isError,
        });
        messages.add({
          'role': 'tool',
          'tool_name': call.name,
          'content': result.content.isNotEmpty
              ? result.content
              : jsonEncode(structured),
        });
      }
    }
    if (draft == null) {
      throw const FormatException('The model exceeded the tool-call limit.');
    }

    onProgress?.call('Verifying every claim…');
    final verification = await _verify(
      question: question,
      toolAudit: toolAudit,
      draft: draft,
    );
    final safelyGrounded = _deterministicallyGrounded(
      verification.answer,
      toolAudit,
    );
    return MoneyChatAnswer(
      text: safelyGrounded ? verification.answer : _safeFallback(toolAudit),
      sources: sourceByKey.values.toList(),
      checkedRecords: checkedRecords,
      appliedFilters: appliedFilters,
      verified: verification.valid,
    );
  }

  static String _friendlyToolName(String name) => switch (name) {
    'search_transactions' => 'transaction search',
    'summarize_transactions' => 'verified totals',
    'get_app_state' => 'current app settings',
    'set_theme' => 'theme control',
    'set_amount_visibility' => 'privacy control',
    'set_app_lock' => 'app lock control',
    'set_notification_capture' => 'notification capture control',
    'set_currency' => 'currency control',
    'set_sync_lookback' => 'sync memory control',
    'create_transaction' => 'transaction creation',
    'update_transaction' => 'transaction correction',
    'delete_transaction' => 'transaction deletion',
    'manage_budget' => 'budget control',
    'reanalyze_transaction_sms' => 'original SMS re-analysis',
    _ => name.replaceAll('_', ' '),
  };

  bool _deterministicallyGrounded(
    String answer,
    List<Map<String, dynamic>> audit,
  ) {
    if (audit.isEmpty) return true;
    final evidence = jsonEncode(audit).toLowerCase();
    final financialClaims = RegExp(
      r'(?:₹|\$|€|£)\s*[\d,]+(?:\.\d+)?|\b[\d,]+(?:\.\d+)?\s*(?:inr|usd|eur|gbp|aed|sgd)\b',
      caseSensitive: false,
    ).allMatches(answer);
    for (final claim in financialClaims) {
      final normalized = claim
          .group(0)!
          .toLowerCase()
          .replaceAll(RegExp(r'[^\d.]'), '');
      if (normalized.isNotEmpty && !evidence.contains(normalized)) return false;
    }
    if (RegExp(
          r'\b(changed|enabled|disabled|now (?:dark|light))\b',
          caseSensitive: false,
        ).hasMatch(answer) &&
        !evidence.contains('"changed":true')) {
      return false;
    }
    return true;
  }

  String _safeFallback(List<Map<String, dynamic>> audit) {
    final cancelled = audit.any((entry) => entry['is_error'] == true);
    return cancelled
        ? 'I could not safely complete that request. No unverified change was applied.'
        : 'I found relevant local information, but I could not verify every figure in the generated response. Please narrow the request and try again.';
  }

  Expense _expenseFromTool(Map<String, dynamic> json) => Expense(
    id: json['id'] as int?,
    amount: (json['amount'] as num).toDouble(),
    currency: json['currency'].toString(),
    merchant: json['merchant'].toString(),
    category: json['category'].toString(),
    date: DateTime.parse(json['date'].toString()),
    originalSms: '',
    type: json['direction'].toString(),
    tags: (json['tags'] as List<dynamic>? ?? const []).join(','),
    isRecurring: json['recurring'] == true,
  );

  Future<_Verification> _verify({
    required String question,
    required List<Map<String, dynamic>> toolAudit,
    required String draft,
  }) async {
    final raw = await cloud.answer(
      systemPrompt:
          'Audit a financial answer against the user question and authoritative '
          'MCP tool results. Return JSON only: '
          '{"valid":true,"answer":"final answer","issue":null}. Mark invalid '
          'if the draft fails the question, changes filters/dates/counts/totals, '
          'invents facts, or omits important insufficiency or truncation. If '
          'invalid, correct it using only the MCP results. If no tool was needed '
          'for an app-help or clarification response, verify relevance and do not '
          'invent transaction facts. Never include or quote an original_sms value '
          'in the answer.',
      userPrompt:
          'QUESTION: $question\nMCP_TOOL_AUDIT: ${jsonEncode(toolAudit)}'
          '\nDRAFT: $draft',
    );
    final json = _jsonObject(raw);
    final answer = json['answer']?.toString().trim();
    return _Verification(
      valid: json['valid'] == true,
      answer: answer == null || answer.isEmpty ? draft : answer,
    );
  }

  static Map<String, dynamic> _jsonObject(String raw) {
    var value = raw.trim();
    if (value.startsWith('```')) {
      value = value
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
    }
    final start = value.indexOf('{');
    final end = value.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('AI returned invalid verification output.');
    }
    return (jsonDecode(value.substring(start, end + 1)) as Map)
        .cast<String, dynamic>();
  }
}

class _Verification {
  const _Verification({required this.valid, required this.answer});
  final bool valid;
  final String answer;
}
