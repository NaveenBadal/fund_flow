import 'dart:convert';

import '../models/expense.dart';
import '../models/transaction_query.dart';
import 'local_money_mcp.dart';
import 'ollama_cloud_service.dart';

typedef TransactionQueryExecutor =
    Future<List<Expense>> Function(TransactionQuery query);

class MoneyChatAnswer {
  const MoneyChatAnswer({
    required this.text,
    required this.sources,
    this.appliedFilters = const [],
    this.verified = false,
  });

  final String text;
  final List<Expense> sources;
  final List<TransactionQuery> appliedFilters;
  final bool verified;
}

/// A local tool pipeline: plan, query SQLite, validate, answer, then verify.
class MoneyChatService {
  const MoneyChatService(this.cloud, {this.mcpClient, this.queryExecutor});

  final OllamaCloudService cloud;
  final LocalMoneyMcpClient? mcpClient;
  @Deprecated('Use mcpClient; retained for isolated unit tests.')
  final TransactionQueryExecutor? queryExecutor;

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
    List<Expense> fallbackTransactions = const [],
  ]) async {
    if (!isInScope(question, fallbackTransactions)) {
      return const MoneyChatAnswer(text: outOfScopeReply, sources: []);
    }

    final plan = await _plan(question);
    if (plan.needsClarification) {
      return MoneyChatAnswer(
        text: plan.clarification?.isNotEmpty == true
            ? plan.clarification!
            : 'Could you clarify the date or filter you want me to use?',
        sources: const [],
      );
    }

    final retrieved = <_QueryResult>[];
    if (plan.intent != 'app_help') {
      if (plan.queries.isEmpty) {
        return const MoneyChatAnswer(
          text:
              'I could not determine a safe transaction filter. Please be more specific.',
          sources: [],
        );
      }
      for (final query in plan.queries) {
        final records =
            mcpClient != null
                  ? await mcpClient!.searchTransactions(query)
                  : queryExecutor != null
                  ? await queryExecutor!(query)
                  : fallbackTransactions.where(query.matches).toList()
              ..sort((a, b) => b.date.compareTo(a.date));
        if (records.any((record) => !query.matches(record))) {
          throw StateError('Local query verification failed.');
        }
        retrieved.add(_QueryResult(query, records));
      }
    }

    final packet = _buildPacket(retrieved);
    final draft = await _answer(question, plan, packet);
    final verification = await _verify(question, plan, packet, draft);
    final sources = <Expense>[
      for (final result in retrieved) ...result.records,
    ];
    return MoneyChatAnswer(
      text: verification.answer,
      sources: sources,
      appliedFilters: plan.queries,
      verified: verification.valid,
    );
  }

  Future<MoneyQueryPlan> _plan(String question) async {
    final now = DateTime.now();
    final raw = await cloud.answer(
      systemPrompt:
          'You are the query planner for a finance app. Convert the question '
          'into JSON only; never answer it. Today is ${now.toIso8601String()} '
          'and the device timezone offset is ${now.timeZoneOffset}. Allowed '
          'intents: transactions, summary, comparison, app_help. Return: '
          '{"intent":"...","needs_clarification":false,"clarification":null,'
          '"queries":[{"label":"primary","from":"ISO-8601 or null",'
          '"to":"ISO-8601 or null","merchant":null,"category":null,'
          '"direction":"expense|income|null","currency":null,"text":null,'
          '"minimum_amount":null,"maximum_amount":null,"limit":100}]}. '
          'Use at most two queries; comparison queries must be labelled. Expand '
          'a day to local 00:00:00 through 23:59:59.999999. Resolve relative '
          'dates from today. If a missing year has a natural most-recent '
          'interpretation, use it; otherwise request clarification. For app '
          'help use no queries. Never produce SQL.',
      userPrompt: question,
    );
    return MoneyQueryPlan.fromJson(_jsonObject(raw));
  }

  Future<String> _answer(
    String question,
    MoneyQueryPlan plan,
    Map<String, dynamic> packet,
  ) {
    return cloud.answer(
      systemPrompt:
          'You are Flow, a precise financial assistant. Answer only from the '
          'verified local tool result supplied. Local totals and counts are '
          'authoritative; do not recalculate or invent records. Mention if a '
          'record list was truncated. For app_help, answer only about Flow: '
          'transaction search, AI chat, imports, privacy, settings, updates, '
          'budgets, and local storage. Be concise and use Markdown. Never expose '
          'raw SMS. Do not claim access to data outside the tool result.',
      userPrompt:
          'QUESTION: $question\nVALIDATED_PLAN: ${jsonEncode(plan.toJson())}'
          '\nVERIFIED_LOCAL_TOOL_RESULT: ${jsonEncode(packet)}',
    );
  }

  Future<_Verification> _verify(
    String question,
    MoneyQueryPlan plan,
    Map<String, dynamic> packet,
    String draft,
  ) async {
    final raw = await cloud.answer(
      systemPrompt:
          'Audit a draft financial answer against the question, validated query '
          'plan, and verified local result. Return JSON only: '
          '{"valid":true,"answer":"final answer","issue":null}. Mark invalid '
          'if it fails the question, changes dates/counts/totals, invents facts, '
          'or omits an important insufficiency. If invalid, provide a corrected '
          'answer using only supplied facts.',
      userPrompt:
          'QUESTION: $question\nPLAN: ${jsonEncode(plan.toJson())}'
          '\nLOCAL_RESULT: ${jsonEncode(packet)}\nDRAFT: $draft',
    );
    final json = _jsonObject(raw);
    final answer = json['answer']?.toString().trim();
    return _Verification(
      valid: json['valid'] == true,
      answer: answer == null || answer.isEmpty ? draft : answer,
    );
  }

  Map<String, dynamic> _buildPacket(List<_QueryResult> results) => {
    'queries': [for (final result in results) result.toJson()],
  };

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
      throw const FormatException('AI returned invalid structured output.');
    }
    return (jsonDecode(value.substring(start, end + 1)) as Map)
        .cast<String, dynamic>();
  }
}

class _QueryResult {
  const _QueryResult(this.query, this.records);

  final TransactionQuery query;
  final List<Expense> records;

  Map<String, dynamic> toJson() {
    final totals = <String, Map<String, double>>{};
    for (final record in records) {
      final currency = totals.putIfAbsent(
        record.currency,
        () => {'income': 0, 'expense': 0},
      );
      currency[record.type] = (currency[record.type] ?? 0) + record.amount;
    }
    final visible = records.take(query.limit).toList();
    return {
      'label': query.label,
      'applied_filter': query.toJson(),
      'matched_count': records.length,
      'totals_by_currency': totals,
      'records_truncated': visible.length < records.length,
      'records': [
        for (final record in visible)
          {
            'id': record.id,
            'date': record.date.toIso8601String(),
            'amount': record.amount,
            'currency': record.currency,
            'direction': record.type,
            'merchant': record.displayMerchant,
            'category': record.category,
            'tags': record.tagList,
            'recurring': record.isRecurring,
          },
      ],
    };
  }
}

class _Verification {
  const _Verification({required this.valid, required this.answer});
  final bool valid;
  final String answer;
}
