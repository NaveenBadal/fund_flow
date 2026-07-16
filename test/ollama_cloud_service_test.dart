import 'dart:convert';

import 'package:expense_manager/services/money_chat_service.dart';
import 'package:expense_manager/services/local_money_mcp.dart';
import 'package:expense_manager/services/ollama_cloud_service.dart';
import 'package:expense_manager/services/database_helper.dart';
import 'package:expense_manager/widgets/money_chat_sheet.dart';
import 'package:expense_manager/models/assistant_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('assistant messages round-trip through their persisted shape', () {
    final original = AssistantMessage(
      id: 4,
      user: false,
      text: 'Verified answer',
      sources: 3,
      verified: true,
      timestamp: DateTime(2026, 7, 16, 10, 30),
    );
    final restored = AssistantMessage.fromMap(original.toMap());

    expect(restored.id, 4);
    expect(restored.text, 'Verified answer');
    expect(restored.sources, 3);
    expect(restored.verified, isTrue);
    expect(restored.timestamp, original.timestamp);
  });

  test('chat converts markdown tables into mobile-friendly rows', () {
    final result = mobileFriendlyMarkdown(
      '| Date | Amount |\n| --- | --- |\n| 20 Jun | ₹450 |',
    );

    expect(result, contains('**Date:** 20 Jun'));
    expect(result, contains('**Amount:** ₹450'));
    expect(result, isNot(contains('| --- |')));
  });

  test('local money server negotiates MCP and lists typed tools', () async {
    String? appCall;
    final server = LocalMoneyMcpServer(
      DatabaseHelper.instance,
      appToolHandler: (name, arguments) async {
        appCall = name;
        return {'changed': true, ...arguments};
      },
    );
    final initialized = await server.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2025-11-25',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '1'},
      },
    });
    final listed = await server.handle({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/list',
      'params': {},
    });

    expect((initialized?['result'] as Map)['protocolVersion'], '2025-11-25');
    final tools = ((listed?['result'] as Map)['tools'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      tools.map((tool) => tool['name']),
      containsAll([
        'search_transactions',
        'summarize_transactions',
        'set_theme',
        'set_amount_visibility',
      ]),
    );
    expect(tools.first['inputSchema'], isA<Map<String, dynamic>>());
    expect(tools.first['outputSchema'], isA<Map<String, dynamic>>());
    final changed = await server.handle({
      'jsonrpc': '2.0',
      'id': 3,
      'method': 'tools/call',
      'params': {
        'name': 'set_theme',
        'arguments': {'mode': 'dark'},
      },
    });
    expect(appCall, 'set_theme');
    expect(
      ((changed?['result'] as Map)['structuredContent'] as Map)['changed'],
      isTrue,
    );
  });

  test('parses an out-of-order AI batch using stable ids', () async {
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'message': {
            'content': jsonEncode({
              'results': [
                {
                  'id': 1,
                  'type': 'not_financial',
                  'amount': null,
                  'merchant': null,
                  'category': null,
                },
                {
                  'id': 0,
                  'type': 'expense',
                  'amount': '1,249.50',
                  'merchant': 'SWIGGY',
                  'category': 'food',
                },
              ],
            }),
          },
        }),
        200,
      );
    });

    final service = OllamaCloudService(
      apiKey: 'test',
      model: 'gpt-oss:20b-cloud',
      client: client,
    );
    final results = await service.parseBatch(['debit sms', 'otp sms']);

    expect(results[0]?.amount, 1249.5);
    expect(results[0]?.category, 'Food');
    expect(results[1]?.type, 'not_financial');
    expect(requestBody['think'], 'low');
    expect(requestBody['stream'], false);
  });

  test('rejects batches above the optimized maximum', () async {
    final service = OllamaCloudService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response('{}', 200)),
    );
    expect(
      () => service.parseBatch(List.filled(13, 'sms')),
      throwsArgumentError,
    );
  });

  test('returns a grounded conversational answer', () async {
    late Map<String, dynamic> requestBody;
    final service = OllamaCloudService(
      apiKey: 'test',
      client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'message': {'content': 'Food spending is down 12% this month.'},
          }),
          200,
        );
      }),
    );

    final answer = await service.answer(
      systemPrompt: 'Use only supplied records.',
      userPrompt: 'How is food spending?',
    );

    expect(answer, 'Food spending is down 12% this month.');
    expect(requestBody['think'], 'medium');
    expect((requestBody['messages'] as List), hasLength(2));
  });

  test(
    'money chat uses role context instead of a manual prompt gate',
    () async {
      var requests = 0;
      final mcp = _FakeMoneyMcpClient();
      final service = MoneyChatService(
        OllamaCloudService(
          apiKey: 'test',
          client: MockClient((_) async {
            requests++;
            final content = requests == 1
                ? 'I can only help with Flow and your personal finances.'
                : jsonEncode({
                    'valid': true,
                    'answer':
                        'I can only help with Flow and your personal finances.',
                  });
            return http.Response(
              jsonEncode({
                'message': {'role': 'assistant', 'content': content},
              }),
              200,
            );
          }),
        ),
        mcpClient: mcp,
      );

      final answer = await service.ask('Create a Python game for me');

      expect(answer.text, contains('personal finances'));
      expect(answer.sources, isEmpty);
      expect(requests, 2);
      expect(mcp.calledTools, isEmpty);
    },
  );

  test('money chat runs an Ollama-native MCP tool loop and verifies', () async {
    final requests = <Map<String, dynamic>>[];
    var call = 0;
    final mcp = _FakeMoneyMcpClient();
    final service = MoneyChatService(
      OllamaCloudService(
        apiKey: 'test',
        client: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          call++;
          final message = switch (call) {
            1 => {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'type': 'function',
                  'function': {
                    'name': 'search_transactions',
                    'arguments': {
                      'label': 'primary',
                      'from': '2026-06-20T00:00:00+05:30',
                      'to': '2026-06-20T23:59:59.999999+05:30',
                      'limit': 100,
                    },
                  },
                },
              ],
            },
            2 => {
              'role': 'assistant',
              'content': 'You had one transaction on 20 June.',
            },
            _ => {
              'role': 'assistant',
              'content': jsonEncode({
                'valid': true,
                'answer': 'You had one verified transaction on 20 June.',
                'issue': null,
              }),
            },
          };
          return http.Response(jsonEncode({'message': message}), 200);
        }),
      ),
      mcpClient: mcp,
    );

    final answer = await service.ask(
      'What about that date?',
      history: [
        AssistantMessage(
          user: true,
          text: 'Get my transactions from 20 June',
          timestamp: DateTime(2026, 7, 16),
        ),
      ],
    );

    expect(call, 3);
    expect(mcp.calledTools, ['search_transactions']);
    expect(answer.verified, isTrue);
    expect(answer.checkedRecords, 1);
    expect(answer.sources.single.id, 7);
    expect(answer.appliedFilters.single.from?.day, 20);
    expect(answer.text, contains('verified transaction'));
    expect(requests.first['tools'], isNotEmpty);
    final firstMessages = requests.first['messages'] as List;
    expect(
      firstMessages.any(
        (message) => message['content'] == 'Get my transactions from 20 June',
      ),
      isTrue,
    );
    final followUpMessages = requests[1]['messages'] as List;
    expect(
      followUpMessages.any((message) => message['role'] == 'tool'),
      isTrue,
    );
    final toolMessage = followUpMessages.firstWhere(
      (message) => message['role'] == 'tool',
    );
    expect(toolMessage['content'], contains('"merchant":"Cafe"'));
    expect(toolMessage['content'], isNot(contains('private raw sms')));
  });

  test(
    'main chat changes settings only through a successful app tool',
    () async {
      var call = 0;
      final mcp = _FakeMoneyMcpClient();
      final service = MoneyChatService(
        OllamaCloudService(
          apiKey: 'test',
          client: MockClient((_) async {
            call++;
            final message = switch (call) {
              1 => {
                'role': 'assistant',
                'content': '',
                'tool_calls': [
                  {
                    'type': 'function',
                    'function': {
                      'name': 'set_theme',
                      'arguments': {'mode': 'dark'},
                    },
                  },
                ],
              },
              2 => {
                'role': 'assistant',
                'content': 'The app theme is now dark.',
              },
              _ => {
                'role': 'assistant',
                'content': jsonEncode({
                  'valid': true,
                  'answer': 'The app theme is now dark.',
                }),
              },
            };
            return http.Response(jsonEncode({'message': message}), 200);
          }),
        ),
        mcpClient: mcp,
      );

      final answer = await service.ask('Make this easier on my eyes at night');

      expect(mcp.calledTools, ['set_theme']);
      expect(answer.text, contains('dark'));
      expect(answer.verified, isTrue);
    },
  );
}

