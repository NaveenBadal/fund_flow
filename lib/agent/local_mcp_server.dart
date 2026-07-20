import 'dart:convert';

import '../domain/finance_summary.dart';
import '../domain/conversation.dart';
import '../domain/money_format.dart';
import '../domain/preferences.dart';
import '../domain/transaction.dart';
import 'agent_presentation.dart';
import 'agent_proposal.dart';
import 'mcp_protocol.dart';

typedef PreferencesReader = AppPreferences Function();
typedef TransactionsReader = List<MoneyTransaction> Function();
typedef UpdateStatusReader = Future<Map<String, Object?>> Function();
typedef ConversationReader = List<ConversationMessage> Function();
typedef FinancialMemoryReader = Future<List<Map<String, Object?>>> Function();
typedef AgentTelemetryReader =
    Future<List<Map<String, Object?>>> Function(int limit);

class McpExecution {
  const McpExecution({required this.result, this.proposal, this.presentation});
  final McpToolResult result;
  final AgentProposal? proposal;
  final AgentPresentation? presentation;
}

class LocalMcpServer {
  LocalMcpServer({
    required TransactionsReader transactions,
    required PreferencesReader preferences,
    UpdateStatusReader? updateStatus,
    ConversationReader? conversation,
    FinancialMemoryReader? financialMemory,
    AgentTelemetryReader? agentTelemetry,
  }) : _transactions = transactions,
       _preferences = preferences,
       _updateStatus = updateStatus,
       _conversation = conversation,
       _financialMemory = financialMemory,
       _agentTelemetry = agentTelemetry;

  final TransactionsReader _transactions;
  final PreferencesReader _preferences;
  final UpdateStatusReader? _updateStatus;
  final ConversationReader? _conversation;
  final FinancialMemoryReader? _financialMemory;
  final AgentTelemetryReader? _agentTelemetry;

  static const _directions = ['incoming', 'outgoing'];
  static const _sources = ['message', 'notification', 'manual'];
  static const _reviewStates = ['confirmed', 'needsReview'];

