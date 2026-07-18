import 'dart:convert';

import '../models/expense.dart';
import '../models/transaction_query.dart';
import '../models/budget.dart';
import 'database_helper.dart';

typedef AppToolHandler =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> arguments,
    );

/// Embedded MCP server for private financial tools.
///
/// It implements the MCP 2025-11-25 lifecycle and tool methods over an
/// in-process JSON-RPC transport, keeping SQLite inaccessible to the model.
class LocalMoneyMcpServer {
  LocalMoneyMcpServer(this.database, {this.appToolHandler});

  final DatabaseHelper database;
  final AppToolHandler? appToolHandler;
  Future<Map<String, dynamic>> Function()? _undo;

  static const protocolVersion = '2025-11-25';

  Future<Map<String, dynamic>?> handle(Map<String, dynamic> request) async {
    final id = request['id'];
    final method = request['method']?.toString();
    if (request['jsonrpc'] != '2.0' || method == null) {
      return _error(id, -32600, 'Invalid JSON-RPC request');
    }
    if (method == 'notifications/initialized') return null;
    try {
      final result = switch (method) {
        'initialize' => _initialize(request['params']),
        'tools/list' => {'tools': _availableTools},
        'tools/call' => await _callTool(request['params']),
        _ => null,
      };
      if (result == null) {
        return _error(id, -32601, 'Method not found: $method');
      }
      return {'jsonrpc': '2.0', 'id': id, 'result': result};
    } on _McpProtocolError catch (error) {
      return _error(id, error.code, error.message);
    } catch (error) {
      return _error(id, -32603, 'Internal MCP error: $error');
    }
  }

  Map<String, dynamic> _initialize(dynamic params) {
    final requested = params is Map ? params['protocolVersion'] : null;
    if (requested != protocolVersion) {
      throw const _McpProtocolError(-32602, 'Unsupported protocol version');
    }
    return {
      'protocolVersion': protocolVersion,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {
        'name': 'flow-local-money',
        'title': 'Flow Local Money Tools',
        'version': '1.0.0',
        'description': 'Consent-gated access to the on-device money database',
      },
    };
  }

