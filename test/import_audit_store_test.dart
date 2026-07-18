import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fund_flow/data/fund_flow_store.dart';
import 'package:fund_flow/domain/import_audit.dart';
import 'package:fund_flow/domain/transaction.dart';
import 'package:fund_flow/ingestion/ai_message_ingestion.dart';
import 'package:fund_flow/ingestion/message_candidate.dart';

void main() {
  sqfliteFfiInit();

  test(
    'audit run persists request, response, reason and transaction live',
    () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await _schema(db);
      final store = FundFlowStore(database: db);
      final candidate = MessageCandidate(
        sender: 'Bank',
        body: 'A semantic transaction message',
        receivedAt: DateTime(2026, 7, 18, 10),
      );
      final runId = await store.beginImportRun(
        source: 'message',
        model: 'test-model',
        endpoint: 'http://localhost:11434',
        candidates: [candidate],
        alreadySeen: {},
      );
      final batchId = await store.beginImportBatch(runId: runId, position: 0);
      await store.assignImportBatch(runId, batchId, [candidate.fingerprint]);
      await store.recordImportBatchRequest(batchId, '{"sent":true}');
      await store.recordImportBatchResponse(batchId, '{"returned":true}');
      await store.commitIngestionBatch(
        AiIngestionBatch(
          results: [
            AnalyzedMessage(
              fingerprint: candidate.fingerprint,
              decision: IngestionDecision.transaction,
              reason: 'Completed outgoing payment.',
              transaction: MoneyTransaction(
                amountMinor: 12500,
                currency: 'INR',
                direction: TransactionDirection.outgoing,
                merchant: 'Merchant',
                category: 'Shopping',
                occurredAt: candidate.receivedAt,
                source: TransactionSource.message,
              ),
            ),
          ],
        ),
        runId: runId,
        batchId: batchId,
      );
      await store.finishImportRun(runId, state: ImportRunState.completed);

      final run = (await store.importRuns()).single;
      final item = (await store.importItems(runId)).single;
      final batch = (await store.importBatches(runId)).single;
      expect(run.processed, 1);
      expect(run.imported, 1);
      expect(item.state, ImportItemState.transaction);
      expect(item.reason, 'Completed outgoing payment.');
      expect(item.transactionId, isNotNull);
      expect(batch.requestJson, contains('sent'));
      expect(batch.responseJson, contains('returned'));
      expect((await store.transactions()), hasLength(1));
    },
  );
}

Future<void> _schema(Database db) async {
  await db.execute('''CREATE TABLE transactions(
    id INTEGER PRIMARY KEY AUTOINCREMENT, amount_minor INTEGER NOT NULL,
    currency TEXT NOT NULL, direction TEXT NOT NULL, merchant TEXT NOT NULL,
    category TEXT NOT NULL, occurred_at TEXT NOT NULL, source TEXT NOT NULL,
    review_state TEXT NOT NULL, confidence REAL NOT NULL, account TEXT,
    note TEXT, source_text TEXT)''');
  await db.execute('''CREATE TABLE import_attempts(
    id INTEGER PRIMARY KEY AUTOINCREMENT, fingerprint TEXT UNIQUE NOT NULL,
    received_at TEXT NOT NULL, outcome TEXT NOT NULL, detail TEXT)''');
  await db.execute('''CREATE TABLE import_runs(
    id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL,
    state TEXT NOT NULL, started_at TEXT NOT NULL, completed_at TEXT,
    model TEXT NOT NULL, endpoint TEXT NOT NULL, total INTEGER NOT NULL,
    processed INTEGER NOT NULL DEFAULT 0, imported INTEGER NOT NULL DEFAULT 0,
    error TEXT)''');
  await db.execute('''CREATE TABLE import_batches(
    id INTEGER PRIMARY KEY AUTOINCREMENT, run_id INTEGER NOT NULL,
    position INTEGER NOT NULL, state TEXT NOT NULL, created_at TEXT NOT NULL,
    completed_at TEXT, request_json TEXT NOT NULL DEFAULT '',
    response_json TEXT, error TEXT)''');
  await db.execute('''CREATE TABLE import_items(
    id INTEGER PRIMARY KEY AUTOINCREMENT, run_id INTEGER NOT NULL,
    batch_id INTEGER, fingerprint TEXT NOT NULL, sender TEXT, body TEXT NOT NULL,
    received_at TEXT NOT NULL, state TEXT NOT NULL, reason TEXT,
    transaction_id INTEGER, UNIQUE(run_id, fingerprint))''');
}