  List<McpToolDefinition> get tools => [
    _tool(
      'transactions_search',
      'Search normalized local transactions. Use paging and explicit filters.',
      McpSchema.object(
        properties: {
          'from': McpSchema.string(),
          'to': McpSchema.string(),
          'direction': McpSchema.string(values: _directions),
          'currency': McpSchema.string(),
          'merchant': McpSchema.string(),
          'category': McpSchema.string(),
          'account': McpSchema.string(),
          'source': McpSchema.string(values: _sources),
          'reviewState': McpSchema.string(values: _reviewStates),
          'minimumMinor': McpSchema.integer(minimum: 0),
          'maximumMinor': McpSchema.integer(minimum: 0),
          'limit': McpSchema.integer(minimum: 1, maximum: 100),
          'offset': McpSchema.integer(minimum: 0),
        },
      ),
      McpRisk.read,
    ),
    _tool(
      'transactions_get',
      'Get one normalized local transaction by integer ID.',
      McpSchema.object(
        properties: {'id': McpSchema.integer(minimum: 1)},
        required: ['id'],
      ),
      McpRisk.read,
    ),
    _periodTool(
      'finance_summary',
      'Calculate currency-safe totals and counts.',
    ),
    _tool(
      'finance_breakdown',
      'Calculate a deterministic ranked breakdown for a date range.',
      McpSchema.object(
        properties: {
          'from': McpSchema.string(),
          'to': McpSchema.string(),
          'groupBy': McpSchema.string(
            values: [
              'category',
              'merchant',
              'account',
              'source',
              'day',
              'week',
              'month',
            ],
          ),
          'direction': McpSchema.string(values: _directions),
          'currency': McpSchema.string(),
          'limit': McpSchema.integer(minimum: 1, maximum: 30),
        },
        required: ['from', 'to', 'groupBy'],
      ),
      McpRisk.read,
    ),
    _tool(
      'finance_compare',
      'Compare two explicit date periods without combining currencies.',
      McpSchema.object(
        properties: {
          'currentFrom': McpSchema.string(),
          'currentTo': McpSchema.string(),
          'baselineFrom': McpSchema.string(),
          'baselineTo': McpSchema.string(),
          'direction': McpSchema.string(values: _directions),
        },
        required: ['currentFrom', 'currentTo', 'baselineFrom', 'baselineTo'],
      ),
      McpRisk.read,
    ),
    _periodTool(
      'finance_recurring_candidates',
      'Find repeated merchants as evidence; does not assert subscriptions.',
    ),
    _periodTool(
      'finance_briefing',
      'Return one deterministic financial briefing with totals, leading spending groups, review count, duplicate candidates and unusual transactions. Prefer this for broad overview questions.',
    ),
    _periodTool(
      'finance_anomalies',
      'Find unusually large transactions relative to the same merchant, currency and direction using a deterministic local baseline.',
    ),
    _periodTool(
      'finance_duplicates',
      'Find possible duplicate transactions with the same merchant, amount, currency and direction close together in time.',
    ),
    _tool(
      'categories_list',
      'List categories currently used by normalized transactions.',
      McpSchema.object(),
      McpRisk.read,
    ),
    _tool(
      'sources_status',
      'Read transaction-source counts and import review status.',
      McpSchema.object(),
      McpRisk.read,
    ),
    _tool(
      'settings_get',
      'Read safe app settings. Credentials and provider keys are excluded.',
      McpSchema.object(),
      McpRisk.read,
    ),
    _tool(
      'privacy_boundary',
      'Explain the local/provider data boundary using app-owned facts.',
      McpSchema.object(),
      McpRisk.read,
    ),
    _tool(
      'app_update_status',
      'Authoritative check for whether Fund Flow has an updater and whether a newer verified GitHub development release is available. Always use this for update questions.',
      McpSchema.object(),
      McpRisk.read,
    ),
    _tool(
      'conversation_search',
      'Search recent local conversation turns for follow-up context.',
      McpSchema.object(
        properties: {
          'query': McpSchema.string(),
          'limit': McpSchema.integer(minimum: 1, maximum: 30),
        },
      ),
      McpRisk.read,
    ),
    _tool(
      'memory_list',
      'List user-approved durable financial facts and aliases. This is separate from conversation history.',
      McpSchema.object(),
      McpRisk.read,
    ),
    _tool(
      'agent_performance',
      'Read recent local AI run latency, model-turn, MCP-call and token telemetry. Contains no prompts, answers or credentials.',
      McpSchema.object(
        properties: {'limit': McpSchema.integer(minimum: 1, maximum: 50)},
      ),
      McpRisk.read,
    ),
    _proposalTool(
      'memory_set',
      'Propose saving or replacing one durable financial fact. Never infer or save memory without explicit user intent and approval.',
      McpSchema.object(
        properties: {'key': McpSchema.string(), 'value': McpSchema.string()},
        required: ['key', 'value'],
      ),
    ),
    _proposalTool(
      'memory_delete',
      'Propose deleting one durable financial fact by exact key.',
      McpSchema.object(
        properties: {'key': McpSchema.string()},
        required: ['key'],
      ),
    ),
    _proposalTool(
      'transactions_create',
      'Prepare a new transaction for explicit approval.',
      _transactionInput(requireId: false),
    ),
    _proposalTool(
      'transactions_update',
      'Prepare changes to one existing transaction for explicit approval.',
      _transactionInput(requireId: true),
    ),
    _proposalTool(
      'transactions_delete',
      'Prepare deletion of one existing transaction for explicit approval.',
      McpSchema.object(
        properties: {'id': McpSchema.integer(minimum: 1)},
        required: ['id'],
      ),
    ),
    _proposalTool(
      'transactions_bulk_update_category',
      'Prepare one category change for an explicit list of transaction IDs.',
      McpSchema.object(
        properties: {
          'ids': McpSchema.array(McpSchema.integer(minimum: 1)),
          'category': McpSchema.string(),
        },
        required: ['ids', 'category'],
      ),
    ),
    _proposalTool(
      'settings_update',
      'Prepare safe appearance, currency, privacy, or lookback changes.',
      McpSchema.object(
        properties: {
          'appearance': McpSchema.string(values: ['system', 'light', 'dark']),
          'currency': McpSchema.string(),
          'hideAmounts': McpSchema.boolean(),
          'messageLookbackDays': McpSchema.integer(
            minimum: minimumLookbackDays,
            maximum: maximumLookbackDays,
          ),
          'captureNotifications': McpSchema.boolean(),
        },
      ),
    ),
    _proposalTool(
      'security_set_app_lock',
      'Prepare an app-lock change; enabling requires device authentication.',
      McpSchema.object(
        properties: {'enabled': McpSchema.boolean()},
        required: ['enabled'],
      ),
      risk: McpRisk.platform,
    ),
    _proposalTool(
      'conversation_clear',
      'Prepare clearing local conversation history without deleting money data.',
      McpSchema.object(),
    ),
    _tool(
      'answer_compose',
      'Finish the turn with ordered typed answer parts grounded in tool results.',
      McpSchema.object(
        properties: {
          'parts': {
            'type': 'array',
            'minItems': 1,
            'maxItems': 16,
            'items': {'type': 'object'},
          },
        },
        required: ['parts'],
      ),
      McpRisk.compose,
    ),
  ];

  McpRisk? riskFor(String name) {
    final matches = tools.where((tool) => tool.name == name);
    return matches.length == 1 ? matches.single.risk : null;
  }