  Future<Map<String, dynamic>> _callTool(dynamic params) async {
    if (params is! Map) {
      throw const _McpProtocolError(-32602, 'Missing tool parameters');
    }
    final name = params['name']?.toString();
    final isTransactionTool = _readToolNames.contains(name);
    final isSourceInspectionTool = name == 'reanalyze_transaction_sms';
    final isMutationTool = _mutationToolNames.contains(name);
    final isAppTool = _appToolNames.contains(name) && appToolHandler != null;
    if (!isTransactionTool &&
        !isSourceInspectionTool &&
        !isMutationTool &&
        !isAppTool) {
      throw _McpProtocolError(-32602, 'Unknown tool: $name');
    }
    final arguments = params['arguments'];
    if (arguments is! Map) {
      return _toolError('Tool arguments must be an object.');
    }
    if (isAppTool) {
      try {
        final structured = await appToolHandler!(
          name!,
          arguments.cast<String, dynamic>(),
        );
        return {
          'content': [
            {'type': 'text', 'text': jsonEncode(structured)},
          ],
          'structuredContent': structured,
          'isError': false,
        };
      } catch (error) {
        return _toolError('App action failed: $error');
      }
    }
    if (isMutationTool) {
      return _callMutationTool(name!, arguments.cast<String, dynamic>());
    }
    if (name == 'undo_last_change') {
      final undo = _undo;
      if (undo == null) return _toolError('There is no recent change to undo.');
      _undo = null;
      return _success(await undo());
    }
    if (isSourceInspectionTool) {
      return _inspectTransactionSource(arguments.cast<String, dynamic>());
    }
    final typedArguments = arguments.cast<String, dynamic>();
    if (name == 'spending_breakdown') {
      final structured = await database.spendingBreakdown(
        TransactionQuery.fromJson(typedArguments),
        groupBy: typedArguments['group_by']?.toString() ?? 'category',
      );
      return _success(structured);
    }
    if (name == 'compare_periods') {
      final first = (typedArguments['first'] as Map?)?.cast<String, dynamic>();
      final second = (typedArguments['second'] as Map?)
          ?.cast<String, dynamic>();
      if (first == null || second == null) {
        return _toolError('Both comparison periods are required.');
      }
      return _success(
        await database.comparePeriods(
          TransactionQuery.fromJson(first),
          TransactionQuery.fromJson(second),
        ),
      );
    }
    if (name == 'find_recurring_transactions') {
      return _success(
        await database.detectRecurringTransactions(
          lookbackDays: _boundedInt(
            typedArguments['lookback_days'],
            180,
            30,
            365,
          ),
        ),
      );
    }
    if (name == 'detect_spending_anomalies') {
      return _success(
        await database.detectAnomalies(
          lookbackDays: _boundedInt(
            typedArguments['lookback_days'],
            90,
            30,
            365,
          ),
        ),
      );
    }
    if (name == 'find_duplicate_transactions') {
      return _success(
        await database.findDuplicateTransactions(
          lookbackDays: _boundedInt(
            typedArguments['lookback_days'],
            90,
            7,
            365,
          ),
        ),
      );
    }
    if (name == 'forecast_cashflow') {
      return _success(
        await database.cashflowForecast(
          horizonDays: _boundedInt(typedArguments['horizon_days'], 30, 7, 90),
        ),
      );
    }
    if (name == 'get_budget_status') {
      return _success(await database.budgetStatus());
    }
    if (name == 'get_agent_memory') {
      final memories = await database.getAgentMemories();
      return _success({
        'matched_count': memories.length,
        'memories': memories
            .map(
              (value) => {'key': value['memory_key'], 'value': value['value']},
            )
            .toList(),
      });
    }
    final query = TransactionQuery.fromJson(typedArguments);
    if (name == 'summarize_transactions') {
      final structured = await database.summarizeTransactions(query);
      return {
        'content': [
          {'type': 'text', 'text': jsonEncode(structured)},
        ],
        'structuredContent': structured,
        'isError': false,
      };
    }
    final records = await database.queryTransactions(query);
    if (records.any((record) => !query.matches(record))) {
      return _toolError('Database result failed local filter validation.');
    }
    final summary = await database.summarizeTransactions(query);
    final structured = _searchResult(query, records, summary);
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(structured)},
      ],
      'structuredContent': structured,
      'isError': false,
    };
  }

  int _boundedInt(dynamic value, int fallback, int minimum, int maximum) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? fallback).clamp(minimum, maximum);
  }

  Map<String, dynamic> _success(Map<String, dynamic> structured) => {
    'content': [
      {'type': 'text', 'text': jsonEncode(structured)},
    ],
    'structuredContent': structured,
    'isError': false,
  };

  Future<Map<String, dynamic>> _inspectTransactionSource(
    Map<String, dynamic> arguments,
  ) async {
    final id = (arguments['id'] as num?)?.toInt();
    if (id == null) return _toolError('Transaction id is required.');
    final transaction = await database.getExpenseById(id);
    if (transaction == null) return _toolError('Transaction was not found.');
    final sms = transaction.originalSms.trim();
    if (sms.isEmpty) {
      return _toolError(
        'This transaction has no original SMS and cannot be re-analyzed.',
      );
    }
    final structured = {
      'transaction_id': id,
      'current_merchant': transaction.displayMerchant,
      'current_category': transaction.category,
      'original_sms': sms,
      'instruction':
          'Infer corrections only from this SMS. Do not quote the SMS to the user.',
    };
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(structured)},
      ],
      'structuredContent': structured,
      'isError': false,
    };
  }

  Future<Map<String, dynamic>> _callMutationTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    try {
      Map<String, dynamic> structured;
      if (name == 'create_transaction') {
        final expense = Expense(
          amount: _positiveNumber(arguments, 'amount'),
          currency: arguments['currency']?.toString().toUpperCase() ?? 'INR',
          merchant: _requiredText(arguments, 'merchant'),
          category: _requiredText(arguments, 'category'),
          date: DateTime.parse(_requiredText(arguments, 'date')),
          originalSms: '',
          type: const {'income', 'transfer'}.contains(arguments['direction'])
              ? arguments['direction'].toString()
              : 'expense',
          tags: arguments['tags']?.toString() ?? '',
          account: arguments['account']?.toString(),
          counterpartyAccount: arguments['counterparty_account']?.toString(),
          status: arguments['status']?.toString() ?? 'settled',
          source: 'assistant',
          notes: arguments['notes']?.toString() ?? '',
        );
        final id = await database.insertExpense(expense);
        _undo = () async {
          final changed = await database.deleteExpense(id) == 1;
          return {'changed': changed, 'undid': 'create_transaction'};
        };
        structured = {'changed': true, 'transaction_id': id};
      } else if (name == 'create_budget') {
        final id = await database.insertBudget(
          Budget(
            name: _requiredText(arguments, 'name'),
            amount: _positiveNumber(arguments, 'amount'),
            currency: arguments['currency']?.toString().toUpperCase() ?? 'INR',
            category: arguments['category']?.toString(),
            warningPercent: _boundedInt(
              arguments['warning_percent'],
              75,
              25,
              100,
            ),
            createdAt: DateTime.now(),
          ),
        );
        _undo = () async {
          final changed = await database.deleteBudget(id) == 1;
          return {'changed': changed, 'undid': 'create_budget'};
        };
        structured = {'changed': true, 'budget_id': id};
      } else if (name == 'delete_budget') {
        final id = (arguments['id'] as num?)?.toInt();
        if (id == null) throw ArgumentError('id is required');
        final existing = await database.getBudgetById(id);
        final deleted = await database.deleteBudget(id);
        if (deleted == 1 && existing != null) {
          _undo = () async {
            await database.insertBudget(existing);
            return {'changed': true, 'undid': 'delete_budget'};
          };
        }
        structured = {'changed': deleted == 1, 'budget_id': id};
      } else if (name == 'update_transaction') {
        final id = (arguments['id'] as num?)?.toInt();
        if (id == null) throw ArgumentError('id is required');
        final existing = await database.getExpenseById(id);
        if (existing == null) throw ArgumentError('transaction not found');
        final updated = existing.copyWith(
          amount: arguments['amount'] == null
              ? null
              : _positiveNumber(arguments, 'amount'),
          currency: arguments['currency']?.toString().toUpperCase(),
          merchant: arguments['merchant']?.toString(),
          category: arguments['category']?.toString(),
          date: arguments['date'] == null
              ? null
              : DateTime.parse(arguments['date'].toString()),
          type: arguments['direction']?.toString(),
          tags: arguments['tags']?.toString(),
          account: arguments['account']?.toString(),
          counterpartyAccount: arguments['counterparty_account']?.toString(),
          status: arguments['status']?.toString(),
          notes: arguments['notes']?.toString(),
        );
        await database.updateExpense(updated);
        _undo = () async {
          final changed = await database.updateExpense(existing) == 1;
          return {'changed': changed, 'undid': 'update_transaction'};
        };
        structured = {'changed': true, 'transaction_id': id};
      } else if (name == 'bulk_update_transactions') {
        final filter = (arguments['filter'] as Map?)?.cast<String, dynamic>();
        final changes = (arguments['changes'] as Map?)?.cast<String, dynamic>();
        if (filter == null || changes == null) {
          throw ArgumentError('filter and changes are required');
        }
        final originals = await database.bulkUpdateExpenses(
          TransactionQuery.fromJson(filter),
          changes,
        );
        _undo = () async {
          await database.restoreExpenses(originals);
          return {
            'changed': originals.isNotEmpty,
            'undid': 'bulk_update_transactions',
            'changed_count': originals.length,
          };
        };
        structured = {
          'changed': originals.isNotEmpty,
          'changed_count': originals.length,
          'applied_filter': filter,
          'changes': changes,
        };
      } else if (name == 'remember_preference') {
        final key = _requiredText(arguments, 'key');
        final value = _requiredText(arguments, 'value');
        await database.rememberAgentPreference(key, value);
        _undo = () async {
          final changed = await database.forgetAgentPreference(key) == 1;
          return {'changed': changed, 'undid': 'remember_preference'};
        };
        structured = {'changed': true, 'memory_key': key, 'value': value};
      } else if (name == 'forget_preference') {
        final key = _requiredText(arguments, 'key');
        final memories = await database.getAgentMemories();
        final previous = memories.cast<Map<String, dynamic>>().where(
          (value) => value['memory_key'] == key.trim().toLowerCase(),
        );
        final changed = await database.forgetAgentPreference(key) == 1;
        if (changed && previous.isNotEmpty) {
          final value = previous.first['value'].toString();
          _undo = () async {
            await database.rememberAgentPreference(key, value);
            return {'changed': true, 'undid': 'forget_preference'};
          };
        }
        structured = {'changed': changed, 'memory_key': key};
      } else {
        // delete_transaction
        final id = (arguments['id'] as num?)?.toInt();
        if (id == null) throw ArgumentError('id is required');
        final existing = await database.getExpenseById(id);
        final deleted = await database.deleteExpense(id);
        if (deleted == 1 && existing != null) {
          _undo = () async {
            await database.insertExpense(existing);
            return {'changed': true, 'undid': 'delete_transaction'};
          };
        }
        structured = {'changed': deleted == 1, 'transaction_id': id};
      }
      return {
        'content': [
          {'type': 'text', 'text': jsonEncode(structured)},
        ],
        'structuredContent': structured,
        'isError': false,
      };
    } catch (error) {
      return _toolError('Transaction action failed: $error');
    }
  }

  String _requiredText(Map<String, dynamic> values, String key) {
    final value = values[key]?.toString().trim();
    if (value == null || value.isEmpty) throw ArgumentError('$key is required');
    return value;
  }

  double _positiveNumber(Map<String, dynamic> values, String key) {
    final value = values[key] as num?;
    if (value == null || value <= 0) {
      throw ArgumentError('$key must be positive');
    }
    return value.toDouble();
  }

  Map<String, dynamic> _searchResult(
    TransactionQuery query,
    List<Expense> records,
    Map<String, dynamic> summary,
  ) => {
    'applied_filter': query.toJson(),
    'matched_count': summary['matched_count'],
    'totals_by_currency': summary['totals_by_currency'],
    'records_truncated':
        (summary['matched_count'] as num? ?? 0).toInt() > records.length,
    'records': records.map(_record).toList(),
  };

  Map<String, dynamic> _record(Expense record) => {
    'id': record.id,
    'date': record.date.toIso8601String(),
    'amount': record.amount,
    'currency': record.currency,
    'direction': record.type,
    'merchant': record.displayMerchant,
    'category': record.category,
    'tags': record.tagList,
    'account': record.account,
    'status': record.status,
    'source': record.source,
    'confidence': record.confidence,
  };

  Map<String, dynamic> _toolError(String message) => {
    'content': [
      {'type': 'text', 'text': message},
    ],
    'isError': true,
  };

  static Map<String, dynamic> _error(dynamic id, int code, String message) => {
    'jsonrpc': '2.0',
    'id': id,
    'error': {'code': code, 'message': message},
  };

  List<Map<String, dynamic>> get _availableTools => [
    ..._transactionTools,
    if (appToolHandler != null) ..._appTools,
  ];

  static final List<Map<String, dynamic>> _transactionTools = [
    {
      'name': 'search_transactions',
      'title': 'Search local transactions',
      'description':
          'Retrieve transactions matching validated date, merchant, category, direction, currency, amount, or text filters.',
      'inputSchema': _inputSchema,
      'outputSchema': {
        'type': 'object',
        'properties': {
          'applied_filter': {'type': 'object'},
          'matched_count': {'type': 'integer'},
          'totals_by_currency': {'type': 'object'},
          'records_truncated': {'type': 'boolean'},
          'records': {'type': 'array'},
        },
        'required': [
          'applied_filter',
          'matched_count',
          'totals_by_currency',
          'records_truncated',
          'records',
        ],
      },
    },
    {
      'name': 'spending_breakdown',
      'title': 'Break spending into groups',
      'description':
          'Calculate an authoritative transaction breakdown grouped by category, merchant, day, or direction. Use this for where-money-went and ranked spending questions.',
      'inputSchema': {
        ..._inputSchema,
        'properties': {
          ...(_inputSchema['properties'] as Map),
          'group_by': {
            'type': 'string',
            'enum': ['category', 'merchant', 'day', 'direction'],
          },
        },
        'required': ['group_by'],
      },
    },
    {
      'name': 'compare_periods',
      'title': 'Compare two financial periods',
      'description':
          'Compare authoritative income and expense totals for two explicitly bounded periods without mixing currencies.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'first': _inputSchema,
          'second': _inputSchema,
          'continue_with_model': {'type': 'boolean'},
        },
        'required': ['first', 'second'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'find_recurring_transactions',
      'title': 'Find recurring payments',
      'description':
          'Detect likely recurring expenses from repeated merchant, interval, and amount patterns.',
      'inputSchema': _daysSchema('lookback_days', 30, 365),
    },
    {
      'name': 'detect_spending_anomalies',
      'title': 'Find unusual spending',
      'description':
          'Find unusually large expenses relative to the user local spending distribution.',
      'inputSchema': _daysSchema('lookback_days', 30, 365),
    },
    {
      'name': 'find_duplicate_transactions',
      'title': 'Find possible duplicate transactions',
      'description':
          'Find transaction pairs that likely represent the same charge. This is read-only; never delete either record automatically.',
      'inputSchema': _daysSchema('lookback_days', 7, 365),
    },
    {
      'name': 'forecast_cashflow',
      'title': 'Forecast cash flow',
      'description':
          'Produce a transparent short-term cash-flow projection from trailing local income and expenses. Always describe it as an estimate.',
      'inputSchema': _daysSchema('horizon_days', 7, 90),
    },
    {
      'name': 'get_budget_status',
      'title': 'Read budgets',
      'description':
          'Read current monthly budget limits and deterministic progress.',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'get_agent_memory',
      'title': 'Read remembered preferences',
      'description':
          'Read preferences and goals the user explicitly asked Flow to remember.',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'summarize_transactions',
      'title': 'Summarize local transactions',
      'description':
          'Calculate authoritative counts and income/expense totals for matching local transactions.',
      'inputSchema': _inputSchema,
      'outputSchema': {
        'type': 'object',
        'properties': {
          'applied_filter': {'type': 'object'},
          'matched_count': {'type': 'integer'},
          'totals_by_currency': {'type': 'object'},
        },
        'required': ['applied_filter', 'matched_count', 'totals_by_currency'],
      },
    },
    {
      'name': 'reanalyze_transaction_sms',
      'title': 'Re-analyze a transaction source SMS',
      'description':
          'Fetch one transaction original SMS for re-analysis only when the user explicitly requests it and approves sharing it with Ollama.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
        },
        'required': ['id'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'create_transaction',
      'title': 'Create a transaction',
      'description':
          'Create a manual transaction after explicit user confirmation.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'amount': {'type': 'number', 'exclusiveMinimum': 0},
          'currency': {'type': 'string'},
          'merchant': {'type': 'string'},
          'category': {'type': 'string'},
          'date': {'type': 'string', 'format': 'date-time'},
          'direction': {
            'type': 'string',
            'enum': ['expense', 'income', 'transfer'],
          },
          'tags': {'type': 'string'},
          'account': {
            'type': ['string', 'null'],
          },
          'counterparty_account': {
            'type': ['string', 'null'],
          },
          'status': {
            'type': 'string',
            'enum': ['pending', 'settled', 'reversed'],
          },
          'notes': {'type': 'string'},
        },
        'required': ['amount', 'merchant', 'category', 'date', 'direction'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'update_transaction',
      'title': 'Correct a transaction',
      'description':
          'Update only explicitly supplied fields on an existing transaction after confirmation.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
          'amount': {'type': 'number', 'exclusiveMinimum': 0},
          'currency': {'type': 'string'},
          'merchant': {'type': 'string'},
          'category': {'type': 'string'},
          'date': {'type': 'string', 'format': 'date-time'},
          'direction': {
            'type': 'string',
            'enum': ['expense', 'income', 'transfer'],
          },
          'tags': {'type': 'string'},
          'account': {
            'type': ['string', 'null'],
          },
          'counterparty_account': {
            'type': ['string', 'null'],
          },
          'status': {
            'type': 'string',
            'enum': ['pending', 'settled', 'reversed'],
          },
          'notes': {'type': 'string'},
        },
        'required': ['id'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'delete_transaction',
      'title': 'Delete a transaction',
      'description':
          'Permanently delete one transaction by id after explicit confirmation.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
        },
        'required': ['id'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'bulk_update_transactions',
      'title': 'Bulk update matching transactions',
      'description':
          'Update category, merchant, tags, status, or account on up to 200 filtered transactions after showing the user a preview and receiving explicit confirmation. Never use an empty filter.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'filter': _inputSchema,
          'changes': {
            'type': 'object',
            'properties': {
              'category': {'type': 'string'},
              'merchant': {'type': 'string'},
              'tags': {'type': 'string'},
              'status': {
                'type': 'string',
                'enum': ['pending', 'settled', 'reversed'],
              },
              'account': {'type': 'string'},
            },
            'additionalProperties': false,
          },
        },
        'required': ['filter', 'changes'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'create_budget',
      'title': 'Create a monthly budget',
      'description':
          'Create a monthly overall or category budget after explicit user confirmation.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'name': {'type': 'string'},
          'amount': {'type': 'number', 'exclusiveMinimum': 0},
          'currency': {'type': 'string'},
          'category': {
            'type': ['string', 'null'],
          },
          'warning_percent': {'type': 'integer', 'minimum': 25, 'maximum': 100},
        },
        'required': ['name', 'amount', 'currency'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'delete_budget',
      'title': 'Delete a budget',
      'description': 'Delete one budget after explicit user confirmation.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'id': {'type': 'integer'},
        },
        'required': ['id'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'undo_last_change',
      'title': 'Undo the last change',
      'description':
          'Undo the most recent reversible transaction or budget change when the user explicitly asks to undo it.',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'remember_preference',
      'title': 'Remember a user preference',
      'description':
          'Persist a short preference or financial goal only when the user explicitly asks Flow to remember it and confirms.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'key': {'type': 'string'},
          'value': {'type': 'string'},
        },
        'required': ['key', 'value'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'forget_preference',
      'title': 'Forget a user preference',
      'description':
          'Delete one remembered preference when the user explicitly asks.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'key': {'type': 'string'},
        },
        'required': ['key'],
        'additionalProperties': false,
      },
    },
  ];

  static const _appToolNames = {
    'get_app_state',
    'set_theme',
    'set_amount_visibility',
    'set_app_lock',
    'set_notification_capture',
    'set_currency',
    'set_sync_lookback',
    'navigate_to',
  };

  static const _mutationToolNames = {
    'create_transaction',
    'update_transaction',
    'delete_transaction',
    'bulk_update_transactions',
    'remember_preference',
    'forget_preference',
    'create_budget',
    'delete_budget',
  };

  static const _readToolNames = {
    'search_transactions',
    'summarize_transactions',
    'spending_breakdown',
    'compare_periods',
    'find_recurring_transactions',
    'detect_spending_anomalies',
    'find_duplicate_transactions',
    'forecast_cashflow',
    'get_budget_status',
    'undo_last_change',
    'get_agent_memory',
  };

  static final List<Map<String, dynamic>> _appTools = [
    {
      'name': 'get_app_state',
      'title': 'Read current app settings',
      'description':
          'Read the current theme, amount visibility, app lock, notification capture, currency, and SMS lookback settings.',
      'inputSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
    {
      'name': 'set_theme',
      'title': 'Change app theme',
      'description':
          'Actually change and persist the app appearance. Use only when the user asks to change the theme.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'mode': {
            'type': 'string',
            'enum': ['system', 'light', 'dark'],
          },
        },
        'required': ['mode'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'set_amount_visibility',
      'title': 'Show or hide money amounts',
      'description':
          'Actually show or mask monetary amounts throughout the app.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'visible': {'type': 'boolean'},
        },
        'required': ['visible'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'set_app_lock',
      'title': 'Enable or disable app lock',
      'description': 'Actually enable or disable the app authentication lock.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'enabled': {'type': 'boolean'},
        },
        'required': ['enabled'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'set_notification_capture',
      'title': 'Control notification transaction capture',
      'description':
          'Actually enable or disable automatic transaction capture from notifications. Enabling may open Android permission settings.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'enabled': {'type': 'boolean'},
        },
        'required': ['enabled'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'set_currency',
      'title': 'Change preferred currency',
      'description': 'Actually change and persist the preferred app currency.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'currency': {
            'type': 'string',
            'enum': ['INR', 'USD', 'EUR', 'GBP', 'SGD', 'AED'],
          },
        },
        'required': ['currency'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'set_sync_lookback',
      'title': 'Change SMS sync lookback',
      'description':
          'Actually change how many historical days SMS synchronization scans, from 7 through 180 days.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'days': {'type': 'integer', 'minimum': 7, 'maximum': 180},
        },
        'required': ['days'],
        'additionalProperties': false,
      },
    },
    {
      'name': 'navigate_to',
      'title': 'Open an app destination',
      'description':
          'Navigate to Flow, Activity, or You when the user asks to open that part of the app.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'destination': {
            'type': 'string',
            'enum': ['activity', 'ask_flow', 'settings'],
          },
        },
        'required': ['destination'],
        'additionalProperties': false,
      },
    },
  ];

  static const Map<String, dynamic> _inputSchema = {
    'type': 'object',
    'properties': {
      'label': {'type': 'string'},
      'from': {
        'type': ['string', 'null'],
        'format': 'date-time',
      },
      'to': {
        'type': ['string', 'null'],
        'format': 'date-time',
      },
      'merchant': {
        'type': ['string', 'null'],
      },
      'category': {
        'type': ['string', 'null'],
      },
      'direction': {
        'type': ['string', 'null'],
        'enum': ['expense', 'income', 'transfer', null],
      },
      'currency': {
        'type': ['string', 'null'],
      },
      'text': {
        'type': ['string', 'null'],
      },
      'minimum_amount': {
        'type': ['number', 'null'],
        'minimum': 0,
      },
      'maximum_amount': {
        'type': ['number', 'null'],
        'minimum': 0,
      },
      'account': {
        'type': ['string', 'null'],
      },
      'status': {
        'type': ['string', 'null'],
        'enum': ['pending', 'settled', 'reversed', null],
      },
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200},
      'continue_with_model': {
        'type': 'boolean',
        'description':
            'True only when records need further AI analysis or another tool call. Omit for ordinary lists and totals.',
      },
    },
    'additionalProperties': false,
  };

  static Map<String, dynamic> _daysSchema(
    String field,
    int minimum,
    int maximum,
  ) => {
    'type': 'object',
    'properties': {
      field: {'type': 'integer', 'minimum': minimum, 'maximum': maximum},
      'continue_with_model': {'type': 'boolean'},
    },
    'additionalProperties': false,
  };
}

