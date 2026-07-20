import 'dart:convert';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../agent/agent_proposal.dart';
import '../agent/agent_runner.dart';
import '../domain/conversation.dart';
import '../domain/import_audit.dart';
import '../domain/transaction.dart';
import '../ingestion/ai_message_ingestion.dart';
import '../ingestion/message_candidate.dart';

class FundFlowStore {
  FundFlowStore({Database? database}) : _database = database;
  Database? _database;
  static const schemaVersion = 6;

  Future<Database> get database async => _database ??= await openDatabase(
    path.join(await getDatabasesPath(), 'fund_flow_greenfield.db'),
    version: schemaVersion,
    onCreate: (db, _) async {
      await db.execute(
        '''CREATE TABLE transactions(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount_minor INTEGER NOT NULL, currency TEXT NOT NULL,
        direction TEXT NOT NULL, merchant TEXT NOT NULL,
        category TEXT NOT NULL, occurred_at TEXT NOT NULL,
        source TEXT NOT NULL, review_state TEXT NOT NULL,
        confidence REAL NOT NULL, account TEXT, note TEXT, source_text TEXT)''',
      );
      await db.execute('''CREATE TABLE conversation(
        id INTEGER PRIMARY KEY AUTOINCREMENT, author TEXT NOT NULL,
        text TEXT NOT NULL, created_at TEXT NOT NULL, verified INTEGER NOT NULL,
        supporting_ids TEXT NOT NULL, parts_json TEXT NOT NULL DEFAULT '[]',
        unstructured INTEGER NOT NULL DEFAULT 0)''');
      await db.execute('''CREATE TABLE preferences(
        key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE import_attempts(
        id INTEGER PRIMARY KEY AUTOINCREMENT, fingerprint TEXT UNIQUE NOT NULL,
        received_at TEXT NOT NULL, outcome TEXT NOT NULL, detail TEXT)''');
      await db.execute('''CREATE TABLE undo_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,
        payload TEXT NOT NULL, created_at TEXT NOT NULL)''');
      await _createAgentTables(db);
      await _createImportAuditTables(db);
      await _createAgentTelemetryTable(db);
      await _createFinancialMemoryTable(db);
      await _createConversationThreads(db);
    },
    onUpgrade: (db, oldVersion, _) async {
      if (oldVersion < 2) {
        await db.execute(
          "ALTER TABLE conversation ADD COLUMN parts_json TEXT NOT NULL DEFAULT '[]'",
        );
        await db.execute(
          'ALTER TABLE conversation ADD COLUMN unstructured INTEGER NOT NULL DEFAULT 0',
        );
        await _createAgentTables(db);
      }
      if (oldVersion < 3) await _createImportAuditTables(db);
      if (oldVersion < 4) await _createAgentTelemetryTable(db);
      if (oldVersion < 5) await _createFinancialMemoryTable(db);
      if (oldVersion < 6) await _migrateToConversationThreads(db);
    },
  );

