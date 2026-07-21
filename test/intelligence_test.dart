import 'dart:convert';
import 'dart:async';

import 'package:fund_flow/agent/agent_runner.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/intelligence/ai_client.dart';
import 'package:fund_flow/intelligence/gemini_adapter.dart';
import 'package:fund_flow/intelligence/model_catalog.dart';
import 'package:fund_flow/domain/ai_provider.dart';
import 'package:fund_flow/domain/transaction.dart';
import 'package:fund_flow/ingestion/ai_message_ingestion.dart';
import 'package:fund_flow/ingestion/message_candidate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  _emptyContentBlamesReasoningBudget();
  _retiredModelSurfacesProviderReason();
  _geminiSchemaDropsUnsupportedKeywords();
  _recommendPrefersRoleSeedWhenServed();
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
      provider: AiProvider.ollama,
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
    expect(requestBody['keep_alive'], '10m');
    expect(requestBody['options'], {'temperature': 0, 'num_predict': 1200});
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
          'total_duration': 9000000,
          'prompt_eval_count': 120,
          'eval_count': 8,
        },
      ].map(jsonEncode).join('\n');
      final client = AiClient(
        client: MockClient((_) async => http.Response(chunks, 200)),
      );
      addTearDown(client.close);
      final deltas = <String>[];
      final turn = await client
          .configured(
            provider: AiProvider.ollama,
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
      expect(turn.metrics?.totalDurationNs, 9000000);
      expect(turn.metrics?.promptTokens, 120);
      expect(turn.metrics?.outputTokens, 8);
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
          provider: AiProvider.ollama,
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
            provider: AiProvider.ollama,
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
                'id': 0,
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
        provider: AiProvider.ollama,
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
      expect(requestUri?.path, '/api/chat');
      final request = jsonDecode(sent!) as Map<String, Object?>;
      // Never false: disabling reasoning on this model lengthens it, which
      // exhausts the output budget and returns empty content.
      expect(request['think'], 'low');
      expect(request['keep_alive'], '10m');
      // Constrained decoding makes malformed JSON structurally impossible.
      expect(request['format'], IngestionPrompt.responseSchema);
      // Budget scales with batch size over a floor that leaves headroom for
      // a verbose reasoning run on a small batch.
      expect(request['options'], {'temperature': 0, 'num_predict': 1024});
      final messages = request['messages'] as List;
      final userPayload =
          jsonDecode((messages.last as Map)['content'].toString()) as Map;
      expect(((userPayload['messages'] as List).single as Map)['id'], 0);
      expect(sent, isNot(contains(candidate.fingerprint)));
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
                    'id': 0,
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
      provider: AiProvider.ollama,
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

  test('native ingestion retries a transient cloud failure', () async {
    var calls = 0;
    final candidate = MessageCandidate(
      sender: 'Bank',
      body: 'Statement is ready.',
      receivedAt: DateTime(2026, 7, 18),
    );
    final client = AiClient(
      client: MockClient((_) async {
        calls++;
        if (calls == 1) return http.Response('temporarily unavailable', 503);
        return http.Response(
          jsonEncode({
            'message': {
              'content': jsonEncode({
                'results': [
                  {
                    'id': 0,
                    'decision': 'not_transaction',
                    'reason': 'Statement notice only.',
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
      provider: AiProvider.ollama,
      endpoint: 'https://ollama.com',
      apiKey: 'secret',
      model: 'gpt-oss:20b',
      candidates: [candidate],
      source: TransactionSource.message,
      now: DateTime(2026, 7, 18),
    );

    expect(calls, 2);
    expect(result.results.single.decision, IngestionDecision.notTransaction);
  });
}

void _geminiSchemaDropsUnsupportedKeywords() {
  test('Gemini schema sanitizer strips additionalProperties recursively', () {
    // Gemini's functionDeclarations.parameters rejects the whole request if it
    // sees a keyword outside its OpenAPI subset. The canonical tool schemas set
    // additionalProperties on every nested object, so it must be gone at every
    // depth while the real schema shape survives.
    final schema = McpSchema.object(
      properties: {
        'filter': McpSchema.object(
          properties: {'merchant': McpSchema.string()},
        ),
        'tags': {'type': 'array', 'items': McpSchema.string()},
      },
      required: ['filter'],
    );

    final sanitized = sanitizeGeminiSchema(schema) as Map;

    expect(sanitized.containsKey('additionalProperties'), isFalse);
    final props = sanitized['properties'] as Map;
    final filter = props['filter'] as Map;
    expect(filter.containsKey('additionalProperties'), isFalse);
    final items = (props['tags'] as Map)['items'] as Map;
    expect(items.containsKey('additionalProperties'), isFalse);
    // The parts Gemini does understand are untouched.
    expect(sanitized['type'], 'object');
    expect(sanitized['required'], ['filter']);
    expect((filter['properties'] as Map).containsKey('merchant'), isTrue);
  });
}

void _recommendPrefersRoleSeedWhenServed() {
  test('recommend keeps the role seed when the catalog serves it', () {
    // The parsing and chat fields share one recommendedContains list, and for
    // Gemini "flash" also matches "flash-lite", so substring matching alone
    // collapses both fields onto the same lite model. When the curated seed is
    // actually served it must win, keeping the light model on parsing and the
    // stronger one on chat.
    final catalog = [
      'gemini-2.0-flash-lite',
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
    ];

    expect(
      ModelCatalog.recommend(
        provider: AiProvider.gemini,
        models: catalog,
        seed: 'gemini-flash-lite-latest',
      ),
      'gemini-flash-lite-latest',
    );
    expect(
      ModelCatalog.recommend(
        provider: AiProvider.gemini,
        models: catalog,
        seed: 'gemini-flash-latest',
      ),
      'gemini-flash-latest',
    );
    // Seed absent: fall back to the substring net rather than crash.
    expect(
      ModelCatalog.recommend(
        provider: AiProvider.gemini,
        models: const ['gemini-2.0-flash-lite', 'gemini-2.5-pro'],
        seed: 'gemini-flash-latest',
      ),
      'gemini-2.0-flash-lite',
    );
  });
}

void _retiredModelSurfacesProviderReason() {
  test('a retired model reports what the provider said', () async {
    // Ollama answers 410 and names the model and its retirement date. The
    // body used to be drained, leaving only a status code to report.
    final client = AiClient(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': 'qwen3-coder:480b was retired at 2026-07-15 00:00:00 PDT',
          }),
          410,
        ),
      ),
    );
    addTearDown(client.close);

    final provider = client.configured(
      provider: AiProvider.ollama,
      endpoint: 'https://ollama.com',
      apiKey: 'k',
      model: 'qwen3-coder:480b-cloud',
    );

    await expectLater(
      provider.nextTurn(messages: const [], tools: const []),
      throwsA(
        isA<AiRequestFailure>()
            .having((e) => e.statusCode, 'statusCode', 410)
            .having((e) => e.detail, 'detail', contains('was retired')),
      ),
    );
  });
}

void _emptyContentBlamesReasoningBudget() {
  test('empty content alongside reasoning names the real cause', () async {
    // Observed on Ollama Cloud: reasoning consumed the entire output budget
    // and content came back empty, which read as "no classifications" and
    // implied the messages were at fault.
    final client = AiClient(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'message': {
              'role': 'assistant',
              'content': '',
              'thinking': 'We need to classify these messages. First...',
            },
          }),
          200,
        ),
      ),
    );
    addTearDown(client.close);

    await expectLater(
      client.analyzeMessages(
        provider: AiProvider.ollama,
        endpoint: 'https://ollama.com',
        apiKey: 'k',
        model: 'gpt-oss:20b-cloud',
        candidates: [
          MessageCandidate(
            sender: 'HDFCBK',
            body: 'Spent Rs 320.00 at Zomato',
            receivedAt: DateTime(2026, 7, 19),
          ),
        ],
        source: TransactionSource.message,
        now: DateTime(2026, 7, 19),
      ),
      throwsA(
        isA<IngestionSchemaException>().having(
          (e) => e.message,
          'message',
          contains('reasoning'),
        ),
      ),
    );
  });
}