class _FakeMoneyMcpClient implements MoneyMcpClient {
  final calledTools = <String>[];

  @override
  Future<List<McpToolDefinition>> listTools() async => [
    const McpToolDefinition(
      name: 'search_transactions',
      description: 'Search matching local transactions.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'from': {
            'type': ['string', 'null'],
          },
          'to': {
            'type': ['string', 'null'],
          },
          'limit': {'type': 'integer'},
        },
      },
    ),
    const McpToolDefinition(
      name: 'set_theme',
      description: 'Actually change the app theme.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'mode': {
            'type': 'string',
            'enum': ['system', 'light', 'dark'],
          },
        },
        'required': ['mode'],
      },
    ),
  ];

  @override
  Future<McpToolResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    calledTools.add(name);
    if (name == 'set_theme') {
      final result = {'changed': true, 'theme': arguments['mode']};
      return McpToolResult(
        content: jsonEncode(result),
        structuredContent: result,
        isError: false,
      );
    }
    final result = {
      'applied_filter': arguments,
      'matched_count': 1,
      'totals_by_currency': {
        'INR': {'income': 0, 'expense': 450},
      },
      'records_truncated': false,
      'records': [
        {
          'id': 7,
          'date': '2026-06-20T12:30:00.000',
          'amount': 450,
          'currency': 'INR',
          'direction': 'expense',
          'merchant': 'Cafe',
          'category': 'Food',
          'tags': <String>[],
          'recurring': false,
        },
      ],
    };
    return McpToolResult(
      content: jsonEncode(result),
      structuredContent: result,
      isError: false,
    );
  }
}
