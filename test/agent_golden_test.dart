import 'package:flutter_test/flutter_test.dart';

import 'package:fund_flow/agent/agent_presentation.dart';
import 'package:fund_flow/agent/agent_runner.dart';
import 'package:fund_flow/agent/local_mcp_server.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/domain/preferences.dart';
import 'package:fund_flow/domain/transaction.dart';

/// Recorded provider behaviour behind each defect found by running the app.
///
/// Every one of these was a real answer on a real screen: a briefing that
/// said no data existed while the ledger held months of it, a comparison
/// shown as raw JSON, a duration printed as currency. Unit tests did not
/// catch any of them because each needed a specific provider turn to
/// reproduce. Replaying those turns is what keeps them fixed.
void main() {
  late List<MoneyTransaction> ledger;
  late LocalMcpServer server;

  setUp(() {
    ledger = [
      _transaction(id: 1, merchant: 'Zomato', category: 'Food'),
      _transaction(
        id: 2,
        merchant: 'Adobe',
        category: 'Subscriptions',
        amountMinor: 169900,
      ),
    ];
    server = LocalMcpServer(
      transactions: () => ledger,
      preferences: () => const AppPreferences(),
    );
  });

  Future<AgentRunResult> run(List<ProviderTurn> turns, {String? question}) =>
      AgentRunner(provider: _FakeProvider(turns), server: server).run(
        question: question ?? 'How am I doing?',
        now: DateTime(2026, 7, 20),
        locale: 'en_IN',
        timeZone: 'Asia/Kolkata',
      );

  test('an empty period hands back the ledger span to retry from', () async {
    // The model trusted its training-era sense of "this month" and asked for
    // a period the ledger does not cover. Answering "no data" there was the
    // original reported bug.
    final empty = await server.execute(
      const McpToolCall(
        id: 'empty',
        name: 'finance_briefing',
        arguments: {'from': '2024-01-01', 'to': '2024-01-31'},
      ),
    );
    // The result must carry the range to re-query, not just an empty set.
    expect(empty.result.content['ledgerCoverage'], isNotNull);
    expect(empty.result.content['hint'], contains('Re-query'));

    // And the loop must be able to act on it: wrong period, then right one.
    final result = await run([
      _toolTurn('finance_briefing', {'from': '2024-01-01', 'to': '2024-01-31'}),
      _toolTurn('finance_briefing', {'from': '2026-07-01', 'to': '2026-07-31'}),
      _composeTurn([
        {'type': 'conclusion', 'text': 'Recovered and answered.'},
        {'type': 'sourceNote', 'text': 'July 2026; INR; two checked records.'},
      ]),
    ]);
    expect(result.events.map((event) => event.tool), [
      'finance_briefing',
      'finance_briefing',
      'answer_compose',
    ]);
    expect(result.events.every((event) => !event.isError), isTrue);
    expect(result.evidenceTransactionIds, containsAll([1, 2]));
  });

  test('"both" and filled-but-empty arguments still mean no filter', () async {
    // Verbatim argument shape observed from gpt-oss on device.
    const filled = {
      'account': '',
      'category': '',
      'currency': '',
      'direction': 'both',
      'from': '',
      'limit': 20,
      'maximumMinor': 0,
      'merchant': '',
      'minimumMinor': 0,
      'offset': 0,
      'reviewState': '',
      'source': '',
      'to': '',
    };
    final search = await server.execute(
      const McpToolCall(
        id: 'filled',
        name: 'transactions_search',
        arguments: filled,
      ),
    );
    expect(search.result.isError, isFalse);
    expect(search.result.content['total'], 2);

    final result = await run([
      _toolTurn('transactions_search', filled),
      _composeTurn([
        {'type': 'conclusion', 'text': 'Found them.'},
        {'type': 'sourceNote', 'text': 'All records; INR; two checked.'},
      ]),
    ]);
    expect(result.events.first.isError, isFalse);
  });

  test('a breakdown carries a total covering groups the limit cut', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'break',
        name: 'finance_breakdown',
        arguments: {
          'from': '2026-07-01',
          'to': '2026-07-31',
          'groupBy': 'category',
          'currency': 'INR',
          'limit': 1,
        },
      ),
    );
    final content = execution.result.content;
    expect((content['rows'] as List), hasLength(1));
    expect(content['rowsTotal'], 2);
    final totals = (content['totals'] as List).cast<Map>();
    // Both categories, not only the row that survived the limit.
    expect(totals.single['amountMinor'], 194900);
  });

  test(
    'a comparison sent as a bare object still renders as an answer',
    () async {
      // The provider skipped the compose call and emitted one part object with
      // no prose around it, which used to be shown to the person as raw JSON.
      final result = await run([
        _contentTurn(
          '{"type":"comparison","title":"June vs July",'
          '"currentLabel":"July","currentMinor":12789027,'
          '"previousLabel":"June","previousMinor":11982863,'
          '"currency":"INR","detail":"Spending fell by 6,762.64."}',
        ),
      ]);
      expect(result.presentation.unstructured, isFalse);
      expect(result.presentation.parts.first.kind, AgentPartKind.conclusion);
      expect(
        result.presentation.parts.first.data['text'],
        contains('Spending fell'),
      );
    },
  );

  test(
    'the conclusion leads whatever order the provider composed in',
    () async {
      final result = await run([
        _composeTurn([
          {
            'type': 'breakdown',
            'title': 'By category',
            'rows': [
              {'label': 'Food', 'amountMinor': 25000, 'currency': 'INR'},
            ],
          },
          {'type': 'sourceNote', 'text': 'July 2026.'},
          {'type': 'conclusion', 'text': 'Food led your spending.'},
        ]),
      ]);
      expect(result.presentation.parts.first.kind, AgentPartKind.conclusion);
      expect(result.presentation.parts.last.kind, AgentPartKind.sourceNote);
    },
  );

  test('a duration is never rendered as currency', () async {
    final result = await run([
      _composeTurn([
        {'type': 'conclusion', 'text': 'About 4.5 seconds.'},
        {
          'type': 'metricRow',
          'metrics': [
            {'label': 'Average elapsed', 'amountMinor': 101, 'currency': 'ms'},
          ],
        },
      ]),
    ]);
    final metric =
        ((result.presentation.parts
                        .singleWhere(
                          (part) => part.kind == AgentPartKind.metricRow,
                        )
                        .data['metrics'])
                    as List)
                .single
            as Map;
    expect(metric.containsKey('currency'), isFalse);
    expect(metric['value'], '101 ms');
  });

  test('a mutating call stops at a proposal and changes nothing', () async {
    final result = await run([
      _toolTurn('transactions_update', {'id': 1, 'category': 'Dining'}),
      _composeTurn([
        {'type': 'conclusion', 'text': 'Prepared the change.'},
      ]),
    ]);
    expect(result.proposal, isNotNull);
    expect(result.proposal!.affectedFingerprint[1], isNotNull);
    expect(ledger.first.category, 'Food');
  });

  test('a badly typed mutation is refused before any proposal', () async {
    final result = await run([
      _toolTurn('transactions_delete', {'id': 'one'}),
      _composeTurn([
        {'type': 'conclusion', 'text': 'Could not do that.'},
        {'type': 'sourceNote', 'text': 'No records were changed.'},
      ]),
    ]);
    expect(result.events.first.isError, isTrue);
    expect(result.proposal, isNull);
    expect(ledger, hasLength(2));
  });

  test('evidence counts everything checked, not only what is cited', () async {
    final result = await run([
      _toolTurn('finance_briefing', {'from': '2026-07-01', 'to': '2026-07-31'}),
      _composeTurn([
        // A briefing reads the whole ledger while citing no rows at all.
        {'type': 'conclusion', 'text': 'Here is your briefing.'},
        {'type': 'sourceNote', 'text': 'July 2026; INR; two checked records.'},
      ]),
    ]);
    expect(result.evidenceTransactionIds, containsAll([1, 2]));
  });
}

MoneyTransaction _transaction({
  required int id,
  required String merchant,
  required String category,
  int amountMinor = 25000,
}) => MoneyTransaction(
  id: id,
  amountMinor: amountMinor,
  currency: 'INR',
  direction: TransactionDirection.outgoing,
  merchant: merchant,
  category: category,
  occurredAt: DateTime(2026, 7, 10),
  source: TransactionSource.message,
);

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

ProviderTurn _composeTurn(List<Map<String, Object?>> parts) =>
    _toolTurn('answer_compose', {'parts': parts});

/// A turn that answers in content instead of calling the compose capability.
ProviderTurn _contentTurn(String content) => ProviderTurn(
  content: content,
  message: {'role': 'assistant', 'content': content},
  toolCalls: const [],
);

class _FakeProvider implements AgentProvider {
  _FakeProvider(this.turns);
  final List<ProviderTurn> turns;
  var index = 0;

  @override
  Future<ProviderTurn> nextTurn({
    required List<Map<String, Object?>> messages,
    required List<McpToolDefinition> tools,
    void Function(String delta)? onContentDelta,
    AgentCancellationToken? cancellation,
  }) async => turns[index++];
}
