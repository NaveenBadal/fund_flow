import '../domain/finance_summary.dart';
import '../domain/preferences.dart';
import '../domain/transaction.dart';
import 'agent_presentation.dart';
import 'agent_proposal.dart';
import 'mcp_protocol.dart';

typedef PreferencesReader = AppPreferences Function();
typedef TransactionsReader = List<MoneyTransaction> Function();
typedef UpdateStatusReader = Future<Map<String, Object?>> Function();

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
  }) : _transactions = transactions,
       _preferences = preferences,
       _updateStatus = updateStatus;

  final TransactionsReader _transactions;
  final PreferencesReader _preferences;
  final UpdateStatusReader? _updateStatus;

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
            values: ['category', 'merchant', 'source', 'day', 'month'],
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
      'Check Fund Flow\'s verified GitHub development release channel.',
      McpSchema.object(),
      McpRisk.platform,
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
          'messageLookbackDays': McpSchema.integer(minimum: 7, maximum: 180),
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

  Future<McpExecution> execute(McpToolCall call) async {
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
        'categories_list' => _categories(call),
        'sources_status' => _sourcesStatus(call),
        'settings_get' => _settings(call),
        'privacy_boundary' => _privacy(call),
        'app_update_status' => await _update(call),
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

  Future<McpExecution> _update(McpToolCall call) async {
    final reader = _updateStatus;
    if (reader == null) {
      return _ok(call, {
        'supported': false,
        'reason': 'Update status is unavailable on this platform.',
      });
    }
    try {
      return _ok(call, await reader(), summary: 'Checked app update status');
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
        'source' => item.source.name,
        'day' => _date(item.occurredAt),
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
    });
  }

  McpExecution _compare(McpToolCall call) {
    List<MoneyTransaction> period(String prefix) => _filtered({
      'from': call.arguments['${prefix}From'],
      'to': call.arguments['${prefix}To'],
      if (call.arguments['direction'] != null)
        'direction': call.arguments['direction'],
    }, requirePeriod: true);
    final current = {
      for (final value in FinanceEngine.summarize(period('current')))
        value.currency: value,
    };
    final baseline = {
      for (final value in FinanceEngine.summarize(period('baseline')))
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
    return _ok(call, {'candidates': rows.take(20).toList()});
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
    };
    final proposal = AgentProposal(
      kind: kind,
      title: title,
      explanation:
          'The agent prepared this local change. Nothing changes until you approve it.',
      arguments: call.arguments,
      affectedIds: ids,
      createdAt: now,
      expiresAt: now.add(const Duration(minutes: 10)),
      requiresAuthentication:
          kind == AgentProposalKind.setAppLock &&
          call.arguments['enabled'] == true,
      reversible: kind != AgentProposalKind.clearConversation,
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
    final merchant = arguments['merchant']?.toString().toLowerCase();
    final category = arguments['category']?.toString().toLowerCase();
    final direction = arguments['direction']?.toString();
    final source = arguments['source']?.toString();
    final review = arguments['reviewState']?.toString();
    final currency = arguments['currency']?.toString().toUpperCase();
    final minimum = arguments['minimumMinor'] as int?;
    final maximum = arguments['maximumMinor'] as int?;
    final values = _transactions().where((item) {
      if (from != null && item.occurredAt.isBefore(from)) return false;
      if (to != null && !item.occurredAt.isBefore(to)) return false;
      if (merchant != null && !item.merchant.toLowerCase().contains(merchant)) {
        return false;
      }
      if (category != null && item.category.toLowerCase() != category) {
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

  DateTime? _dateArgument(
    Map<String, Object?> arguments,
    String key, {
    required bool required,
    bool endExclusive = false,
  }) {
    final raw = arguments[key];
    if (raw == null) {
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
    'outgoingMinor': value.outgoingMinor,
    'netMinor': value.netMinor,
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