  Future<McpExecution> execute(McpToolCall call) async {
    // Local-only diagnostics: seeing which period the model actually asked
    // for is the difference between fixing a bad answer and guessing at it.
    // ignore: avoid_print
    print('fundflow.agent ${call.name} ${jsonEncode(call.arguments)}');
    final definition = tools.where((tool) => tool.name == call.name);
    if (definition.length != 1) return _error(call, 'Unknown capability.');
    try {
      _rejectUnknownArguments(call.arguments, definition.single.inputSchema);
      return switch (call.name) {
        'transactions_search' => _search(call),
        'transactions_get' => _get(call),
        'finance_summary' => _summary(call),
        'finance_breakdown' => _breakdown(call),
        'finance_compare' => _compare(call),
        'finance_recurring_candidates' => _recurring(call),
        'finance_briefing' => _briefing(call),
        'finance_anomalies' => _anomalies(call),
        'finance_duplicates' => _duplicates(call),
        'categories_list' => _categories(call),
        'sources_status' => _sourcesStatus(call),
        'settings_get' => _settings(call),
        'privacy_boundary' => _privacy(call),
        'app_update_status' => await _update(call),
        'conversation_search' => _conversationSearch(call),
        'memory_list' => await _memoryList(call),
        'agent_performance' => await _agentPerformance(call),
        'answer_compose' => _compose(call),
        _ => _proposal(call),
      };
    } on McpProtocolException catch (error) {
      return _error(call, error.message);
    } on AgentPresentationException catch (error) {
      return _error(call, error.message);
    } catch (_) {
      return _error(call, 'Capability arguments were not valid.');
    }
  }

  McpExecution _conversationSearch(McpToolCall call) {
    final query = call.arguments['query']?.toString().trim().toLowerCase();
    final limit = _integer(call.arguments, 'limit', fallback: 12, maximum: 30);
    final values = (_conversation?.call() ?? const <ConversationMessage>[])
        .where(
          (message) =>
              query == null ||
              query.isEmpty ||
              message.text.toLowerCase().contains(query),
        )
        .toList()
        .reversed
        .take(limit)
        .map(
          (message) => {
            'id': message.id,
            'author': message.author.name,
            'text': message.text,
            'createdAt': message.createdAt.toIso8601String(),
            'verified': message.verified,
            'supportingTransactionIds': message.supportingTransactionIds,
          },
        )
        .toList();
    return _ok(call, {
      'messages': values,
    }, summary: 'Found ${values.length} conversation turns');
  }

  Future<McpExecution> _memoryList(McpToolCall call) async {
    final values =
        await (_financialMemory?.call() ??
            Future.value(const <Map<String, Object?>>[]));
    return _ok(call, {
      'facts': values,
      'count': values.length,
      'policy':
          'Only user-approved facts are stored. Chat text and provider output are never learned silently.',
    }, summary: 'Read user-approved financial memory');
  }

  Future<McpExecution> _agentPerformance(McpToolCall call) async {
    final limit = _integer(call.arguments, 'limit', fallback: 10, maximum: 50);
    final runs =
        await (_agentTelemetry?.call(limit) ??
            Future.value(const <Map<String, Object?>>[]));
    int average(String key) {
      if (runs.isEmpty) return 0;
      return runs.fold<int>(
            0,
            (sum, run) => sum + ((run[key] as num?)?.toInt() ?? 0),
          ) ~/
          runs.length;
    }

    return _ok(call, {
      'sampleSize': runs.length,
      'averageElapsedMs': average('elapsedMs'),
      'averageProviderDurationMs': average('providerDurationMs'),
      'averageTurns': average('turns'),
      'averageCalls': average('calls'),
      'averagePromptTokens': average('promptTokens'),
      'averageOutputTokens': average('outputTokens'),
      'runs': runs,
      'privacy':
          'No question, answer, API key or transaction content is stored.',
    }, summary: 'Read local agent performance telemetry');
  }

  Future<McpExecution> _update(McpToolCall call) async {
    final reader = _updateStatus;
    if (reader == null) {
      return _ok(call, {
        'supported': false,
        'updaterAvailable': false,
        'reason': 'Update checks are unavailable on this build or platform.',
      });
    }
    try {
      return _ok(call, {
        'updaterAvailable': true,
        ...await reader(),
      }, summary: 'Checked the verified GitHub update channel');
    } catch (_) {
      return _error(
        call,
        'GitHub update status could not be checked. No app data changed.',
      );
    }
  }

  McpExecution _search(McpToolCall call) {
    final all = _filtered(call.arguments);
    final offset = _integer(call.arguments, 'offset', fallback: 0);
    final limit = _integer(call.arguments, 'limit', fallback: 30, maximum: 100);
    final page = all.skip(offset).take(limit).map(_transactionJson).toList();
    return _ok(call, {
      'transactions': page,
      'total': all.length,
      'offset': offset,
      'hasMore': offset + page.length < all.length,
      ..._emptyPeriodHint(all),
    }, summary: 'Found ${all.length} matching transactions');
  }

  McpExecution _get(McpToolCall call) {
    final id = _integer(call.arguments, 'id', minimum: 1);
    final values = _transactions().where((item) => item.id == id);
    if (values.length != 1) {
      throw const McpProtocolException('Transaction not found.');
    }
    return _ok(call, {'transaction': _transactionJson(values.single)});
  }

  McpExecution _summary(McpToolCall call) {
    final values = _filtered(call.arguments, requirePeriod: true);
    final summaries = FinanceEngine.summarize(values);
    return _ok(call, {
      'currencies': [for (final value in summaries) _summaryJson(value)],
      'reviewCount': values
          .where((item) => item.reviewState == ReviewState.needsReview)
          .length,
      'transactionIds': values.map((item) => item.id).whereType<int>().toList(),
      ..._emptyPeriodHint(values),
    }, summary: 'Calculated ${values.length} transactions');
  }