  static Future<void> _createAgentTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS agent_proposals(
      id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,
      title TEXT NOT NULL, explanation TEXT NOT NULL,
      arguments_json TEXT NOT NULL, affected_ids TEXT NOT NULL,
      created_at TEXT NOT NULL, expires_at TEXT NOT NULL,
      requires_authentication INTEGER NOT NULL, reversible INTEGER NOT NULL,
      status TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS tool_calls(
      id INTEGER PRIMARY KEY AUTOINCREMENT, conversation_id INTEGER,
      tool TEXT NOT NULL, summary TEXT NOT NULL, is_error INTEGER NOT NULL,
      created_at TEXT NOT NULL)''');
  }

  static Future<void> _createImportAuditTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS import_runs(
      id INTEGER PRIMARY KEY AUTOINCREMENT, source TEXT NOT NULL,
      state TEXT NOT NULL, started_at TEXT NOT NULL, completed_at TEXT,
      model TEXT NOT NULL, endpoint TEXT NOT NULL, total INTEGER NOT NULL,
      processed INTEGER NOT NULL DEFAULT 0, imported INTEGER NOT NULL DEFAULT 0,
      error TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS import_batches(
      id INTEGER PRIMARY KEY AUTOINCREMENT, run_id INTEGER NOT NULL,
      position INTEGER NOT NULL, state TEXT NOT NULL, created_at TEXT NOT NULL,
      completed_at TEXT, request_json TEXT NOT NULL DEFAULT '',
      response_json TEXT, error TEXT)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS import_items(
      id INTEGER PRIMARY KEY AUTOINCREMENT, run_id INTEGER NOT NULL,
      batch_id INTEGER, fingerprint TEXT NOT NULL, sender TEXT, body TEXT NOT NULL,
      received_at TEXT NOT NULL, state TEXT NOT NULL, reason TEXT,
      transaction_id INTEGER, UNIQUE(run_id, fingerprint))''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS import_items_run ON import_items(run_id)',
    );
  }

  static Future<void> _createAgentTelemetryTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS agent_runs(
      id INTEGER PRIMARY KEY AUTOINCREMENT, conversation_id INTEGER,
      model TEXT NOT NULL, started_at TEXT NOT NULL,
      elapsed_ms INTEGER NOT NULL, turns INTEGER NOT NULL, calls INTEGER NOT NULL,
      prompt_tokens INTEGER NOT NULL, output_tokens INTEGER NOT NULL,
      provider_duration_ms INTEGER NOT NULL, metrics_json TEXT NOT NULL)''');
  }

  static Future<void> _createConversationThreads(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS conversation_threads(
      id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    final columns = await db.rawQuery('PRAGMA table_info(conversation)');
    if (!columns.any((row) => row['name'] == 'thread_id')) {
      await db.execute('ALTER TABLE conversation ADD COLUMN thread_id INTEGER');
    }
    await db.execute(
      'CREATE INDEX IF NOT EXISTS conversation_thread '
      'ON conversation(thread_id)',
    );
  }

  /// Moves an existing single conversation into the threaded model.
  ///
  /// Messages predate threads and would become unreachable if left
  /// unassigned, so they are gathered into one thread titled from the first
  /// question rather than dropped.
  static Future<void> _migrateToConversationThreads(Database db) async {
    await _createConversationThreads(db);
    final existing = await db.query(
      'conversation',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (existing.isEmpty) return;
    final firstText = existing.first['text'] as String? ?? '';
    final createdAt = existing.first['created_at'] as String;
    final threadId = await db.insert('conversation_threads', {
      'title': ConversationThread.titleFrom(firstText),
      'created_at': createdAt,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await db.update(
      'conversation',
      {'thread_id': threadId},
      where: 'thread_id IS NULL',
    );
  }

  static Future<void> _createFinancialMemoryTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS financial_memory(
      key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)''');
  }

  Future<List<MoneyTransaction>> transactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'occurred_at DESC');
    return rows.map(MoneyTransaction.fromMap).toList();
  }

  Future<int> saveTransaction(MoneyTransaction value) async {
    final db = await database;
    final map = value.toMap()..remove('id');
    if (value.id == null) return db.insert('transactions', map);
    await db.update(
      'transactions',
      map,
      where: 'id = ?',
      whereArgs: [value.id],
    );
    return value.id!;
  }

  Future<void> deleteTransaction(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  /// Messages in [threadId]. A null thread has no messages: an unsent chat
  /// exists only in memory until its first question is asked.
  Future<List<ConversationMessage>> conversation({int? threadId}) async {
    if (threadId == null) return const [];
    final db = await database;
    final rows = await db.query(
      'conversation',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
    return rows.map(ConversationMessage.fromMap).toList();
  }

  Future<int> addMessage(ConversationMessage value, {int? threadId}) async {
    final db = await database;
    final map = value.toMap()
      ..remove('id')
      ..['thread_id'] = threadId;
    final id = db.insert('conversation', map);
    if (threadId != null) {
      // Touching the thread keeps the history list ordered by real activity
      // rather than by when a thread was first opened.
      await db.update(
        'conversation_threads',
        {'updated_at': DateTime.now().toUtc().toIso8601String()},
        where: 'id = ?',
        whereArgs: [threadId],
      );
    }
    return id;
  }

  Future<int> createConversationThread(String title) async {
    final now = DateTime.now().toUtc().toIso8601String();
    return (await database).insert('conversation_threads', {
      'title': title,
      'created_at': now,
      'updated_at': now,
    });
  }

  /// History, most recently active first, with a preview of the last message.
  Future<List<ConversationThread>> conversationThreads() async {
    final rows = await (await database).rawQuery('''
      SELECT t.id, t.title, t.created_at, t.updated_at,
             COUNT(c.id) AS message_count,
             (SELECT text FROM conversation
               WHERE thread_id = t.id AND text != ''
               ORDER BY created_at DESC LIMIT 1) AS preview
      FROM conversation_threads t
      LEFT JOIN conversation c ON c.thread_id = t.id
      GROUP BY t.id
      HAVING message_count > 0
      ORDER BY t.updated_at DESC
    ''');
    return rows.map(ConversationThread.fromMap).toList();
  }

  Future<void> deleteConversationThread(int id) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'conversation',
        where: 'thread_id = ?',
        whereArgs: [id],
      );
      await transaction.delete(
        'conversation_threads',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> recordToolEvents(
    int conversationId,
    Iterable<AgentToolEvent> events,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (final event in events) {
      batch.insert('tool_calls', {
        'conversation_id': conversationId,
        'tool': event.tool,
        'summary': event.summary,
        'is_error': event.isError ? 1 : 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> recordAgentRun({
    required int conversationId,
    required String model,
    required DateTime startedAt,
    required AgentRunResult result,
  }) async {
    final promptTokens = result.metrics.fold<int>(
      0,
      (sum, value) => sum + (value.promptTokens ?? 0),
    );
    final outputTokens = result.metrics.fold<int>(
      0,
      (sum, value) => sum + (value.outputTokens ?? 0),
    );
    final providerDurationNs = result.metrics.fold<int>(
      0,
      (sum, value) => sum + (value.totalDurationNs ?? 0),
    );
    await (await database).insert('agent_runs', {
      'conversation_id': conversationId,
      'model': model,
      'started_at': startedAt.toUtc().toIso8601String(),
      'elapsed_ms': result.elapsed.inMilliseconds,
      'turns': result.turns,
      'calls': result.calls,
      'prompt_tokens': promptTokens,
      'output_tokens': outputTokens,
      'provider_duration_ms': providerDurationNs ~/ 1000000,
      'metrics_json': jsonEncode(
        result.metrics.map((value) => value.toJson()).toList(),
      ),
    });
  }

  Future<List<Map<String, Object?>>> recentAgentRuns({int limit = 20}) async {
    final rows = await (await database).query(
      'agent_runs',
      orderBy: 'id DESC',
      limit: limit.clamp(1, 100),
    );
    return rows
        .map(
          (row) => <String, Object?>{
            'model': row['model'],
            'startedAt': row['started_at'],
            'elapsedMs': row['elapsed_ms'],
            'turns': row['turns'],
            'calls': row['calls'],
            'promptTokens': row['prompt_tokens'],
            'outputTokens': row['output_tokens'],
            'providerDurationMs': row['provider_duration_ms'],
          },
        )
        .toList();
  }

  Future<List<Map<String, Object?>>> financialMemory() async {
    final rows = await (await database).query(
      'financial_memory',
      orderBy: 'key ASC',
    );
    return rows
        .map(
          (row) => <String, Object?>{
            'key': row['key'],
            'value': row['value'],
            'updatedAt': row['updated_at'],
          },
        )
        .toList();
  }

  Future<void> setFinancialMemory(String key, String value) async {
    await (await database).insert('financial_memory', {
      'key': key.trim(),
      'value': value.trim(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteFinancialMemory(String key) async {
    await (await database).delete(
      'financial_memory',
      where: 'key = ?',
      whereArgs: [key.trim()],
    );
  }

  Future<AgentProposal> saveProposal(AgentProposal value) async {
    final id = await (await database).insert('agent_proposals', {
      'kind': value.kind.name,
      'title': value.title,
      'explanation': value.explanation,
      'arguments_json': jsonEncode(value.arguments),
      'affected_ids': value.affectedIds.join(','),
      'created_at': value.createdAt.toUtc().toIso8601String(),
      'expires_at': value.expiresAt.toUtc().toIso8601String(),
      'requires_authentication': value.requiresAuthentication ? 1 : 0,
      'reversible': value.reversible ? 1 : 0,
      'status': value.status.name,
    });
    return value.copyWith(id: id);
  }

  Future<void> setProposalStatus(int id, AgentProposalStatus status) async {
    await (await database).update(
      'agent_proposals',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Writes an undo record and returns its id.
  ///
  /// Undo used to pop whichever record was newest, which is only the right
  /// one when nothing else has happened since. Returning the id lets the
  /// caller undo the change it actually made.
  Future<int> saveUndo(String kind, Map<String, Object?> payload) async {
    final id = await (await database).insert('undo_records', {
      'kind': kind,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _pruneUndo();
    return id;
  }

  /// Keeps the undo table from growing without bound.
  static const _undoHistoryLimit = 50;

  Future<void> _pruneUndo() async {
    await (await database).rawDelete(
      'DELETE FROM undo_records WHERE id NOT IN '
      '(SELECT id FROM undo_records ORDER BY id DESC LIMIT ?)',
      [_undoHistoryLimit],
    );
  }

  Future<int> applyTransactionChanges({
    required Iterable<MoneyTransaction> upserts,
    required Iterable<int> deletes,
    required String undoKind,
    required Map<String, Object?> undoPayload,
  }) async {
    final db = await database;
    late int undoId;
    await db.transaction((transaction) async {
      final createdIds = <int>[];
      for (final value in upserts) {
        final map = value.toMap()..remove('id');
        if (value.id == null) {
          createdIds.add(await transaction.insert('transactions', map));
        } else {
          final count = await transaction.update(
            'transactions',
            map,
            where: 'id = ?',
            whereArgs: [value.id],
          );
          if (count != 1) throw StateError('A transaction became stale.');
        }
      }
      for (final id in deletes) {
        final count = await transaction.delete(
          'transactions',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (count != 1) throw StateError('A transaction became stale.');
      }
      undoId = await transaction.insert('undo_records', {
        'kind': undoKind,
        'payload': jsonEncode({
          ...undoPayload,
          if (createdIds.isNotEmpty) 'createdIds': createdIds,
        }),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
    await _pruneUndo();
    return undoId;
  }

  Future<UndoRecord?> latestUndo() async {
    final rows = await (await database).query(
      'undo_records',
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : _undoFromRow(rows.single);
  }

  /// The specific undo record a change wrote, or null once it is consumed.
  Future<UndoRecord?> undoById(int id) async {
    final rows = await (await database).query(
      'undo_records',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _undoFromRow(rows.single);
  }

  UndoRecord _undoFromRow(Map<String, Object?> row) => UndoRecord(
    id: row['id'] as int,
    kind: row['kind'] as String,
    payload: Map<String, Object?>.from(
      jsonDecode(row['payload'] as String) as Map,
    ),
  );

  Future<void> applyTransactionUndo(UndoRecord record) async {
    final db = await database;
    await db.transaction((transaction) async {
      switch (record.kind) {
        case 'delete_created_transaction':
          for (final id
              in (record.payload['createdIds'] as List? ?? const [])) {
            await transaction.delete(
              'transactions',
              where: 'id = ?',
              whereArgs: [(id as num).toInt()],
            );
          }
        case 'restore_transaction':
          final value = Map<String, Object?>.from(
            record.payload['transaction'] as Map,
          );
          await transaction.insert(
            'transactions',
            value,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        case 'restore_transactions':
          for (final raw
              in record.payload['transactions'] as List? ?? const []) {
            await transaction.insert(
              'transactions',
              Map<String, Object?>.from(raw as Map),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        default:
          throw StateError('This undo record is not a transaction change.');
      }
      await transaction.delete(
        'undo_records',
        where: 'id = ?',
        whereArgs: [record.id],
      );
    });
  }

  Future<void> consumeUndo(int id) async {
    await (await database).delete(
      'undo_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearConversation() async =>
      (await database).transaction((transaction) async {
        await transaction.delete('conversation');
        await transaction.delete('conversation_threads');
      });

  Future<Set<String>> seenImportFingerprints(Iterable<String> values) async {
    final fingerprints = values.toList();
    if (fingerprints.isEmpty) return {};
    final placeholders = List.filled(fingerprints.length, '?').join(',');
    final rows = await (await database).query(
      'import_attempts',
      columns: ['fingerprint'],
      where: 'fingerprint IN ($placeholders)',
      whereArgs: fingerprints,
    );
    return rows.map((row) => row['fingerprint'] as String).toSet();
  }

  Future<int> beginImportRun({
    required String source,
    required String model,
    required String endpoint,
    required List<MessageCandidate> candidates,
    required Set<String> alreadySeen,
  }) async {
    final db = await database;
    final previous = <String, Map<String, Object?>>{};
    if (alreadySeen.isNotEmpty) {
      final placeholders = List.filled(alreadySeen.length, '?').join(',');
      final rows = await db.query(
        'import_attempts',
        columns: ['fingerprint', 'outcome', 'detail'],
        where: 'fingerprint IN ($placeholders)',
        whereArgs: alreadySeen.toList(),
      );
      for (final row in rows) {
        previous[row['fingerprint'] as String] = row;
      }
    }
    return db.transaction((transaction) async {
      final runId = await transaction.insert('import_runs', {
        'source': source,
        'state': ImportRunState.running.name,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'model': model,
        'endpoint': endpoint,
        'total': candidates.length,
        'processed': alreadySeen.length,
        'imported': 0,
      });
      for (final candidate in candidates) {
        final seen = alreadySeen.contains(candidate.fingerprint);
        final old = previous[candidate.fingerprint];
        final oldOutcome = old?['outcome']?.toString();
        final oldLabel = switch (oldOutcome) {
          'transaction' => 'Previously added as a transaction',
          'notTransaction' => 'Previously classified as not a transaction',
          'uncertain' => 'Previously classified as uncertain',
          _ => 'Previously analyzed',
        };
        await transaction.insert('import_items', {
          'run_id': runId,
          'fingerprint': candidate.fingerprint,
          'sender': candidate.sender,
          'body': candidate.body,
          'received_at': candidate.receivedAt.toUtc().toIso8601String(),
          'state': seen
              ? ImportItemState.alreadySeen.name
              : ImportItemState.queued.name,
          'reason': seen
              ? '$oldLabel; not sent again. ${old?['detail']?.toString() ?? ''}'
                    .trim()
              : null,
        });
      }
      return runId;
    });
  }

  Future<int> beginImportBatch({required int runId, required int position}) =>
      database.then(
        (db) => db.insert('import_batches', {
          'run_id': runId,
          'position': position,
          'state': 'sending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'request_json': '',
        }),
      );

  Future<void> recordImportBatchRequest(int id, String requestJson) async {
    await (await database).update(
      'import_batches',
      {'request_json': requestJson},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> recordImportBatchResponse(int id, String responseJson) async {
    await (await database).update(
      'import_batches',
      {'response_json': responseJson},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> failImportBatch(int id, String error) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.update(
        'import_batches',
        {
          'state': 'failed',
          'error': error,
          'completed_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await transaction.update(
        'import_items',
        {'state': ImportItemState.failed.name, 'reason': error},
        where: 'batch_id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> assignImportBatch(
    int runId,
    int batchId,
    Iterable<String> fingerprints,
  ) async {
    final db = await database;
    final batch = db.batch();
    for (final fingerprint in fingerprints) {
      batch.update(
        'import_items',
        {'batch_id': batchId},
        where: 'run_id = ? AND fingerprint = ?',
        whereArgs: [runId, fingerprint],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> finishImportRun(
    int runId, {
    required ImportRunState state,
    String? error,
  }) async {
    await (await database).update(
      'import_runs',
      {
        'state': state.name,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
        'error': error,
      },
      where: 'id = ?',
      whereArgs: [runId],
    );
  }

  Future<List<ImportRunRecord>> importRuns({int limit = 30}) async {
    final rows = await (await database).query(
      'import_runs',
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(ImportRunRecord.fromMap).toList();
  }

  Future<List<ImportBatchRecord>> importBatches(int runId) async {
    final rows = await (await database).query(
      'import_batches',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 'position ASC',
    );
    return rows.map(ImportBatchRecord.fromMap).toList();
  }

  Future<List<ImportItemRecord>> importItems(int runId) async {
    final rows = await (await database).query(
      'import_items',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 'received_at DESC',
    );
    return rows.map(ImportItemRecord.fromMap).toList();
  }

  Future<void> clearImportAudit() async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete('import_items');
      await transaction.delete('import_batches');
      await transaction.delete('import_runs');
      await transaction.update('transactions', {'source_text': null});
    });
  }

  Future<void> recoverInterruptedImports() async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final running = await transaction.query(
        'import_runs',
        columns: ['id'],
        where: 'state = ?',
        whereArgs: [ImportRunState.running.name],
      );
      for (final row in running) {
        final runId = row['id'] as int;
        const reason =
            'The app process ended before this AI request completed. Tap Check to retry safely.';
        await transaction.update(
          'import_runs',
          {
            'state': ImportRunState.failed.name,
            'completed_at': now,
            'error': reason,
          },
          where: 'id = ?',
          whereArgs: [runId],
        );
        await transaction.update(
          'import_batches',
          {'state': 'failed', 'completed_at': now, 'error': reason},
          where: 'run_id = ? AND state = ?',
          whereArgs: [runId, 'sending'],
        );
        await transaction.update(
          'import_items',
          {'state': ImportItemState.failed.name, 'reason': reason},
          where: 'run_id = ? AND state = ?',
          whereArgs: [runId, ImportItemState.queued.name],
        );
      }
    });
  }

  /// Commits a batch and returns the transactions it created.
  ///
  /// Returning the rows lets a caller extend the list it already holds
  /// instead of re-reading the whole table after every batch, which grows
  /// more expensive with each batch as the ledger fills.
  Future<List<MoneyTransaction>> commitIngestionBatch(
    AiIngestionBatch batch, {
    int? runId,
    int? batchId,
  }) async {
    final db = await database;
    return db.transaction((transaction) async {
      final inserted = <MoneyTransaction>[];
      for (final result in batch.results) {
        final accepted = await transaction.insert('import_attempts', {
          'fingerprint': result.fingerprint,
          'received_at': DateTime.now().toUtc().toIso8601String(),
          'outcome': result.decision.name,
          'detail': result.reason,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        int? transactionId;
        if (accepted != 0 && result.transaction != null) {
          final value = result.transaction!.toMap()..remove('id');
          transactionId = await transaction.insert('transactions', value);
          inserted.add(result.transaction!.copyWith(id: transactionId));
        }
        if (runId != null) {
          await transaction.update(
            'import_items',
            {
              'batch_id': batchId,
              'state': switch (result.decision) {
                IngestionDecision.transaction =>
                  ImportItemState.transaction.name,
                IngestionDecision.notTransaction =>
                  ImportItemState.notTransaction.name,
                IngestionDecision.uncertain => ImportItemState.uncertain.name,
              },
              'reason': result.reason,
              'transaction_id': transactionId,
            },
            where: 'run_id = ? AND fingerprint = ?',
            whereArgs: [runId, result.fingerprint],
          );
        }
      }
      if (batchId != null) {
        await transaction.update(
          'import_batches',
          {
            'state': 'completed',
            'completed_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [batchId],
        );
      }
      if (runId != null) {
        await transaction.rawUpdate(
          '''UPDATE import_runs SET
          processed = (SELECT COUNT(*) FROM import_items WHERE run_id = ? AND state != ?),
          imported = (SELECT COUNT(*) FROM import_items WHERE run_id = ? AND state = ?)
          WHERE id = ?''',
          [
            runId,
            ImportItemState.queued.name,
            runId,
            ImportItemState.transaction.name,
            runId,
          ],
        );
      }
      return inserted;
    });
  }

  Future<String?> preference(String key) async {
    final rows = await (await database).query(
      'preferences',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setPreference(String key, String value) async =>
      (await database).insert('preferences', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

class UndoRecord {
  const UndoRecord({
    required this.id,
    required this.kind,
    required this.payload,
  });
  final int id;
  final String kind;
  final Map<String, Object?> payload;
}
