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
  const LocalMoneyMcpServer(this.database, {this.appToolHandler});

  final DatabaseHelper database;
  final AppToolHandler? appToolHandler;

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
    final isTransactionTool =
        name == 'search_transactions' || name == 'summarize_transactions';
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
    if (isSourceInspectionTool) {
      return _inspectTransactionSource(arguments.cast<String, dynamic>());
    }
    final query = TransactionQuery.fromJson(arguments.cast<String, dynamic>());
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
    final structured = _searchResult(query, records);
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(structured)},
      ],
      'structuredContent': structured,
      'isError': false,
    };
  }

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
          type: arguments['direction']?.toString() == 'income'
              ? 'income'
              : 'expense',
          tags: arguments['tags']?.toString() ?? '',
          isRecurring: arguments['recurring'] == true,
        );
        final id = await database.insertExpense(expense);
        structured = {'changed': true, 'transaction_id': id};
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
          isRecurring: arguments['recurring'] as bool?,
        );
        await database.updateExpense(updated);
        structured = {'changed': true, 'transaction_id': id};
      } else if (name == 'delete_transaction') {
        final id = (arguments['id'] as num?)?.toInt();
        if (id == null) throw ArgumentError('id is required');
        final deleted = await database.deleteExpense(id);
        structured = {'changed': deleted == 1, 'transaction_id': id};
      } else {
        final category = _requiredText(arguments, 'category');
        final remove = arguments['remove'] == true;
        if (remove) {
          await database.deleteBudget(category);
        } else {
          await database.insertOrUpdateBudget(
            Budget(
              category: category,
              limitAmount: _positiveNumber(arguments, 'limit_amount'),
              currency:
                  arguments['currency']?.toString().toUpperCase() ?? 'INR',
            ),
          );
        }
        structured = {'changed': true, 'category': category, 'removed': remove};
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
  ) => {
    'applied_filter': query.toJson(),
    'matched_count': records.length,
    'totals_by_currency': _totals(records),
    'records_truncated': records.length > query.limit,
    'records': records.take(query.limit).map(_record).toList(),
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
    'recurring': record.isRecurring,
  };

  Map<String, Map<String, double>> _totals(List<Expense> records) {
    final totals = <String, Map<String, double>>{};
    for (final record in records) {
      final currency = totals.putIfAbsent(
        record.currency,
        () => {'income': 0, 'expense': 0},
      );
      currency[record.type] = (currency[record.type] ?? 0) + record.amount;
    }
    return totals;
  }

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
            'enum': ['expense', 'income'],
          },
          'tags': {'type': 'string'},
          'recurring': {'type': 'boolean'},
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
            'enum': ['expense', 'income'],
          },
          'tags': {'type': 'string'},
          'recurring': {'type': 'boolean'},
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
      'name': 'manage_budget',
      'title': 'Create, update, or remove a budget',
      'description':
          'Set a category budget or remove it after explicit confirmation.',
      'inputSchema': {
        'type': 'object',
        'properties': {
          'category': {'type': 'string'},
          'limit_amount': {'type': 'number', 'exclusiveMinimum': 0},
          'currency': {'type': 'string'},
          'remove': {'type': 'boolean'},
        },
        'required': ['category'],
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
  };

  static const _mutationToolNames = {
    'create_transaction',
    'update_transaction',
    'delete_transaction',
    'manage_budget',
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
        'enum': ['expense', 'income', null],
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
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 200},
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

  @override
  Future<List<McpToolDefinition>> listTools() async {
    await _ensureInitialized();
    final listed = await _request('tools/list', {});
    return (listed['tools'] as List<dynamic>? ?? const [])
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
        isRecurring: json['recurring'] == true,
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