  McpExecution _breakdown(McpToolCall call) {
    final values = _filtered(call.arguments, requirePeriod: true);
    final groupBy = _requiredString(call.arguments, 'groupBy');
    final limit = _integer(call.arguments, 'limit', fallback: 10, maximum: 30);
    final groups = <String, Map<String, (int, int)>>{};
    for (final item in values) {
      final label = switch (groupBy) {
        'category' => item.category,
        'merchant' => item.merchant,
        'account' =>
          item.account?.trim().isNotEmpty == true
              ? item.account!
              : 'Unknown account',
        'source' => item.source.name,
        'day' => _date(item.occurredAt),
        'week' => _week(item.occurredAt),
        'month' =>
          '${item.occurredAt.year}-${item.occurredAt.month.toString().padLeft(2, '0')}',
        _ => throw const McpProtocolException('Unsupported breakdown.'),
      };
      final currencies = groups.putIfAbsent(label, () => {});
      final old = currencies[item.currency] ?? (0, 0);
      currencies[item.currency] = (old.$1 + item.amountMinor, old.$2 + 1);
    }
    final rows = <Map<String, Object?>>[];
    for (final group in groups.entries) {
      for (final currency in group.value.entries) {
        rows.add({
          'label': group.key,
          'currency': currency.key,
          'amountMinor': currency.value.$1,
          'amountDisplay': formatMoney(currency.value.$1, currency.key),
          'count': currency.value.$2,
        });
      }
    }
    rows.sort(
      (a, b) => (b['amountMinor'] as int).compareTo(a['amountMinor'] as int),
    );
    return _ok(call, {
      'groupBy': groupBy,
      'rows': rows.take(limit).toList(),
      'transactionIds': values.map((item) => item.id).whereType<int>().toList(),
      ..._emptyPeriodHint(values),
    });
  }

  McpExecution _compare(McpToolCall call) {
    List<MoneyTransaction> period(String prefix) => _filtered({
      'from': call.arguments['${prefix}From'],
      'to': call.arguments['${prefix}To'],
      if (call.arguments['direction'] != null)
        'direction': call.arguments['direction'],
    }, requirePeriod: true);
    final currentValues = period('current');
    final baselineValues = period('baseline');
    final current = {
      for (final value in FinanceEngine.summarize(currentValues))
        value.currency: value,
    };
    final baseline = {
      for (final value in FinanceEngine.summarize(baselineValues))
        value.currency: value,
    };
    final currencies = {...current.keys, ...baseline.keys}.toList()..sort();
    return _ok(call, {
      'currencies': [
        for (final currency in currencies)
          {
            'currency': currency,
            'current': _summaryJson(
              current[currency] ?? _emptySummary(currency),
            ),
            'baseline': _summaryJson(
              baseline[currency] ?? _emptySummary(currency),
            ),
          },
      ],
      'evidenceTransactionIds': [
        ...currentValues,
        ...baselineValues,
      ].map((item) => item.id).whereType<int>().take(500).toList(),
      if (currencies.isEmpty) ..._emptyPeriodHint(const []),
    });
  }

  McpExecution _recurring(McpToolCall call) {
    final values = _filtered(call.arguments, requirePeriod: true);
    final groups = <String, List<MoneyTransaction>>{};
    for (final item in values) {
      groups.putIfAbsent(item.merchant, () => []).add(item);
    }
    final rows =
        groups.entries
            .where((entry) => entry.value.length >= 2)
            .map(
              (entry) => {
                'merchant': entry.key,
                'count': entry.value.length,
                'currencies': FinanceEngine.summarize(
                  entry.value,
                ).map(_summaryJson).toList(),
                'transactionIds': entry.value
                    .map((item) => item.id)
                    .whereType<int>()
                    .toList(),
              },
            )
            .toList()
          ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return _ok(call, {
      'candidates': rows.take(20).toList(),
      ..._emptyPeriodHint(values),
    });
  }

