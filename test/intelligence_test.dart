import 'dart:convert';
import 'dart:async';

import 'package:fund_flow/agent/agent_runner.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/intelligence/ai_client.dart';
import 'package:fund_flow/domain/transaction.dart';
import 'package:fund_flow/ingestion/message_candidate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('provider adapter sends tools and decodes native tool calls', () async {
    late Map<String, dynamic> requestBody;
    final client = AiClient(
      client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'done': true,
            'message': {
              'role': 'assistant',
              'content': '',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'function': {
                    'name': 'settings_get',
                    'arguments': <String, Object?>{},
                  },
                },
              ],
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);
    final provider = client.configured(
      endpoint: 'https://provider.example',
      apiKey: 'secret',
      model: 'agent-model',
    );
    final turn = await provider.nextTurn(
      messages: const [
        {'role': 'user', 'content': 'What are my settings?'},
      ],
      tools: const [
        McpToolDefinition(
          name: 'settings_get',
          description: 'Read settings',
          inputSchema: {
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
          risk: McpRisk.read,
        ),
      ],
    );
    expect(requestBody['model'], 'agent-model');
    expect(requestBody['think'], 'low');
    expect(requestBody['options'], {'temperature': 0});
    expect(requestBody['tools'], hasLength(1));
    expect(turn.toolCalls.single.name, 'settings_get');
    expect(turn.toolCalls.single.arguments, isEmpty);
  });

  test(
    'stream preserves thinking, emits content deltas and requires done',
    () async {
      final chunks = [
        {
          'done': false,
          'message': {'role': 'assistant', 'thinking': 'check tools'},
        },
        {
          'done': false,
          'message': {'role': 'assistant', 'content': 'Hello'},
        },
        {
          'done': true,
          'message': {'role': 'assistant', 'content': ''},
        },
      ].map(jsonEncode).join('\n');
      final client = AiClient(
        client: MockClient((_) async => http.Response(chunks, 200)),
      );
      addTearDown(client.close);
      final deltas = <String>[];
      final turn = await client
          .configured(
            endpoint: 'http://localhost:11434',
            apiKey: 'secret',
            model: 'model',
          )
          .nextTurn(
            messages: const [],
            tools: const [],
            onContentDelta: deltas.add,
          );
      expect(turn.content, 'Hello');
      expect(turn.message['thinking'], 'check tools');
      expect(deltas, ['Hello']);
    },
  );

  test('stop cancels an active provider stream', () async {
    final stream = StreamController<List<int>>();
    final client = AiClient(
      client: MockClient.streaming(
        (_, _) async => http.StreamedResponse(stream.stream, 200),
      ),
    );
    addTearDown(client.close);
    final token = AgentCancellationToken();
    final future = client
        .configured(
          endpoint: 'http://localhost:11434',
          apiKey: 'secret',
          model: 'model',
        )
        .nextTurn(messages: const [], tools: const [], cancellation: token);
    await Future<void>.delayed(Duration.zero);
    token.cancel();
    await expectLater(future, throwsA(isA<AgentRunCancelled>()));
  });

  test('truncated provider stream is rejected', () async {
    final client = AiClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'done': false,
            'message': {'role': 'assistant', 'content': 'Partial'},
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);
    expect(
      () => client
          .configured(
            endpoint: 'http://localhost:11434',
            apiKey: 'secret',
            model: 'model',
          )
          .nextTurn(messages: const [], tools: const []),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'ingestion exposes the exact safe request and raw provider response',
    () async {
      String? sent;
      String? returned;
      Uri? requestUri;
      final candidate = MessageCandidate(
        sender: 'Bank',
        body: 'Payment body',
        receivedAt: DateTime(2026, 7, 18),
      );
      final responseBody = jsonEncode({
        'message': {
          'content': jsonEncode({
            'results': [
              {
                'id': candidate.fingerprint,
                'decision': 'not_transaction',
                'reason': 'No completed movement of money.',
              },
            ],
          }),
        },
      });
      final client = AiClient(
        client: MockClient((request) async {
          requestUri = request.url;
          return http.Response(responseBody, 200);
        }),
      );
      addTearDown(client.close);

      await client.analyzeMessages(
        endpoint: 'http://localhost:11434',
        apiKey: 'secret-not-logged',
        model: 'model',
        candidates: [candidate],
        source: TransactionSource.message,
        now: DateTime(2026, 7, 18),
        onRequest: (value) => sent = value,
        onResponse: (value) => returned = value,
      );

      expect(sent, contains('Payment body'));
      expect(sent, isNot(contains('secret-not-logged')));
      expect(requestUri?.path, '/v1/chat/completions');
      final request = jsonDecode(sent!) as Map<String, Object?>;
      expect(request['reasoning_effort'], 'low');
      expect(request['temperature'], 0);
      expect(request['max_tokens'], 2400);
      expect(request['response_format'], isA<Map>());
      expect(returned, responseBody);
    },
  );

  test('invalid ingestion output is corrected by one bounded AI retry', () async {
    var calls = 0;
    final candidate = MessageCandidate(
      sender: 'Bank',
      body: 'Sent Rs.279 to Wynk',
      receivedAt: DateTime(2026, 7, 18),
    );
    final requests = <String>[];
    final responses = <String>[];
    final client = AiClient(
      client: MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'message': {
                'content':
                    '```json\n[{"id":"${candidate.fingerprint}","amount":27900}]\n```',
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'message': {
              'content': jsonEncode({
                'results': [
                  {
                    'id': candidate.fingerprint,
                    'decision': 'transaction',
                    'reason': 'Completed outgoing transfer.',
                    'amountMinor': 27900,
                    'currency': 'INR',
                    'direction': 'outgoing',
                    'merchant': 'Wynk',
                    'category': 'Subscription',
                    'occurredAt': '2026-07-18T00:00:00',
                    'confidence': 0.95,
                  },
                ],
              }),
            },
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final result = await client.analyzeMessages(
      endpoint: 'http://localhost:11434',
      apiKey: 'secret',
      model: 'gpt-oss:20b',
      candidates: [candidate],
      source: TransactionSource.message,
      now: DateTime(2026, 7, 18, 12),
      onRequest: requests.add,
      onResponse: responses.add,
    );

    expect(calls, 2);
    expect(requests, hasLength(2));
    expect(responses, hasLength(2));
    expect(requests.last, contains('previous output was rejected'));
    expect(result.results.single.transaction?.amountMinor, 27900);
  });
}
