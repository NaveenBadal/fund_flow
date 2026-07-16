import 'dart:convert';

import '../models/expense.dart';
import '../models/transaction_query.dart';
import 'local_money_mcp.dart';
import 'ollama_cloud_service.dart';

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
  const MoneyChatService(this.cloud, {this.mcpClient});

  final OllamaCloudService cloud;
  final MoneyMcpClient? mcpClient;

  static const outOfScopeReply =
      'I’m built only for your money and this app. Ask me about transactions, '
      'spending, income, budgets, categories, merchants, trends, imports, '
      'privacy, settings, or how Flow works.';

  static final _financeLanguage = RegExp(
    r'\b(transaction|transactions|expense|expenses|spend|spending|spent|income|'
    r'salary|money|budget|balance|payment|paid|pay|purchase|bought|buy|merchant|'
    r'category|categories|subscription|subscriptions|recurring|refund|debit|'
    r'credit|cash|bank|upi|card|transfer|saving|savings|cost|price|amount|total|'
    r'month|monthly|week|weekly|year|today|yesterday|recent|latest|flow|app|'
    r'setting|settings|update|notification|sms|import|export|csv|privacy|lock|'
    r'currency|inr|usd|eur|gbp|aed|sgd)\b',
    caseSensitive: false,
  );
  static final _outsideIntent = RegExp(
    r'\b(python|javascript|typescript|java|c\+\+|html|css|code|coding|'
    r'program|script|essay|poem|story|recipe|weather|sports|politics|medical|'
    r'legal|homework|translate|translation|image|draw)\b',
    caseSensitive: false,
  );

  static bool isInScope(
    String question, [
    List<Expense> transactions = const [],
  ]) {
    final text = question.trim();
    if (text.isEmpty || _outsideIntent.hasMatch(text)) return false;
    if (_financeLanguage.hasMatch(text)) return true;
    final normalized = text.toLowerCase();
    return transactions.any((expense) {
      final merchant = expense.displayMerchant.trim().toLowerCase();
      final category = expense.category.trim().toLowerCase();
      return (merchant.length > 2 && normalized.contains(merchant)) ||
          (category.length > 2 && normalized.contains(category));
    });
  }

  Future<MoneyChatAnswer> ask(
    String question, [
    List<Expense> knownTransactions = const [],
  ]) async {
    if (!isInScope(question, knownTransactions)) {
      return const MoneyChatAnswer(text: outOfScopeReply, sources: []);
    }
    final mcp = mcpClient;
    if (mcp == null) throw StateError('The local MCP client is unavailable.');

    final mcpTools = await mcp.listTools();
    final allowedNames = mcpTools
        .map((tool) => tool['name']?.toString())
        .whereType<String>()
        .toSet();
    final ollamaTools = mcpTools.map(_toOllamaTool).toList();
    final now = DateTime.now();
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are Flow, a precise financial assistant inside a private money '
            'app. Today is ${now.toIso8601String()} and the device timezone '
            'offset is ${now.timeZoneOffset}. For every question that depends on '
            'transaction data, you MUST call the provided tools before answering. '
            'Use search_transactions for transaction lists and '
            'summarize_transactions for authoritative counts and totals. For '
            'comparisons, call tools once for each period. Resolve relative dates '
            'from today and expand a requested day to local start/end timestamps. '
            'If essential date information is genuinely ambiguous, ask one short '
            'clarifying question without calling a tool. Never write SQL. Never '
            'invent transactions, totals, balances, or tool results. Mention when '
            'records are truncated. Questions about app settings, privacy, imports, '
            'updates, and usage do not require a transaction tool. Be concise and '
            'use Markdown. Never expose raw SMS.',
      },
      {'role': 'user', 'content': question},
    ];
    final toolAudit = <Map<String, dynamic>>[];
    final appliedFilters = <TransactionQuery>[];
    final sourceByKey = <String, Expense>{};
    var checkedRecords = 0;
    String? draft;

    for (var turn = 0; turn < 4; turn++) {
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
        McpToolResult result;
        if (!allowedNames.contains(call.name)) {
          result = McpToolResult(
            content: 'Unknown tool: ${call.name}',
            structuredContent: const {},
            isError: true,
          );
        } else {
          result = await mcp.callTool(call.name, call.arguments);
        }
        final structured = result.structuredContent;
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

    final verification = await _verify(
      question: question,
      toolAudit: toolAudit,
      draft: draft,
    );
    return MoneyChatAnswer(
      text: verification.answer,
      sources: sourceByKey.values.toList(),
      checkedRecords: checkedRecords,
      appliedFilters: appliedFilters,
      verified: verification.valid,
    );
  }

  Map<String, dynamic> _toOllamaTool(Map<String, dynamic> tool) => {
    'type': 'function',
    'function': {
      'name': tool['name'],
      'description': tool['description'],
      'parameters': tool['inputSchema'],
    },
  };

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
          'invent transaction facts.',
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