  McpExecution _briefing(McpToolCall call) {
    final values = _filtered(call.arguments, requirePeriod: true);
    final outgoing = values
        .where((item) => item.direction == TransactionDirection.outgoing)
        .toList();
    List<Map<String, Object?>> ranked(
      String Function(MoneyTransaction) labelOf,
    ) {
      final groups = <String, Map<String, (int, int)>>{};
      for (final item in outgoing) {
        final currencies = groups.putIfAbsent(labelOf(item), () => {});
        final old = currencies[item.currency] ?? (0, 0);
        currencies[item.currency] = (old.$1 + item.amountMinor, old.$2 + 1);
      }
      final rows =
          <Map<String, Object?>>[
            for (final group in groups.entries)
              for (final currency in group.value.entries)
                {
                  'label': group.key,
                  'currency': currency.key,
                  'amountMinor': currency.value.$1,
                  'amountDisplay': formatMoney(currency.value.$1, currency.key),
                  'count': currency.value.$2,
                },
          ]..sort(
            (a, b) =>
                (b['amountMinor'] as int).compareTo(a['amountMinor'] as int),
          );
      return rows.take(5).toList();
    }

    return _ok(call, {
      'filters': {
        'from': call.arguments['from'],
        'to': call.arguments['to'],
        if (call.arguments['currency'] != null)
          'currency': call.arguments['currency'],
      },
      'checkedCount': values.length,
      'currencies': FinanceEngine.summarize(values).map(_summaryJson).toList(),
      'topCategories': ranked((item) => item.category),
      'topMerchants': ranked((item) => item.merchant),
      'needsReview': values
          .where((item) => item.reviewState == ReviewState.needsReview)
          .length,
      'anomalies': _anomalyRows(values).take(8).toList(),
      'possibleDuplicates': _duplicateRows(values).take(8).toList(),
      'evidenceTransactionIds': values
          .map((item) => item.id)
          .whereType<int>()
          .take(500)
          .toList(),
      ..._emptyPeriodHint(values),
    }, summary: 'Built a local financial briefing');
  }

  McpExecution _anomalies(McpToolCall call) {
    final values = _filtered(call.arguments, requirePeriod: true);
    final rows = _anomalyRows(values);
    return _ok(call, {
      'method':
          'At least 2x the median amount among 3 or more matching merchant, currency and direction transactions.',
      'checkedCount': values.length,
      'rows': rows.take(30).toList(),
      'evidenceTransactionIds': rows
          .map((row) => row['transactionId'])
          .whereType<int>()
          .toList(),
      ..._emptyPeriodHint(values),
    }, summary: 'Checked transactions for unusual amounts');
  }

