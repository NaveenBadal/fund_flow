import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../domain/conversation.dart';
import '../domain/transaction.dart';
import '../ingestion/ai_message_ingestion.dart';

class FundFlowStore {
  FundFlowStore({Database? database}) : _database = database;
  Database? _database;
  static const schemaVersion = 1;

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
        supporting_ids TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE preferences(
        key TEXT PRIMARY KEY, value TEXT NOT NULL)''');
      await db.execute('''CREATE TABLE import_attempts(
        id INTEGER PRIMARY KEY AUTOINCREMENT, fingerprint TEXT UNIQUE NOT NULL,
        received_at TEXT NOT NULL, outcome TEXT NOT NULL, detail TEXT)''');
      await db.execute('''CREATE TABLE undo_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,
        payload TEXT NOT NULL, created_at TEXT NOT NULL)''');
    },
  );

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

  Future<List<ConversationMessage>> conversation() async {
    final db = await database;
    final rows = await db.query('conversation', orderBy: 'created_at ASC');
    return rows.map(ConversationMessage.fromMap).toList();
  }

  Future<int> addMessage(ConversationMessage value) async {
    final db = await database;
    final map = value.toMap()..remove('id');
    return db.insert('conversation', map);
  }

  Future<void> clearConversation() async =>
      (await database).delete('conversation');

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

  Future<int> commitIngestionBatch(AiIngestionBatch batch) async {
    final db = await database;
    return db.transaction((transaction) async {
      var imported = 0;
      for (final result in batch.results) {
        final accepted = await transaction.insert('import_attempts', {
          'fingerprint': result.fingerprint,
          'received_at': DateTime.now().toUtc().toIso8601String(),
          'outcome': result.decision.name,
          'detail': result.reason,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (accepted == 0 || result.transaction == null) continue;
        final value = result.transaction!.toMap()..remove('id');
        await transaction.insert('transactions', value);
        imported++;
      }
      return imported;
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
