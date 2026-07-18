import 'package:fund_flow/agent/local_mcp_server.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/domain/preferences.dart';
import 'package:fund_flow/domain/transaction.dart';
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
    expect(names, contains('answer_compose'));
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