  List<Map<String, Object?>> _anomalyRows(List<MoneyTransaction> values) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final item in values) {
      final key = [
        item.merchant.toLowerCase(),
        item.currency,
        item.direction.name,
      ].join('|');
      groups.putIfAbsent(key, () => []).add(item);
    }
    final rows = <Map<String, Object?>>[];
    for (final group in groups.values.where((items) => items.length >= 3)) {
      final amounts = group.map((item) => item.amountMinor).toList()..sort();
      final median = amounts[amounts.length ~/ 2];
      if (median <= 0) continue;
      for (final item in group.where(
        (value) => value.amountMinor >= median * 2,
      )) {
        rows.add({
          'transactionId': item.id,
          'merchant': item.merchant,
          'amountMinor': item.amountMinor,
          'amountDisplay': formatMoney(item.amountMinor, item.currency),
          'medianMinor': median,
          'medianDisplay': formatMoney(median, item.currency),
          'multiple': item.amountMinor / median,
          'currency': item.currency,
          'direction': item.direction.name,
          'occurredAt': item.occurredAt.toIso8601String(),
          'sampleSize': group.length,
        });
      }
    }
    rows.sort(
      (a, b) => (b['multiple'] as double).compareTo(a['multiple'] as double),
    );
    return rows;
  }

  McpExecution _duplicates(McpToolCall call) {
    final values = _filtered(call.arguments, requirePeriod: true);
    final rows = _duplicateRows(values);
    return _ok(call, {
      'method':
          'Same normalized merchant, amount, currency and direction within 48 hours. Candidates require review and are never automatically deleted.',
      'checkedCount': values.length,
      'rows': rows.take(30).toList(),
      'evidenceTransactionIds': rows
          .expand(
            (row) => (row['transactionIds'] as List<Object?>).whereType<int>(),
          )
          .toSet()
          .toList(),
      ..._emptyPeriodHint(values),
    }, summary: 'Checked transactions for possible duplicates');
  }

  List<Map<String, Object?>> _duplicateRows(List<MoneyTransaction> values) {
    final groups = <String, List<MoneyTransaction>>{};
    for (final item in values) {
      final key = [
        item.merchant.trim().toLowerCase(),
        item.amountMinor,
        item.currency,
        item.direction.name,
      ].join('|');
      groups.putIfAbsent(key, () => []).add(item);
    }
    final rows = <Map<String, Object?>>[];
    for (final group in groups.values) {
      group.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      for (var index = 1; index < group.length; index++) {
        final previous = group[index - 1];
        final current = group[index];
        final gap = current.occurredAt.difference(previous.occurredAt);
        if (gap <= const Duration(hours: 48)) {
          rows.add({
            'merchant': current.merchant,
            'amountMinor': current.amountMinor,
            'amountDisplay': formatMoney(current.amountMinor, current.currency),
            'currency': current.currency,
            'direction': current.direction.name,
            'transactionIds': [previous.id, current.id],
            'minutesApart': gap.inMinutes,
          });
        }
      }
    }
    rows.sort(
      (a, b) => (a['minutesApart'] as int).compareTo(b['minutesApart'] as int),
    );
    return rows;
  }

  McpExecution _categories(McpToolCall call) {
    final counts = <String, int>{};
    for (final item in _transactions()) {
      counts[item.category] = (counts[item.category] ?? 0) + 1;
    }
    final rows =
        counts.entries
            .map((entry) => {'name': entry.key, 'count': entry.value})
            .toList()
          ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return _ok(call, {'categories': rows});
  }

  McpExecution _sourcesStatus(McpToolCall call) {
    final values = _transactions();
    return _ok(call, {
      'sources': [
        for (final source in TransactionSource.values)
          {
            'source': source.name,
            'count': values.where((item) => item.source == source).length,
          },
      ],
      'needsReview': values
          .where((item) => item.reviewState == ReviewState.needsReview)
          .length,
    });
  }

  McpExecution _settings(McpToolCall call) {
    final value = _preferences();
    return _ok(call, {
      'appearance': value.appearance.name,
      'currency': value.currency,
      'hideAmounts': value.hideAmounts,
      'appLock': value.lockApp,
      'messageLookbackDays': value.messageLookbackDays,
      'captureNotifications': value.captureNotifications,
      'provider': {
        'endpoint': value.aiEndpoint,
        'model': value.aiModel,
        'credentialIncluded': false,
      },
    });
  }

  McpExecution _privacy(McpToolCall call) => _ok(call, {
    'local': [
      'normalized transactions',
      'conversation history',
      'settings',
      'tool audit',
      'message intelligence request and response audit',
      'agent performance telemetry without prompt or answer content',
    ],
    'provider': [
      'questions',
      'tool schemas',
      'requested structured tool results',
      'unseen message batches during import',
    ],
    'neverExposed': [
      'API key',
      'SQLite access',
      'device authentication result',
    ],
  });

  McpExecution _compose(McpToolCall call) {
    final presentation = AgentPresentation.fromComposeArguments(call.arguments);
    return McpExecution(
      presentation: presentation,
      result: McpToolResult(
        callId: call.id,
        tool: call.name,
        content: {'accepted': true},
      ),
    );
  }

  McpExecution _proposal(McpToolCall call) {
    final now = DateTime.now();
    final ids = <int>[];
    final id = call.arguments['id'];
    if (id is int) ids.add(id);
    final rawIds = call.arguments['ids'];
    if (rawIds is List) ids.addAll(rawIds.whereType<int>());
    for (final value in ids) {
      if (!_transactions().any((item) => item.id == value)) {
        throw McpProtocolException('Transaction $value no longer exists.');
      }
    }
    final kind = switch (call.name) {
      'transactions_create' => AgentProposalKind.createTransaction,
      'transactions_update' => AgentProposalKind.updateTransaction,
      'transactions_delete' => AgentProposalKind.deleteTransaction,
      'transactions_bulk_update_category' => AgentProposalKind.bulkCategory,
      'settings_update' => AgentProposalKind.updateSettings,
      'security_set_app_lock' => AgentProposalKind.setAppLock,
      'conversation_clear' => AgentProposalKind.clearConversation,
      'memory_set' => AgentProposalKind.setMemory,
      'memory_delete' => AgentProposalKind.deleteMemory,
      _ => throw const McpProtocolException('Unsupported proposal.'),
    };
    if (call.arguments.isEmpty && kind == AgentProposalKind.updateSettings) {
      throw const McpProtocolException('No setting change was supplied.');
    }
    final title = switch (kind) {
      AgentProposalKind.createTransaction => 'Add a transaction',
      AgentProposalKind.updateTransaction => 'Update a transaction',
      AgentProposalKind.deleteTransaction => 'Delete a transaction',
      AgentProposalKind.bulkCategory => 'Change ${ids.length} categories',
      AgentProposalKind.updateSettings => 'Change app settings',
      AgentProposalKind.setAppLock => 'Change app lock',
      AgentProposalKind.clearConversation => 'Clear this conversation',
      AgentProposalKind.setMemory => 'Save a financial memory',
      AgentProposalKind.deleteMemory => 'Delete a financial memory',
    };
    final reversible = kind != AgentProposalKind.clearConversation;
    final requiresAuthentication =
        kind == AgentProposalKind.setAppLock &&
        call.arguments['enabled'] == true;
    final proposal = AgentProposal(
      kind: kind,
      title: title,
      explanation:
          'The agent prepared this local change. Nothing changes until you approve it.',
      arguments: call.arguments,
      affectedIds: ids,
      createdAt: now,
      // Expiry is not the safety net — approval re-checks that the affected
      // records still look as described and refuses a stale change. So a
      // reversible local edit can wait as long as the person needs; leaving
      // to make tea and coming back should not silently void the card.
      // Changes that cannot be undone or that gate the app keep a short
      // window, where an unattended screen is the risk being guarded.
      expiresAt: now.add(
        reversible && !requiresAuthentication
            ? const Duration(hours: 24)
            : const Duration(minutes: 10),
      ),
      requiresAuthentication: requiresAuthentication,
      reversible: reversible,
    );
    return McpExecution(
      proposal: proposal,
      result: McpToolResult(
        callId: call.id,
        tool: call.name,
        content: {
          'status': 'approval_required',
          'title': title,
          'affectedIds': ids,
        },
        summary: title,
      ),
    );
  }

  /// Appended to a period tool's result when nothing matched.
  ///
  /// A model that mis-derives "this month" — most often by trusting its
  /// training-era sense of today over the stated clock — would otherwise see
  /// an empty result and truthfully report that no data exists. Handing back
  /// the ledger's actual span turns that dead end into a one-turn retry.
  Map<String, Object?> _emptyPeriodHint(List<MoneyTransaction> matched) {
    if (matched.isNotEmpty) return const {};
    final all = _transactions();
    if (all.isEmpty) {
      return {
        'ledgerCoverage': {'totalCount': 0},
        'hint': 'The ledger holds no transactions at all yet.',
      };
    }
    final dates = all.map((item) => item.occurredAt).toList()..sort();
    return {
      'ledgerCoverage': {
        'totalCount': all.length,
        'earliestOccurredAt': dates.first.toIso8601String(),
        'latestOccurredAt': dates.last.toIso8601String(),
      },
      'hint':
          'No records matched the requested period or filters, but the '
          'ledger holds ${all.length} transactions between '
          '${dates.first.toIso8601String()} and ${dates.last.toIso8601String()}. '
          'Re-query within this range before concluding there is no data.',
    };
  }

  List<MoneyTransaction> _filtered(
    Map<String, Object?> arguments, {
    bool requirePeriod = false,
  }) {
    final from = _dateArgument(arguments, 'from', required: requirePeriod);
    final to = _dateArgument(
      arguments,
      'to',
      required: requirePeriod,
      endExclusive: true,
    );
    if (from != null && to != null && !from.isBefore(to)) {
      throw const McpProtocolException('The date range is empty.');
    }
    // Providers fill every schema property rather than omitting the unused
    // ones — empty strings and zeroes arrive meaning "no filter". Taken
    // literally, category "" or maximumMinor 0 matches nothing and the whole
    // ledger silently disappears, so blank means absent throughout.
    String? textFilter(String key) {
      final value = arguments[key]?.toString().trim().toLowerCase();
      return (value == null || value.isEmpty) ? null : value;
    }

    final merchant = textFilter('merchant');
    final category = textFilter('category');
    final account = textFilter('account');
    // Schema enums are advisory to the provider, not enforced by it: models
    // routinely send direction "both" meaning "no filter". Taken literally
    // that matches nothing — every transaction is incoming or outgoing — and
    // the whole ledger silently vanishes from the answer. Honour the intent
    // for the no-filter spellings and reject anything else loudly enough for
    // the model to correct itself.
    final direction = _enumFilter(arguments, 'direction', _directions);
    final source = _enumFilter(arguments, 'source', _sources);
    final review = _enumFilter(arguments, 'reviewState', _reviewStates);
    // Currency is free-form, so the no-filter spellings are honoured here
    // directly — "all" taken literally is a currency nothing is priced in.
    final currencyRaw = arguments['currency']?.toString().trim();
    final currency =
        currencyRaw == null ||
            currencyRaw.isEmpty ||
            const {'both', 'all', 'any'}.contains(currencyRaw.toLowerCase())
        ? null
        : currencyRaw.toUpperCase();
    final minimumRaw = arguments['minimumMinor'] as int?;
    final maximumRaw = arguments['maximumMinor'] as int?;
    final minimum = (minimumRaw == null || minimumRaw <= 0) ? null : minimumRaw;
    final maximum = (maximumRaw == null || maximumRaw <= 0) ? null : maximumRaw;
    final values = _transactions().where((item) {
      if (from != null && item.occurredAt.isBefore(from)) return false;
      if (to != null && !item.occurredAt.isBefore(to)) return false;
      if (merchant != null && !item.merchant.toLowerCase().contains(merchant)) {
        return false;
      }
      if (category != null && item.category.toLowerCase() != category) {
        return false;
      }
      if (account != null &&
          !(item.account?.toLowerCase().contains(account) ?? false)) {
        return false;
      }
      if (direction != null && item.direction.name != direction) return false;
      if (source != null && item.source.name != source) return false;
      if (review != null && item.reviewState.name != review) return false;
      if (currency != null && item.currency != currency) return false;
      if (minimum != null && item.amountMinor < minimum) return false;
      if (maximum != null && item.amountMinor > maximum) return false;
      return true;
    }).toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    return values;
  }

  /// A filter argument that must be one of [allowed], with "no filter"
  /// spellings treated as absent rather than as a value nothing can match.
  String? _enumFilter(
    Map<String, Object?> arguments,
    String key,
    List<String> allowed,
  ) {
    final raw = arguments[key]?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    const unfiltered = {'both', 'all', 'any'};
    if (unfiltered.contains(raw.toLowerCase())) return null;
    final match = allowed.where(
      (value) => value.toLowerCase() == raw.toLowerCase(),
    );
    if (match.length != 1) {
      throw McpProtocolException(
        '$key must be one of ${allowed.join(', ')}, or omitted for all.',
      );
    }
    return match.single;
  }

  DateTime? _dateArgument(
    Map<String, Object?> arguments,
    String key, {
    required bool required,
    bool endExclusive = false,
  }) {
    final raw = arguments[key];
    if (raw == null || raw.toString().trim().isEmpty) {
      if (required) throw McpProtocolException('$key is required.');
      return null;
    }
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed == null) throw McpProtocolException('$key must be an ISO date.');
    final date = DateTime(parsed.year, parsed.month, parsed.day);
    return endExclusive ? date.add(const Duration(days: 1)) : date;
  }

  int _integer(
    Map<String, Object?> values,
    String key, {
    int? fallback,
    int? minimum,
    int? maximum,
  }) {
    final value = values[key] ?? fallback;
    if (value is! int ||
        (minimum != null && value < minimum) ||
        (maximum != null && value > maximum)) {
      throw McpProtocolException('$key is outside its allowed range.');
    }
    return value;
  }

  String _requiredString(Map<String, Object?> values, String key) {
    final value = values[key]?.toString().trim();
    if (value == null || value.isEmpty) {
      throw McpProtocolException('$key is required.');
    }
    return value;
  }

  void _rejectUnknownArguments(
    Map<String, Object?> arguments,
    Map<String, Object?> schema,
  ) {
    final properties = Map<String, Object?>.from(
      schema['properties'] as Map? ?? const {},
    );
    final unknown = arguments.keys.where((key) => !properties.containsKey(key));
    if (unknown.isNotEmpty) {
      throw McpProtocolException('Unknown arguments: ${unknown.join(', ')}.');
    }
    final required = (schema['required'] as List?)?.cast<String>() ?? const [];
    final missing = required.where((key) => !arguments.containsKey(key));
    if (missing.isNotEmpty) {
      throw McpProtocolException('Missing arguments: ${missing.join(', ')}.');
    }
  }

  Map<String, Object?> _transactionJson(MoneyTransaction item) => {
    'id': item.id,
    'amountMinor': item.amountMinor,
    'amountDisplay': formatMoney(item.amountMinor, item.currency),
    'currency': item.currency,
    'direction': item.direction.name,
    'merchant': item.merchant,
    'category': item.category,
    'occurredAt': item.occurredAt.toIso8601String(),
    'source': item.source.name,
    'reviewState': item.reviewState.name,
    'confidence': item.confidence,
    if (item.account != null) 'account': item.account,
    if (item.note != null && item.note!.isNotEmpty) 'note': item.note,
  };

  Map<String, Object?> _summaryJson(CurrencySummary value) => {
    'currency': value.currency,
    'incomingMinor': value.incomingMinor,
    'incomingDisplay': formatMoney(value.incomingMinor, value.currency),
    'outgoingMinor': value.outgoingMinor,
    'outgoingDisplay': formatMoney(value.outgoingMinor, value.currency),
    'netMinor': value.netMinor,
    'netDisplay': formatMoney(value.netMinor, value.currency),
    'count': value.transactionCount,
  };

  CurrencySummary _emptySummary(String currency) => CurrencySummary(
    currency: currency,
    incomingMinor: 0,
    outgoingMinor: 0,
    transactionCount: 0,
  );
  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _week(DateTime value) {
    final monday = DateTime(
      value.year,
      value.month,
      value.day,
    ).subtract(Duration(days: value.weekday - DateTime.monday));
    return _date(monday);
  }

  McpExecution _ok(
    McpToolCall call,
    Map<String, Object?> content, {
    String? summary,
  }) => McpExecution(
    result: McpToolResult(
      callId: call.id,
      tool: call.name,
      content: content,
      summary: summary,
    ),
  );

  McpExecution _error(McpToolCall call, String message) => McpExecution(
    result: McpToolResult(
      callId: call.id,
      tool: call.name,
      content: {'error': message},
      isError: true,
    ),
  );

  static McpToolDefinition _tool(
    String name,
    String description,
    Map<String, Object?> schema,
    McpRisk risk,
  ) => McpToolDefinition(
    name: name,
    description: description,
    inputSchema: schema,
    risk: risk,
  );
  static McpToolDefinition _periodTool(String name, String description) =>
      _tool(
        name,
        description,
        McpSchema.object(
          properties: {
            'from': McpSchema.string(),
            'to': McpSchema.string(),
            'direction': McpSchema.string(values: _directions),
            'currency': McpSchema.string(),
          },
          required: ['from', 'to'],
        ),
        McpRisk.read,
      );
  static McpToolDefinition _proposalTool(
    String name,
    String description,
    Map<String, Object?> schema, {
    McpRisk risk = McpRisk.propose,
  }) => _tool(name, description, schema, risk);
  static Map<String, Object?> _transactionInput({required bool requireId}) =>
      McpSchema.object(
        properties: {
          if (requireId) 'id': McpSchema.integer(minimum: 1),
          'amountMinor': McpSchema.integer(minimum: 1),
          'currency': McpSchema.string(),
          'direction': McpSchema.string(values: _directions),
          'merchant': McpSchema.string(),
          'category': McpSchema.string(),
          'occurredAt': McpSchema.string(),
          'account': McpSchema.string(),
          'note': McpSchema.string(),
        },
        required: requireId
            ? ['id']
            : [
                'amountMinor',
                'currency',
                'direction',
                'merchant',
                'category',
                'occurredAt',
              ],
      );
}