/// MCP client/host adapter over the embedded server transport.
abstract interface class MoneyMcpClient {
  Future<List<McpToolDefinition>> listTools();

  Future<McpToolResult> callTool(String name, Map<String, dynamic> arguments);
}

class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.title,
    this.outputSchema,
  });

  final String name;
  final String? title;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Map<String, dynamic>? outputSchema;

  factory McpToolDefinition.fromJson(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim();
    final schema = json['inputSchema'];
    if (name == null || name.isEmpty || schema is! Map) {
      throw const FormatException('Invalid MCP tool definition.');
    }
    return McpToolDefinition(
      name: name,
      title: json['title']?.toString(),
      description: json['description']?.toString() ?? '',
      inputSchema: schema.cast<String, dynamic>(),
      outputSchema: json['outputSchema'] is Map
          ? (json['outputSchema'] as Map).cast<String, dynamic>()
          : null,
    );
  }

  Map<String, dynamic> toOllamaFunction() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': inputSchema,
    },
  };
}

class McpToolResult {
  const McpToolResult({
    required this.content,
    required this.structuredContent,
    required this.isError,
  });

  final String content;
  final Map<String, dynamic> structuredContent;
  final bool isError;
}

class LocalMoneyMcpClient implements MoneyMcpClient {
  LocalMoneyMcpClient(this.server);

