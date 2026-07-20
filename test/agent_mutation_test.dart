import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fund_flow/agent/agent_proposal.dart';
import 'package:fund_flow/agent/local_mcp_server.dart';
import 'package:fund_flow/agent/mcp_protocol.dart';
import 'package:fund_flow/data/fund_flow_store.dart';
import 'package:fund_flow/domain/preferences.dart';
import 'package:fund_flow/domain/transaction.dart';

/// Cover for the capabilities that can change or delete the ledger.
///
/// Every one of these paths was untested until now: nothing exercised
/// transactions_create, transactions_delete or the bulk category change, and
/// nothing at all exercised undo. They are the only capabilities that can
/// destroy someone's records, so they are the ones that most needed a net.
void main() {
  sqfliteFfiInit();

  group('argument validation refuses before a proposal exists', () {
    late List<MoneyTransaction> transactions;
    late LocalMcpServer server;

    setUp(() {
      transactions = [_transaction(id: 1)];
      server = LocalMcpServer(
        transactions: () => transactions,
        preferences: () => const AppPreferences(),
      );
    });

    test('a text id is refused rather than cast at apply time', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'bad',
          name: 'transactions_delete',
          arguments: {'id': 'seven'},
        ),
      );
      expect(execution.result.isError, isTrue);
      expect(execution.proposal, isNull);
    });

    test('a fractional amount is refused', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'bad',
          name: 'transactions_update',
          arguments: {'id': 1, 'amountMinor': 10.5},
        ),
      );
      expect(execution.result.isError, isTrue);
      expect(
        execution.result.content['error'].toString(),
        contains('whole number'),
      );
    });

    test('an out-of-range value is refused', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'bad',
          name: 'transactions_update',
          arguments: {'id': 1, 'amountMinor': -5},
        ),
      );
      expect(execution.result.isError, isTrue);
    });

    test('an unknown enum member is refused', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'bad',
          name: 'transactions_update',
          arguments: {'id': 1, 'direction': 'sideways'},
        ),
      );
      expect(execution.result.isError, isTrue);
      expect(
        execution.result.content['error'].toString(),
        contains('incoming'),
      );
    });

    test('an empty id list cannot become a no-op bulk change', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'bulk',
          name: 'transactions_bulk_update_category',
          arguments: {'ids': <int>[], 'category': 'Food'},
        ),
      );
      expect(execution.result.isError, isTrue);
      expect(execution.proposal, isNull);
    });

    test('a list holding a non-integer is refused', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'bulk',
          name: 'transactions_bulk_update_category',
          arguments: {
            'ids': ['1'],
            'category': 'Food',
          },
        ),
      );
      expect(execution.result.isError, isTrue);
    });

    test('a valid proposal still passes and mutates nothing', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'ok',
          name: 'transactions_update',
          arguments: {'id': 1, 'category': 'Dining'},
        ),
      );
      expect(execution.result.isError, isFalse);
      expect(execution.proposal?.affectedIds, [1]);
      expect(transactions.single.category, 'Food');
    });

    test('the proposal records what the row said when it was made', () async {
      final execution = await server.execute(
        const McpToolCall(
          id: 'ok',
          name: 'transactions_update',
          arguments: {'id': 1, 'category': 'Dining'},
        ),
      );
      final fingerprint = execution.proposal!.affectedFingerprint[1];
      expect(fingerprint, isNotNull);
      // The same row still matches; a row edited since would not.
      expect(
        fingerprint,
        AgentProposal.fingerprintOf(
          amountMinor: transactions.single.amountMinor,
          currency: transactions.single.currency,
          merchant: transactions.single.merchant,
          category: transactions.single.category,
          occurredAt: transactions.single.occurredAt,
        ),
      );
      expect(
        fingerprint,
        isNot(
          AgentProposal.fingerprintOf(
            amountMinor: transactions.single.amountMinor,
            currency: transactions.single.currency,
            merchant: transactions.single.merchant,
            category: 'Something else',
            occurredAt: transactions.single.occurredAt,
          ),
        ),
      );
    });

    test(
      'gpt-oss filling every property is still not a validation error',
      () async {
        // The provider populates unused properties with empty strings and
        // zeroes, and writes "both" where it means "do not filter".
        final execution = await server.execute(
          const McpToolCall(
            id: 'filled',
            name: 'transactions_search',
            arguments: {
              'account': '',
              'category': '',
              'currency': '',
              'direction': 'both',
              'from': '',
              'limit': 10,
              'maximumMinor': 0,
              'merchant': '',
              'minimumMinor': 0,
              'offset': 0,
              'reviewState': '',
              'source': '',
              'to': '',
            },
          ),
        );
        expect(execution.result.isError, isFalse);
      },
    );
  });

  group('store applies and reverses each kind of change', () {
    late Database db;
    late FundFlowStore store;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _schema(db);
      store = FundFlowStore(database: db);
    });

    test('a created transaction is removed again by its undo', () async {
      final undoId = await store.applyTransactionChanges(
        upserts: [_transaction()],
        deletes: const [],
        undoKind: 'delete_created_transaction',
        undoPayload: {'createdAt': DateTime(2026, 7, 20).toIso8601String()},
      );
      expect(await store.transactions(), hasLength(1));

      await store.applyTransactionUndo((await store.undoById(undoId))!);
      expect(await store.transactions(), isEmpty);
    });

    test('an updated transaction is restored to its earlier values', () async {
      await store.applyTransactionChanges(
        upserts: [_transaction()],
        deletes: const [],
        undoKind: 'delete_created_transaction',
        undoPayload: const {},
      );
      final before = (await store.transactions()).single;

      final undoId = await store.applyTransactionChanges(
        upserts: [before.copyWith(category: 'Dining')],
        deletes: const [],
        undoKind: 'restore_transaction',
        undoPayload: {'transaction': before.toMap()},
      );
      expect((await store.transactions()).single.category, 'Dining');

      await store.applyTransactionUndo((await store.undoById(undoId))!);
      expect((await store.transactions()).single.category, 'Food');
    });

    test('a deleted transaction comes back with its fields', () async {
      await store.applyTransactionChanges(
        upserts: [_transaction(merchant: 'Cafe River')],
        deletes: const [],
        undoKind: 'delete_created_transaction',
        undoPayload: const {},
      );
      final before = (await store.transactions()).single;

      final undoId = await store.applyTransactionChanges(
        upserts: const [],
        deletes: [before.id!],
        undoKind: 'restore_transaction',
        undoPayload: {'transaction': before.toMap()},
      );
      expect(await store.transactions(), isEmpty);

      await store.applyTransactionUndo((await store.undoById(undoId))!);
      final restored = (await store.transactions()).single;
      expect(restored.merchant, 'Cafe River');
      expect(restored.amountMinor, before.amountMinor);
    });

    test('a bulk category change reverses every row it touched', () async {
      await store.applyTransactionChanges(
        upserts: [
          _transaction(merchant: 'One', category: 'Food'),
          _transaction(merchant: 'Two', category: 'Transport'),
        ],
        deletes: const [],
        undoKind: 'delete_created_transaction',
        undoPayload: const {},
      );
      final before = await store.transactions();

      final undoId = await store.applyTransactionChanges(
        upserts: before.map((item) => item.copyWith(category: 'Bills')),
        deletes: const [],
        undoKind: 'restore_transactions',
        undoPayload: {
          'transactions': before.map((item) => item.toMap()).toList(),
        },
      );
      expect(
        (await store.transactions()).map((item) => item.category),
        everyElement('Bills'),
      );

      await store.applyTransactionUndo((await store.undoById(undoId))!);
      final restored = await store.transactions();
      expect(
        restored.map((item) => item.category),
        containsAll(['Food', 'Transport']),
      );
    });

    test('a change against a vanished row rolls back whole', () async {
      await store.applyTransactionChanges(
        upserts: [_transaction()],
        deletes: const [],
        undoKind: 'delete_created_transaction',
        undoPayload: const {},
      );
      final present = (await store.transactions()).single;

      // One row exists and one does not; the batch must not half-apply.
      await expectLater(
        store.applyTransactionChanges(
          upserts: [
            present.copyWith(category: 'Dining'),
            _transaction(id: 9999, category: 'Ghost'),
          ],
          deletes: const [],
          undoKind: 'restore_transactions',
          undoPayload: const {},
        ),
        throwsA(isA<StateError>()),
      );
      expect((await store.transactions()).single.category, 'Food');
    });

    test('a consumed undo cannot be replayed', () async {
      final undoId = await store.applyTransactionChanges(
        upserts: [_transaction()],
        deletes: const [],
        undoKind: 'delete_created_transaction',
        undoPayload: const {},
      );
      await store.applyTransactionUndo((await store.undoById(undoId))!);
      expect(await store.undoById(undoId), isNull);
    });

    test('undo history does not grow without bound', () async {
      for (var index = 0; index < 60; index++) {
        await store.saveUndo('restore_memory', {'key': 'k$index'});
      }
      final rows = await db.query('undo_records');
      expect(rows.length, lessThanOrEqualTo(50));
      // The newest survive; the oldest are the ones dropped.
      final latest = await store.latestUndo();
      expect(latest!.payload['key'], 'k59');
    });
  });
}

MoneyTransaction _transaction({
  int? id,
  String merchant = 'Cafe River',
  String category = 'Food',
}) => MoneyTransaction(
  id: id,
  amountMinor: 25000,
  currency: 'INR',
  direction: TransactionDirection.outgoing,
  merchant: merchant,
  category: category,
  occurredAt: DateTime(2026, 7, 18),
  source: TransactionSource.message,
);

Future<void> _schema(Database db) async {
  await db.execute('''CREATE TABLE transactions(
    id INTEGER PRIMARY KEY AUTOINCREMENT, amount_minor INTEGER NOT NULL,
    currency TEXT NOT NULL, direction TEXT NOT NULL, merchant TEXT NOT NULL,
    category TEXT NOT NULL, occurred_at TEXT NOT NULL, source TEXT NOT NULL,
    review_state TEXT NOT NULL, confidence REAL NOT NULL, account TEXT,
    note TEXT, source_text TEXT)''');
  await db.execute('''CREATE TABLE undo_records(
    id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,
    payload TEXT NOT NULL, created_at TEXT NOT NULL)''');
}
