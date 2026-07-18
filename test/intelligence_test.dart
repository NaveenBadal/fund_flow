import 'dart:convert';

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
    expect(requestBody['tools'], hasLength(1));
    expect(turn.toolCalls.single.name, 'settings_get');
    expect(turn.toolCalls.single.arguments, isEmpty);
  });

  test(
    'ingestion exposes the exact safe request and raw provider response',
    () async {
      String? sent;
      String? returned;
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
        client: MockClient((_) async => http.Response(responseBody, 200)),
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
      expect(returned, responseBody);
    },
  );
}
