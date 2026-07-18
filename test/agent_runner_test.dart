import 'package:fund_flow/agent/agent_runner.dart';
import 'package:fund_flow/agent/local_mcp_server.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/domain/preferences.dart';
import 'package:fund_flow/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LocalMcpServer server;
  setUp(() {
    server = LocalMcpServer(
      transactions: () => [
        MoneyTransaction(
          id: 7,
          amountMinor: 45000,
          currency: 'INR',
          direction: TransactionDirection.outgoing,
          merchant: 'Calm Cafe',
          category: 'Food',
          occurredAt: DateTime(2026, 7, 10),
          source: TransactionSource.message,
        ),
      ],
      preferences: () => const AppPreferences(),
    );
  });

  test('agent completes a multi-tool read with typed answer', () async {
    final provider = _FakeProvider([
      _toolTurn('finance_summary', {'from': '2026-07-01', 'to': '2026-07-31'}),
      _toolTurn('transactions_search', {
        'from': '2026-07-01',
        'to': '2026-07-31',
        'limit': 10,
      }),
      _toolTurn('answer_compose', {
        'parts': [
          {'type': 'conclusion', 'text': 'You spent ₹450 this month.'},
          {
            'type': 'transactionList',
            'transactionIds': [7],
          },
          {
            'type': 'sourceNote',
            'text': 'Calculated from one local transaction.',
          },
        ],
      }),
    ]);
    final result = await AgentRunner(provider: provider, server: server).run(
      question: 'What did I spend?',
      now: DateTime(2026, 7, 18),
      locale: 'en_IN',
      timeZone: 'Asia/Kolkata',
    );
    expect(result.events.map((event) => event.tool), [
      'finance_summary',
      'transactions_search',
      'answer_compose',
    ]);
    expect(result.presentation.parts, hasLength(3));
    expect(
      provider.messages.where((message) => message['role'] == 'tool'),
      hasLength(2),
    );
  });

  test('proposal stops before execution', () async {
    final result =
        await AgentRunner(
          provider: _FakeProvider([
            _toolTurn('transactions_update', {'id': 7, 'category': 'Dining'}),
          ]),
          server: server,
        ).run(
          question: 'Move Calm Cafe to Dining',
          now: DateTime(2026, 7, 18),
          locale: 'en_IN',
          timeZone: 'Asia/Kolkata',
        );
    expect(result.proposal?.affectedIds, [7]);
    expect(
      result.presentation.parts.any((part) => part.kind.name == 'proposal'),
      isTrue,
    );
  });

  test('cancelled run never calls provider', () async {
    final token = AgentCancellationToken()..cancel();
    final provider = _FakeProvider([]);
    expect(
      () => AgentRunner(provider: provider, server: server).run(
        question: 'Stop',
        now: DateTime(2026, 7, 18),
        locale: 'en_IN',
        timeZone: 'Asia/Kolkata',
        cancellation: token,
      ),
      throwsA(isA<AgentRunCancelled>()),
    );
    expect(provider.messages, isEmpty);
  });

  test(
    'update questions have authoritative updater routing and tool result',
    () async {
      server = LocalMcpServer(
        transactions: () => const [],
        preferences: () => const AppPreferences(),
        updateStatus: () async => {
          'supportedOnThisBuild': true,
          'status': 'available',
          'latestBuildNumber': 91,
        },
      );
      final provider = _FakeProvider([
        _toolTurn('app_update_status', {}),
        _toolTurn('answer_compose', {
          'parts': [
            {'type': 'conclusion', 'text': 'A verified update is available.'},
          ],
        }),
      ]);
      final result = await AgentRunner(provider: provider, server: server).run(
        question: 'Is an updater available?',
        now: DateTime(2026, 7, 18),
        locale: 'en_IN',
        timeZone: 'Asia/Kolkata',
      );
      expect(result.events.first.tool, 'app_update_status');
      expect(
        provider.messages.first['content'],
        contains('MUST call app_update_status'),
      );
      final toolMessage = provider.messages.where(
        (message) => message['role'] == 'tool',
      );
      expect(toolMessage.single['content'], contains('updaterAvailable'));
    },
  );
}

ProviderTurn _toolTurn(String name, Map<String, Object?> arguments) =>
    ProviderTurn(
      content: '',
      message: {
        'role': 'assistant',
        'content': '',
        'tool_calls': [
          {
            'id': 'call_$name',
            'function': {'name': name, 'arguments': arguments},
          },
        ],
      },
      toolCalls: [
        McpToolCall(id: 'call_$name', name: name, arguments: arguments),
      ],
    );

class _FakeProvider implements AgentProvider {
  _FakeProvider(this.turns);
  final List<ProviderTurn> turns;
  final List<Map<String, Object?>> messages = [];
  var index = 0;

  @override
  Future<ProviderTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<McpToolDefinition> tools,
  }) async {
    this.messages
      ..clear()
      ..addAll(messages);
    return turns[index++];
  }
}
