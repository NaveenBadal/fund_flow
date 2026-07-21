import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/agent/agent_presentation.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/domain/conversation.dart';

void main() {
  group('tool result budget', () {
    test('passes small results through untouched', () {
      final message = McpToolResult(
        callId: 'a',
        tool: 'transactions_search',
        content: const {
          'transactions': [
            {'id': 1, 'amountMinor': 100},
          ],
        },
      ).toProviderMessage();
      final decoded =
          jsonDecode(message['content']! as String) as Map<String, Object?>;
      expect(decoded['ok'], isTrue);
      expect(decoded.containsKey('truncated'), isFalse);
      expect(decoded['transactions'], hasLength(1));
    });

    test('trims long lists and stays valid JSON', () {
      final many = [
        for (var i = 0; i < 2000; i++)
          {
            'id': i,
            'amountMinor': 12345,
            'merchant': 'A fairly long merchant name $i',
            'occurredAt': '2026-07-19T10:00:00.000Z',
          },
      ];
      final message = McpToolResult(
        callId: 'a',
        tool: 'transactions_search',
        content: {'transactions': many},
      ).toProviderMessage();
      final raw = message['content']! as String;

      expect(
        raw.length,
        lessThanOrEqualTo(McpToolResult.maximumContentCharacters),
      );
      // Must remain parseable: a cut string would break the provider.
      final decoded = jsonDecode(raw) as Map<String, Object?>;
      expect(decoded['transactions'], isA<List<Object?>>());
      expect((decoded['transactions']! as List).length, lessThan(2000));

      // The provider has to know the view is partial, otherwise it reads the
      // trimmed tail as data that does not exist.
      final truncated = decoded['truncated']! as Map<String, Object?>;
      expect(truncated['field'], 'transactions');
      expect(truncated['total'], 2000);
    });
  });

  group('history replay', () {
    test('keeps figures from structured parts', () {
      final message = ConversationMessage(
        author: MessageAuthor.assistant,
        text: 'You spent more this month.',
        createdAt: DateTime(2026, 7, 19),
        parts: const [
          AgentPart(
            kind: AgentPartKind.conclusion,
            data: {'text': 'You spent more this month.'},
          ),
          AgentPart(
            kind: AgentPartKind.metricRow,
            data: {
              'metrics': [
                {'label': 'Spent', 'amountMinor': 4218000, 'currency': 'INR'},
              ],
            },
          ),
          AgentPart(
            kind: AgentPartKind.breakdown,
            data: {
              'title': 'By category',
              'rows': [
                {'label': 'Food', 'amountMinor': 1240000, 'currency': 'INR'},
              ],
            },
          ),
        ],
      );

      final replay = message.providerContent;
      expect(replay, contains('You spent more this month.'));
      // The figures are the whole point: prose alone cannot answer "why is
      // that higher than last month?".
      expect(replay, contains('4218000'));
      expect(replay, contains('Food 1240000 INR'));
    });

    test('drops follow-up suggestions from replay', () {
      final message = ConversationMessage(
        author: MessageAuthor.assistant,
        text: 'Done.',
        createdAt: DateTime(2026, 7, 19),
        parts: const [
          AgentPart(kind: AgentPartKind.conclusion, data: {'text': 'Done.'}),
          AgentPart(
            kind: AgentPartKind.followUps,
            data: {
              'questions': ['What about last month?'],
            },
          ),
        ],
      );
      expect(message.providerContent, 'Done.');
    });

    test('falls back to plain text when there are no parts', () {
      final message = ConversationMessage(
        author: MessageAuthor.person,
        text: 'How much did I spend?',
        createdAt: DateTime(2026, 7, 19),
      );
      expect(message.providerContent, 'How much did I spend?');
    });
  });
}
