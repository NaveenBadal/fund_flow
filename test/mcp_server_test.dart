import 'package:fund_flow/agent/local_mcp_server.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/domain/preferences.dart';
import 'package:fund_flow/domain/transaction.dart';
import 'package:fund_flow/domain/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<MoneyTransaction> transactions;
  late LocalMcpServer server;

  setUp(() {
    transactions = [
      _transaction(1, 25000, 'INR', 'Cafe River', 'Food'),
      _transaction(2, 5000, 'INR', 'Metro', 'Transport'),
      _transaction(3, 1200, 'USD', 'Cloud Host', 'Work'),
    ];
    server = LocalMcpServer(
      transactions: () => transactions,
      preferences: () => const AppPreferences(),
    );
  });

  test('catalog exposes reads, proposals, settings and answer composition', () {
    final names = server.tools.map((tool) => tool.name).toSet();
    expect(names, contains('transactions_search'));
    expect(names, contains('finance_compare'));
    expect(names, contains('settings_update'));
    expect(names, contains('security_set_app_lock'));
    expect(names, contains('app_update_status'));
    expect(names, contains('conversation_search'));
    expect(names, contains('answer_compose'));
  });

  test('filled-but-empty arguments mean no filter, exactly as sent by '
      'gpt-oss', () async {
    transactions.add(
      MoneyTransaction(
        id: 9,
        amountMinor: 87255,
        currency: 'INR',
        direction: TransactionDirection.outgoing,
        merchant: 'Zomato',
        category: 'Food',
        occurredAt: DateTime(2026, 7, 17),
        source: TransactionSource.message,
        reviewState: ReviewState.needsReview,
      ),
    );
    // Verbatim shape observed from the live provider: every property
    // present, unused ones as empty strings and zeroes.
    final execution = await server.execute(
      const McpToolCall(
        id: 'filled',
        name: 'transactions_search',
        arguments: {
          'account': '',
          'category': '',
          'currency': '',
          'direction': '',
          'from': '',
          'limit': 14,
          'maximumMinor': 0,
          'merchant': '',
          'minimumMinor': 0,
          'offset': 0,
          'reviewState': 'needsReview',
          'source': '',
          'to': '',
        },
      ),
    );
    expect(execution.result.isError, isFalse);
    expect(execution.result.content['total'], 1);
  });

  test('currency "all" means no filter, not an impossible currency', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'cur',
        name: 'transactions_search',
        arguments: {'currency': 'all', 'reviewState': 'confirmed'},
      ),
    );
    expect(execution.result.isError, isFalse);
    expect(execution.result.content['total'], transactions.length);
  });

  test('direction "both" means no filter, not an impossible match', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'both',
        name: 'finance_briefing',
        arguments: {
          'from': '2026-07-01',
          'to': '2026-07-31',
          'direction': 'both',
        },
      ),
    );
    expect(execution.result.isError, isFalse);
    expect(execution.result.content['checkedCount'], transactions.length);
  });

  test('an invalid enum filter fails loudly instead of matching nothing', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'bad',
        name: 'finance_briefing',
        arguments: {
          'from': '2026-07-01',
          'to': '2026-07-31',
          'direction': 'sideways',
        },
      ),
    );
    expect(execution.result.isError, isTrue);
    expect(
      execution.result.content['error'].toString(),
      contains('incoming'),
    );
  });

  test('an empty period result carries ledger coverage for self-correction',
      () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'empty',
        name: 'finance_briefing',
        arguments: {'from': '2024-01-01', 'to': '2024-02-01'},
      ),
    );
    expect(execution.result.isError, isFalse);
    expect(execution.result.content['checkedCount'], 0);
    final coverage =
        execution.result.content['ledgerCoverage'] as Map<String, Object?>;
    expect(coverage['totalCount'], transactions.length);
    expect(coverage['earliestOccurredAt'], isNotNull);
    expect(execution.result.content['hint'], isNotNull);
  });

  test('conversation search returns bounded local follow-up context', () async {
    server = LocalMcpServer(
      transactions: () => transactions,
      preferences: () => const AppPreferences(),
      conversation: () => [
        ConversationMessage(
          author: MessageAuthor.person,
          text: 'How much did I spend on coffee?',
          createdAt: DateTime(2026, 7, 1),
        ),
        ConversationMessage(
          author: MessageAuthor.assistant,
          text: 'Coffee spending was INR 250.',
          createdAt: DateTime(2026, 7, 1, 0, 1),
          verified: true,
          supportingTransactionIds: const [1],
        ),
      ],
    );
    final execution = await server.execute(
      const McpToolCall(
        id: 'history',
        name: 'conversation_search',
        arguments: {'query': 'coffee', 'limit': 1},
      ),
    );
    final messages = execution.result.content['messages'] as List;
    expect(messages, hasLength(1));
    expect((messages.single as Map)['supportingTransactionIds'], [1]);
  });

  test(
    'update status is read through the scoped platform capability',
    () async {
      server = LocalMcpServer(
        transactions: () => transactions,
        preferences: () => const AppPreferences(),
        updateStatus: () async => {
          'supported': true,
          'status': 'available',
          'latestBuildNumber': 81,
        },
      );
      final execution = await server.execute(
        const McpToolCall(
          id: 'update',
          name: 'app_update_status',
          arguments: {},
        ),
      );
      expect(execution.result.isError, isFalse);
      expect(execution.result.content['status'], 'available');
      expect(execution.result.content['latestBuildNumber'], 81);
    },
  );

  test('summary never combines currencies', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'one',
        name: 'finance_summary',
        arguments: {'from': '2026-07-01', 'to': '2026-07-31'},
      ),
    );
    final rows = execution.result.content['currencies'] as List;
    expect(rows, hasLength(2));
    expect(
      rows.map((row) => (row as Map)['currency']),
      containsAll(['INR', 'USD']),
    );
  });

  test('unknown arguments are rejected without exposing internals', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'bad',
        name: 'transactions_search',
        arguments: {'sql': 'DROP TABLE transactions'},
      ),
    );
    expect(execution.result.isError, isTrue);
    expect(execution.result.content['error'], contains('Unknown arguments'));
  });

  test('mutation tool creates a proposal and does not mutate', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'change',
        name: 'transactions_update',
        arguments: {'id': 1, 'category': 'Dining'},
      ),
    );
    expect(execution.proposal?.affectedIds, [1]);
    expect(transactions.first.category, 'Food');
    expect(execution.result.content['status'], 'approval_required');
  });

  test('a reversible proposal waits for the person, not a stopwatch', () async {
    final memory = await server.execute(
      const McpToolCall(
        id: 'mem',
        name: 'memory_set',
        arguments: {'key': 'monthly_rent', 'value': '25000 INR'},
      ),
    );
    final window = memory.proposal!.expiresAt.difference(
      memory.proposal!.createdAt,
    );
    expect(window, greaterThan(const Duration(hours: 1)));

    // Clearing a conversation cannot be undone, so it keeps a short window.
    final clear = await server.execute(
      const McpToolCall(
        id: 'clear',
        name: 'conversation_clear',
        arguments: {},
      ),
    );
    expect(
      clear.proposal!.expiresAt.difference(clear.proposal!.createdAt),
      lessThan(const Duration(hours: 1)),
    );
  });

  test('compose requires a conclusion and produces typed parts', () async {
    final execution = await server.execute(
      const McpToolCall(
        id: 'answer',
        name: 'answer_compose',
        arguments: {
          'parts': [
            {'type': 'conclusion', 'text': 'Food was your largest category.'},
            {
              'type': 'followUps',
              'questions': ['Show the transactions'],
            },
          ],
        },
      ),
    );
    expect(execution.presentation?.parts, hasLength(2));
  });
}

MoneyTransaction _transaction(
  int id,
  int amount,
  String currency,
  String merchant,
  String category,
) => MoneyTransaction(
  id: id,
  amountMinor: amount,
  currency: currency,
  direction: TransactionDirection.outgoing,
  merchant: merchant,
  category: category,
  occurredAt: DateTime(2026, 7, id),
  source: TransactionSource.message,
);