  final LocalMoneyMcpServer server;
  var _nextId = 1;
  bool _initialized = false;
  Set<String> _tools = const {};
  List<McpToolDefinition>? _definitions;

  @override
  Future<List<McpToolDefinition>> listTools() async {
    await _ensureInitialized();
    final cached = _definitions;
    if (cached != null) return cached;
    final listed = await _request('tools/list', {});
    return _definitions = (listed['tools'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((tool) => McpToolDefinition.fromJson(tool.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    await _ensureInitialized();
    if (!_tools.contains(name)) {
      throw StateError('MCP tool is unavailable: $name');
    }
    final result = await _request('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    final blocks = result['content'] as List<dynamic>? ?? const [];
    final text = blocks
        .whereType<Map>()
        .where((block) => block['type'] == 'text')
        .map((block) => block['text']?.toString() ?? '')
        .join('\n');
    final structured = result['structuredContent'] is Map
        ? (result['structuredContent'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    return McpToolResult(
      content: text,
      structuredContent: structured,
      isError: result['isError'] == true,
    );
  }

  Future<List<Expense>> searchTransactions(TransactionQuery query) async {
    final result = await callTool('search_transactions', query.toJson());
    if (result.isError) {
      throw StateError('MCP tool execution failed.');
    }
    final structured = result.structuredContent;
    final records = structured['records'] as List<dynamic>? ?? const [];
    return records.whereType<Map>().map((value) {
      final json = value.cast<String, dynamic>();
      return Expense(
        id: json['id'] as int?,
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'].toString(),
        merchant: json['merchant'].toString(),
        category: json['category'].toString(),
        date: DateTime.parse(json['date'].toString()),
        originalSms: '',
        type: json['direction'].toString(),
        tags: (json['tags'] as List<dynamic>? ?? const []).join(','),
      );
    }).toList();
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _request('initialize', {
      'protocolVersion': LocalMoneyMcpServer.protocolVersion,
      'capabilities': {},
      'clientInfo': {'name': 'flow-app', 'version': '1.0.0'},
    });
    await server.handle({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    });
    final listed = await _request('tools/list', {});
    _tools = (listed['tools'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((tool) => tool['name'].toString())
        .toSet();
    _initialized = true;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> params,
  ) async {
    final response = await server.handle({
      'jsonrpc': '2.0',
      'id': _nextId++,
      'method': method,
      'params': params,
    });
    if (response == null) throw StateError('MCP server returned no response.');
    if (response['error'] != null) {
      final error = response['error'] as Map;
      throw StateError('MCP ${error['code']}: ${error['message']}');
    }
    return (response['result'] as Map).cast<String, dynamic>();
  }
}

class _McpProtocolError implements Exception {
  const _McpProtocolError(this.code, this.message);
  final int code;
  final String message;
}
