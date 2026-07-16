import 'dart:convert';

import 'package:expense_manager/services/money_chat_service.dart';
import 'package:expense_manager/services/local_money_mcp.dart';
import 'package:expense_manager/services/ollama_cloud_service.dart';
import 'package:expense_manager/services/database_helper.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('local money server negotiates MCP and lists typed tools', () async {
    final server = LocalMoneyMcpServer(DatabaseHelper.instance);
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
      containsAll(['search_transactions', 'summarize_transactions']),
    );
    expect(tools.first['inputSchema'], isA<Map<String, dynamic>>());
    expect(tools.first['outputSchema'], isA<Map<String, dynamic>>());
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

  test('money chat rejects unrelated work without contacting AI', () async {
    var requests = 0;
    final service = MoneyChatService(
      OllamaCloudService(
        apiKey: 'test',
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      ),
    );

    final answer = await service.ask('Create a Python game for me', const []);

    expect(answer.text, MoneyChatService.outOfScopeReply);
    expect(answer.sources, isEmpty);
    expect(requests, 0);
  });

  test('money chat recognizes finance and app questions', () {
    expect(
      MoneyChatService.isInScope('What did I spend this month?', const []),
      isTrue,
    );
    expect(
      MoneyChatService.isInScope('How do I update this app?', const []),
      isTrue,
    );
    expect(MoneyChatService.isInScope('Write me a poem', const []), isFalse);
  });

  test('money chat plans, retrieves, answers, and verifies', () async {
    final requests = <Map<String, dynamic>>[];
    var call = 0;
    final service = MoneyChatService(
      OllamaCloudService(
        apiKey: 'test',
        client: MockClient((request) async {
          requests.add(jsonDecode(request.body) as Map<String, dynamic>);
          call++;
          final content = switch (call) {
            1 => jsonEncode({
              'intent': 'transactions',
              'needs_clarification': false,
              'queries': [
                {
                  'label': 'primary',
                  'from': '2026-06-20T00:00:00+05:30',
                  'to': '2026-06-20T23:59:59.999999+05:30',
                  'direction': null,
                  'limit': 100,
                },
              ],
            }),
            2 => 'You had one transaction on 20 June.',
            _ => jsonEncode({
              'valid': true,
              'answer': 'You had one verified transaction on 20 June.',
              'issue': null,
            }),
          };
          return http.Response(
            jsonEncode({
              'message': {'content': content},
            }),
            200,
          );
        }),
      ),
      queryExecutor: (query) async => [
        Expense(
          id: 7,
          amount: 450,
          currency: 'INR',
          merchant: 'Cafe',
          category: 'Food',
          date: DateTime.parse('2026-06-20T12:30:00+05:30'),
          originalSms: 'private raw sms',
        ),
      ],
    );

    final answer = await service.ask('Get my transactions from 20 June');

    expect(call, 3);
    expect(answer.verified, isTrue);
    expect(answer.sources.single.id, 7);
    expect(answer.appliedFilters.single.from?.day, 20);
    expect(answer.text, contains('verified transaction'));
    final answerPrompt =
        ((requests[1]['messages'] as List)[1]
                as Map<String, dynamic>)['content']
            .toString();
    expect(answerPrompt, contains('"merchant":"Cafe"'));
    expect(answerPrompt, isNot(contains('private raw sms')));
  });

  test(
    'money chat rejects locally returned records outside the plan',
    () async {
      final service = MoneyChatService(
        OllamaCloudService(
          apiKey: 'test',
          client: MockClient((_) async {
            return http.Response(
              jsonEncode({
                'message': {
                  'content': jsonEncode({
                    'intent': 'transactions',
                    'needs_clarification': false,
                    'queries': [
                      {
                        'from': '2026-06-20T00:00:00Z',
                        'to': '2026-06-20T23:59:59Z',
                      },
                    ],
                  }),
                },
              }),
              200,
            );
          }),
        ),
        queryExecutor: (_) async => [
          Expense(
            amount: 20,
            currency: 'INR',
            merchant: 'Wrong day',
            category: 'Other',
            date: DateTime.utc(2026, 6, 21),
            originalSms: '',
          ),
        ],
      );

      expect(
        () => service.ask('Get my transactions from 20 June'),
        throwsStateError,
      );
    },
  );
}
