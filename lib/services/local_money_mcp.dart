import 'dart:convert';

import '../models/expense.dart';
import '../models/transaction_query.dart';
import 'database_helper.dart';

/// Embedded MCP server for private, read-only financial tools.
///
/// It implements the MCP 2025-11-25 lifecycle and tool methods over an
/// in-process JSON-RPC transport, keeping SQLite inaccessible to the model.
class LocalMoneyMcpServer {
  const LocalMoneyMcpServer(this.database);

  final DatabaseHelper database;

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
        'tools/list' => {'tools': _tools},
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
        'description':
            'Private read-only access to the on-device money database',
      },
    };
  }

  Future<Map<String, dynamic>> _callTool(dynamic params) async {
    if (params is! Map) {
      throw const _McpProtocolError(-32602, 'Missing tool parameters');
    }
    final name = params['name']?.toString();
    if (name != 'search_transactions' && name != 'summarize_transactions') {
      throw _McpProtocolError(-32602, 'Unknown tool: $name');
    }
    final arguments = params['arguments'];
    if (arguments is! Map) {
      return _toolError('Tool arguments must be an object.');
    }
    final query = TransactionQuery.fromJson(arguments.cast<String, dynamic>());
    final records = await database.queryTransactions(query);
    if (records.any((record) => !query.matches(record))) {
      return _toolError('Database result failed local filter validation.');
    }
    final structured = name == 'search_transactions'
        ? _searchResult(query, records)
        : _summaryResult(query, records);
    return {
      'content': [
        {'type': 'text', 'text': jsonEncode(structured)},
      ],
      'structuredContent': structured,
      'isError': false,
    };
  }

  Map<String, dynamic> _searchResult(
    TransactionQuery query,
    List<Expense> records,
  ) => {
    'applied_filter': query.toJson(),
    'matched_count': records.length,
    'records': records.map(_record).toList(),
  };

  Map<String, dynamic> _summaryResult(
    TransactionQuery query,
    List<Expense> records,
  ) => {
    'applied_filter': query.toJson(),
    'matched_count': records.length,
    'totals_by_currency': _totals(records),
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

  static final List<Map<String, dynamic>> _tools = [
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
          'records': {'type': 'array'},
        },
        'required': ['applied_filter', 'matched_count', 'records'],
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
class LocalMoneyMcpClient {
  LocalMoneyMcpClient(this.server);

  final LocalMoneyMcpServer server;
  var _nextId = 1;
  bool _initialized = false;
  Set<String> _tools = const {};

  Future<List<Expense>> searchTransactions(TransactionQuery query) async {
    await _ensureInitialized();
    if (!_tools.contains('search_transactions')) {
      throw StateError('MCP search_transactions tool is unavailable.');
    }
    final result = await _request('tools/call', {
      'name': 'search_transactions',
      'arguments': query.toJson(),
    });
    if (result['isError'] == true) {
      throw StateError('MCP tool execution failed.');
    }
    final structured = (result['structuredContent'] as Map)
        .cast<String, dynamic>();
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
