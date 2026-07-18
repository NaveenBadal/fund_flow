import 'package:fund_flow/agent/agent_runner.dart';
import 'package:fund_flow/agent/agent_proposal.dart';
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

  test('compose JSON emitted as content remains a structured answer', () async {
    const content =
        '{"parts":[{"type":"conclusion","text":"Hello!"},{"type":"followUps","questions":["How can I help?"]}]}';
    final provider = _FakeProvider([
      const ProviderTurn(
        message: {'role': 'assistant', 'content': content},
        content: content,
        toolCalls: [],
      ),
    ]);
    final result = await AgentRunner(provider: provider, server: server).run(
      question: 'Hi',
      now: DateTime(2026, 7, 18),
      locale: 'en_IN',
      timeZone: 'Asia/Kolkata',
    );
    expect(result.presentation.unstructured, isFalse);
    expect(result.presentation.parts, hasLength(2));
  });

  test('briefing, anomaly and duplicate tools stay deterministic', () async {
    final values = [
      for (final entry in [
        (1, 10000, DateTime(2026, 7, 1)),
        (2, 10000, DateTime(2026, 7, 2)),
        (3, 10000, DateTime(2026, 7, 2, 12)),
        (4, 50000, DateTime(2026, 7, 3)),
        (5, 50000, DateTime(2026, 7, 3, 1)),
      ])
        MoneyTransaction(
          id: entry.$1,
          amountMinor: entry.$2,
          currency: 'INR',
          direction: TransactionDirection.outgoing,
          merchant: 'Calm Cafe',
          category: 'Food',
          occurredAt: entry.$3,
          source: TransactionSource.message,
        ),
    ];
    final advanced = LocalMcpServer(
      transactions: () => values,
      preferences: () => const AppPreferences(),
    );
    Future<Map<String, Object?>> call(String name) async =>
        (await advanced.execute(
          McpToolCall(
            id: name,
            name: name,
            arguments: const {'from': '2026-07-01', 'to': '2026-07-31'},
          ),
        )).result.content;

    final briefing = await call('finance_briefing');
    final anomalies = await call('finance_anomalies');
    final duplicates = await call('finance_duplicates');

    expect(briefing['checkedCount'], 5);
    expect(anomalies['rows'], isNotEmpty);
    expect(duplicates['rows'], isNotEmpty);
    expect(duplicates['method'], contains('never automatically deleted'));
  });

  test(
    'unsupported transaction citations are rejected and recomposed',
    () async {
      final provider = _FakeProvider([
        _toolTurn('finance_summary', {
          'from': '2026-07-01',
          'to': '2026-07-31',
        }),
        _toolTurn('answer_compose', {
          'parts': [
            {'type': 'conclusion', 'text': 'Unsupported citation.'},
            {
              'type': 'transactionList',
              'transactionIds': [999],
            },
            {'type': 'sourceNote', 'text': 'One checked record.'},
          ],
        }),
        _toolTurn('answer_compose', {
          'parts': [
            {'type': 'conclusion', 'text': 'Verified answer.'},
            {
              'type': 'transactionList',
              'transactionIds': [7],
            },
            {'type': 'sourceNote', 'text': 'July; INR; one checked record.'},
          ],
        }),
      ]);

      final result = await AgentRunner(provider: provider, server: server).run(
        question: 'Summarize July.',
        now: DateTime(2026, 7, 18),
        locale: 'en_IN',
        timeZone: 'Asia/Kolkata',
      );

      expect(result.presentation.plainText, contains('Verified answer'));
      expect(
        provider.messages
            .where((message) => message['role'] == 'tool')
            .last['content'],
        contains('no capability returned'),
      );
    },
  );

  test('durable financial memory is readable and approval gated', () async {
    final memoryServer = LocalMcpServer(
      transactions: () => const [],
      preferences: () => const AppPreferences(),
      financialMemory: () async => [
        {'key': 'salary_account', 'value': 'HDFC 6942'},
      ],
    );
    final listed = await memoryServer.execute(
      const McpToolCall(id: 'read', name: 'memory_list', arguments: {}),
    );
    final proposed = await memoryServer.execute(
      const McpToolCall(
        id: 'write',
        name: 'memory_set',
        arguments: {'key': 'rent_merchant', 'value': 'Landlord'},
      ),
    );

    expect(listed.result.content['count'], 1);
    expect(proposed.proposal?.kind, AgentProposalKind.setMemory);
    expect(proposed.result.content['status'], 'approval_required');
  });

  test('performance telemetry is private and locally summarized', () async {
    final telemetryServer = LocalMcpServer(
      transactions: () => const [],
      preferences: () => const AppPreferences(),
      agentTelemetry: (limit) async => [
        {
          'model': 'gpt-oss:20b-cloud',
          'elapsedMs': 800,
          'providerDurationMs': 700,
          'turns': 2,
          'calls': 2,
          'promptTokens': 900,
          'outputTokens': 120,
        },
        {
          'model': 'gpt-oss:20b-cloud',
          'elapsedMs': 1200,
          'providerDurationMs': 1000,
          'turns': 2,
          'calls': 3,
          'promptTokens': 1100,
          'outputTokens': 180,
        },
      ],
    );
    final result = await telemetryServer.execute(
      const McpToolCall(
        id: 'performance',
        name: 'agent_performance',
        arguments: {'limit': 10},
      ),
    );

    expect(result.result.content['averageElapsedMs'], 1000);
    expect(result.result.content['averageTurns'], 2);
    expect(result.result.content['privacy'], contains('No question'));
  });

  test('broad finance question stays within a two-turn agent budget', () async {
    final provider = _FakeProvider([
      _toolTurn('finance_briefing', {'from': '2026-07-01', 'to': '2026-07-31'}),
      _toolTurn('answer_compose', {
        'parts': [
          {'type': 'conclusion', 'text': 'Your July briefing is ready.'},
          {
            'type': 'sourceNote',
            'text': 'July 2026; all currencies; one checked record.',
          },
        ],
      }),
    ]);
    final result = await AgentRunner(provider: provider, server: server).run(
      question: 'Give me my financial briefing.',
      now: DateTime(2026, 7, 18),
      locale: 'en_IN',
      timeZone: 'Asia/Kolkata',
    );

    expect(result.turns, 2);
    expect(result.calls, 2);
    expect(provider.messages.first['content'], contains('untrusted data'));
  });
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
    void Function(String delta)? onContentDelta,
    AgentCancellationToken? cancellation,
  }) async {
    this.messages
      ..clear()
      ..addAll(messages);
    return turns[index++];
  }
}
