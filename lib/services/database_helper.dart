import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/budget.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/ai_log.dart';
import '../models/merchant_stats.dart';
import '../models/savings_goal.dart';
import '../models/transaction_query.dart';
import '../models/assistant_message.dart';
import 'transaction_duplicate_detector.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('expenses.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 14,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    await _createExpensesTable(db);
    await _createAiLogsTable(db);
    await _createParsedSmsTable(db);
    await _createBudgetsTable(db);
    await _createCustomCategoriesTable(db);
    await _createMerchantCategoryMapTable(db);
    await _createAppMetadataTable(db);
    await _createSavingsGoalsTable(db);
    await _createDismissedActionsTable(db);
    await _createExpenseIndexes(db);
    await _createAssistantMessagesTable(db);
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createAiLogsTable(db);
    if (oldVersion < 3) {
      await _createParsedSmsTable(db);
      await db.execute('''
        INSERT OR IGNORE INTO parsed_sms (body, sender, date, parsed_at)
        SELECT originalSms, '', 0, date FROM expenses
      ''');
    }
    if (oldVersion < 4) {
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'",
      );
      await _createBudgetsTable(db);
    }
    if (oldVersion < 5) {
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN tags TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN split_share REAL DEFAULT NULL",
      );
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN is_recurring INTEGER NOT NULL DEFAULT 0",
      );
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN normalized_merchant TEXT DEFAULT NULL",
      );
    }
    if (oldVersion < 6) {
      await _createCustomCategoriesTable(db);
    }
    if (oldVersion < 7) {
      await _createMerchantCategoryMapTable(db);
      await _createAppMetadataTable(db);
    }
    if (oldVersion < 8) {
      // Columns may already exist if the DB was created at v3+ with the updated
      // _createParsedSmsTable schema. Ignore "duplicate column" errors.
      try {
        await db.execute(
          "ALTER TABLE parsed_sms ADD COLUMN sender TEXT DEFAULT ''",
        );
      } catch (_) {}
      try {
        await db.execute(
          "ALTER TABLE parsed_sms ADD COLUMN date INTEGER DEFAULT 0",
        );
      } catch (_) {}
    }
    if (oldVersion < 9) {
      await _createSavingsGoalsTable(db);
    }
    if (oldVersion < 10) {
      try {
        await db.execute(
          "ALTER TABLE parsed_sms ADD COLUMN skip_reason TEXT NOT NULL DEFAULT ''",
        );
      } catch (_) {}
    }
    if (oldVersion < 11) await _createDismissedActionsTable(db);
    if (oldVersion < 12) await _createExpenseIndexes(db);
    if (oldVersion < 13) await _createAssistantMessagesTable(db);
    if (oldVersion < 14) {
      await db.execute(
        "ALTER TABLE assistant_messages ADD COLUMN filter_details TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  // ─── Table definitions ───────────────────────────────────────────────────

  Future _createExpensesTable(Database db) async {
    await db.execute('''
CREATE TABLE expenses (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  amount              REAL    NOT NULL,
  currency            TEXT    NOT NULL,
  merchant            TEXT    NOT NULL,
  category            TEXT    NOT NULL,
  date                TEXT    NOT NULL,
  originalSms         TEXT    NOT NULL,
  type                TEXT    NOT NULL DEFAULT 'expense',
  tags                TEXT    NOT NULL DEFAULT '',
  split_share         REAL    DEFAULT NULL,
  is_recurring        INTEGER NOT NULL DEFAULT 0,
  normalized_merchant TEXT    DEFAULT NULL
)
''');
  }

  Future<void> _createExpenseIndexes(Database db) async {
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_category_date ON expenses(category, date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_type_date ON expenses(type, date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_currency_date ON expenses(currency, date DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_expenses_merchant_date ON expenses(normalized_merchant, merchant, date DESC)',
    );
  }

  Future<void> _createAssistantMessagesTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS assistant_messages (
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  is_user   INTEGER NOT NULL,
  text      TEXT    NOT NULL,
  sources   INTEGER NOT NULL DEFAULT 0,
  verified  INTEGER NOT NULL DEFAULT 0,
  filter_details TEXT NOT NULL DEFAULT '',
  timestamp TEXT    NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_assistant_messages_time ON assistant_messages(timestamp)',
    );
  }

  Future<List<AssistantMessage>> getAssistantMessages({int limit = 100}) async {
    final db = await instance.database;
    final rows = await db.query(
      'assistant_messages',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.reversed.map(AssistantMessage.fromMap).toList();
  }

  Future<AssistantMessage> insertAssistantMessage(
    AssistantMessage message,
  ) async {
    final db = await instance.database;
    final id = await db.insert('assistant_messages', message.toMap());
    return AssistantMessage(
      id: id,
      user: message.user,
      text: message.text,
      sources: message.sources,
      verified: message.verified,
      filterDetails: message.filterDetails,
      timestamp: message.timestamp,
    );
  }

  Future<void> clearAssistantMessages() async {
    final db = await instance.database;
    await db.delete('assistant_messages');
  }

  Future _createAiLogsTable(Database db) async {
    await db.execute('''
CREATE TABLE ai_logs (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  requestPrompt TEXT    NOT NULL,
  responseBody  TEXT    NOT NULL,
  timestamp     TEXT    NOT NULL,
  status        TEXT    NOT NULL
)
''');
  }

  Future _createParsedSmsTable(Database db) async {
    await db.execute('''
CREATE TABLE parsed_sms (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  body        TEXT    NOT NULL,
  sender      TEXT    NOT NULL DEFAULT '',
  date        INTEGER NOT NULL DEFAULT 0,
  parsed_at   TEXT    NOT NULL,
  skip_reason TEXT    NOT NULL DEFAULT '',
  UNIQUE(body, sender, date)
)
''');
  }

  Future _createBudgetsTable(Database db) async {
    await db.execute('''
CREATE TABLE budgets (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  category     TEXT    NOT NULL UNIQUE,
  limit_amount REAL    NOT NULL,
  currency     TEXT    NOT NULL DEFAULT 'INR'
)
''');
  }

  Future _createDismissedActionsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS dismissed_actions (
  action_key   TEXT PRIMARY KEY,
  dismissed_at TEXT NOT NULL
)
''');
  }

  Future _createCustomCategoriesTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS custom_categories (
  id    INTEGER PRIMARY KEY AUTOINCREMENT,
  name  TEXT    NOT NULL UNIQUE,
  icon  TEXT    NOT NULL DEFAULT 'e148',
  color TEXT    NOT NULL DEFAULT 'FF607D8B'
)
''');
  }

  Future _createMerchantCategoryMapTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS merchant_category_map (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  merchant_key  TEXT    NOT NULL UNIQUE,
  category      TEXT    NOT NULL,
  updated_at    TEXT    NOT NULL
)
''');
  }

  Future _createSavingsGoalsTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS savings_goals (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  name           TEXT    NOT NULL,
  target_amount  REAL    NOT NULL,
  current_amount REAL    NOT NULL DEFAULT 0,
  deadline       TEXT    DEFAULT NULL,
  color_value    INTEGER NOT NULL DEFAULT ${0xFF6750A4}
)
''');
  }

  Future _createAppMetadataTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS app_metadata (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
    await db.execute(
      "INSERT OR IGNORE INTO app_metadata (key, value) VALUES ('last_sync_at', '')",
    );
  }

  // ─── Expense CRUD ────────────────────────────────────────────────────────

  Future<int> insertExpense(Expense expense) async {
    final db = await instance.database;
    return await db.insert('expenses', expense.toMap());
  }

  Future<void> insertExpenses(List<Expense> expenses) async {
    if (expenses.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final e in expenses) {
      batch.insert('expenses', e.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<Expense>> insertExpensesReturning(List<Expense> expenses) async {
    if (expenses.isEmpty) return const [];
    final db = await instance.database;
    const detector = TransactionDuplicateDetector();
    return db.transaction((txn) async {
      final inserted = <Expense>[];
      for (final expense in expenses) {
        final from = expense.date
            .subtract(TransactionDuplicateDetector.candidateWindow)
            .toIso8601String();
        final to = expense.date
            .add(TransactionDuplicateDetector.candidateWindow)
            .toIso8601String();
        final rows = await txn.query(
          'expenses',
          where:
              'amount = ? AND currency = ? AND type = ? AND date BETWEEN ? AND ?',
          whereArgs: [expense.amount, expense.currency, expense.type, from, to],
        );
        final duplicate = rows
            .map(Expense.fromMap)
            .any((existing) => detector.isDuplicate(expense, existing));
        if (duplicate) continue;
        final id = await txn.insert('expenses', expense.toMap());
        inserted.add(expense.copyWith(id: id));
      }
      return inserted;
    });
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await instance.database;
    return await db.update(
      'expenses',
      expense.toMap(),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  /// Batch-update the is_recurring flag for a set of expenses.
  Future<void> updateRecurringFlags(Map<int, bool> flags) async {
    if (flags.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final entry in flags.entries) {
      batch.update(
        'expenses',
        {'is_recurring': entry.value ? 1 : 0},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<int> deleteExpense(int id) async {
    final db = await instance.database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Expense>> getAllExpenses() async {
    final db = await instance.database;
    final result = await db.query('expenses', orderBy: 'date DESC');
    return result.map((json) => Expense.fromMap(json)).toList();
  }

  Future<Expense?> getExpenseById(int id) async {
    final db = await instance.database;
    final rows = await db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Expense.fromMap(rows.single);
  }

  Future<List<Expense>> getEntriesForPeriod(DateTime from, DateTime to) async {
    final db = await instance.database;
    final result = await db.query(
      'expenses',
      where: 'date >= ? AND date <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'date DESC',
    );
    return result.map(Expense.fromMap).toList();
  }

  /// Executes the bounded query language used by the money assistant.
  /// Values are always bound parameters; model-generated SQL is never accepted.
  Future<List<Expense>> queryTransactions(TransactionQuery query) async {
    final db = await instance.database;
    final filter = _transactionFilter(query);
    final rows = await db.query(
      'expenses',
      where: filter.where,
      whereArgs: filter.arguments,
      orderBy: 'date DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<Map<String, dynamic>> summarizeTransactions(
    TransactionQuery query,
  ) async {
    final db = await instance.database;
    final filter = _transactionFilter(query);
    final rows = await db.rawQuery('''
SELECT currency, type, COUNT(*) AS record_count, COALESCE(SUM(amount), 0) AS total
FROM expenses
${filter.where == null ? '' : 'WHERE ${filter.where}'}
GROUP BY currency, type
''', filter.arguments);
    var count = 0;
    final totals = <String, Map<String, double>>{};
    for (final row in rows) {
      count += (row['record_count'] as num).toInt();
      final currency = row['currency'].toString();
      final type = row['type'].toString();
      totals.putIfAbsent(currency, () => {'income': 0, 'expense': 0})[type] =
          (row['total'] as num).toDouble();
    }
    return {
      'applied_filter': query.toJson(),
      'matched_count': count,
      'totals_by_currency': totals,
    };
  }

  ({String? where, List<Object?> arguments}) _transactionFilter(
    TransactionQuery query,
  ) {
    final clauses = <String>[];
    final arguments = <Object?>[];

    void add(String clause, Object? value) {
      clauses.add(clause);
      arguments.add(value);
    }

    if (query.from != null) add('date >= ?', query.from!.toIso8601String());
    if (query.to != null) add('date <= ?', query.to!.toIso8601String());
    if (query.merchant != null) {
      clauses.add(
        '(LOWER(merchant) LIKE ? OR LOWER(COALESCE(normalized_merchant, merchant)) LIKE ?)',
      );
      final value = '%${query.merchant!.toLowerCase()}%';
      arguments.addAll([value, value]);
    }
    if (query.category != null) {
      add('LOWER(category) = ?', query.category!.toLowerCase());
    }
    if (query.direction != null) add('type = ?', query.direction);
    if (query.currency != null) add('UPPER(currency) = ?', query.currency);
    if (query.minimumAmount != null) add('amount >= ?', query.minimumAmount);
    if (query.maximumAmount != null) add('amount <= ?', query.maximumAmount);
    if (query.text != null) {
      clauses.add(
        '(LOWER(merchant) LIKE ? OR LOWER(COALESCE(normalized_merchant, merchant)) LIKE ? '
        'OR LOWER(category) LIKE ? OR LOWER(tags) LIKE ?)',
      );
      final value = '%${query.text!.toLowerCase()}%';
      arguments.addAll([value, value, value, value]);
    }
    return (
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      arguments: arguments,
    );
  }

  Future<List<Expense>> getExpensesByMerchant(String merchant) async {
    final db = await instance.database;
    final result = await db.query(
      'expenses',
      where: "(merchant = ? OR normalized_merchant = ?) AND type = 'expense'",
      whereArgs: [merchant, merchant],
      orderBy: 'date DESC',
    );
    return result.map(Expense.fromMap).toList();
  }

  Future<bool> smsExists(String originalSms) async {
    final db = await instance.database;
    final result = await db.query(
      'expenses',
      columns: ['id'],
      where: 'originalSms = ?',
      whereArgs: [originalSms],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<void> markRecurring(Map<int, bool> flags) async {
    if (flags.isEmpty) return;
    final db = await instance.database;
    final batch = db.batch();
    for (final entry in flags.entries) {
      batch.update(
        'expenses',
        {'is_recurring': entry.value ? 1 : 0},
        where: 'id = ?',
        whereArgs: [entry.key],
      );
    }
    await batch.commit(noResult: true);
  }

  // ─── Parsed SMS ──────────────────────────────────────────────────────────

  Future<bool> isSmsParsed(String body, String sender, int date) async {
    final db = await instance.database;
    final result = await db.query(
      'parsed_sms',
      columns: ['id'],
      where: 'body = ? AND sender = ? AND date = ?',
      whereArgs: [body, sender, date],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<Set<String>> getParsedSmsKeys(int sinceTimestamp) async {
    final db = await instance.database;
    final rows = await db.query(
      'parsed_sms',
      columns: ['body', 'sender', 'date'],
      where: 'date >= ?',
      whereArgs: [sinceTimestamp],
    );
    return rows.map((r) => '${r['sender']}|${r['body']}|${r['date']}').toSet();
  }

  Future<void> markSmsBatchParsed(
    List<Map<String, dynamic>> smsList, {
    Map<String, String> skipReasons = const {},
  }) async {
    if (smsList.isEmpty) return;
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final sms in smsList) {
      final body = sms['body'] as String;
      batch.insert('parsed_sms', {
        'body': body,
        'sender': sms['address'],
        'date': sms['timestamp'],
        'parsed_at': now,
        'skip_reason': skipReasons[body] ?? '',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getParsedSmsAudit() async {
    final db = await instance.database;
    final rows = await db.rawQuery('''
      SELECT
        p.id,
        p.body,
        p.parsed_at,
        p.skip_reason,
        CASE WHEN e.id IS NOT NULL THEN 1 ELSE 0 END AS has_expense
      FROM parsed_sms p
      LEFT JOIN expenses e ON e.originalSms = p.body
      GROUP BY p.id
      ORDER BY p.parsed_at DESC
    ''');
    return rows;
  }

  // ─── Budget CRUD ─────────────────────────────────────────────────────────

  Future<void> insertOrUpdateBudget(Budget budget) async {
    final db = await instance.database;
    await db.insert(
      'budgets',
      budget.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Budget>> getAllBudgets() async {
    final db = await instance.database;
    final result = await db.query('budgets', orderBy: 'category ASC');
    return result.map(Budget.fromMap).toList();
  }

  Future<void> deleteBudget(String category) async {
    final db = await instance.database;
    await db.delete('budgets', where: 'category = ?', whereArgs: [category]);
  }

  // ─── Custom Categories ────────────────────────────────────────────────────

  Future<List<CustomCategory>> getAllCustomCategories() async {
    final db = await instance.database;
    final result = await db.query('custom_categories', orderBy: 'name ASC');
    return result.map(CustomCategory.fromMap).toList();
  }

  Future<void> insertOrUpdateCustomCategory(CustomCategory cat) async {
    final db = await instance.database;
    await db.insert(
      'custom_categories',
      cat.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteCustomCategory(int id) async {
    final db = await instance.database;
    await db.delete('custom_categories', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Merchant category learning ───────────────────────────────────────────

  Future<Map<String, String>> getMerchantCategoryMap() async {
    final db = await instance.database;
    final rows = await db.query('merchant_category_map');
    return {
      for (final r in rows)
        r['merchant_key'] as String: r['category'] as String,
    };
  }

  Future<void> upsertMerchantCategory(
    String merchantKey,
    String category,
  ) async {
    final db = await instance.database;
    await db.insert('merchant_category_map', {
      'merchant_key': merchantKey.toLowerCase().trim(),
      'category': category,
      'updated_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─── App metadata ─────────────────────────────────────────────────────────

  Future<String?> getAppMetadata(String key) async {
    final db = await instance.database;
    final result = await db.query(
      'app_metadata',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isEmpty) return null;
    final val = result.first['value'] as String?;
    return (val == null || val.isEmpty) ? null : val;
  }

  Future<void> setAppMetadata(String key, String value) async {
    final db = await instance.database;
    await db.insert('app_metadata', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ─── Analytics queries ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMonthlyTotals({int months = 6}) async {
    final db = await instance.database;
    final cutoff = DateTime.now().subtract(Duration(days: months * 31));
    final rows = await db.rawQuery(
      '''
      SELECT
        CAST(strftime('%Y', date) AS INTEGER) AS year,
        CAST(strftime('%m', date) AS INTEGER) AS month,
        SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) AS total_expense,
        SUM(CASE WHEN type = 'income'  THEN amount ELSE 0 END) AS total_income
      FROM expenses
      WHERE date >= ?
      GROUP BY year, month
      ORDER BY year DESC, month DESC
    ''',
      [cutoff.toIso8601String()],
    );
    return rows;
  }

  Future<Map<String, double>> getCategoryTotals(
    DateTime from,
    DateTime to,
  ) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT category, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense'
        AND date >= ? AND date <= ?
      GROUP BY category
    ''',
      [from.toIso8601String(), to.toIso8601String()],
    );
    return {
      for (final r in rows)
        r['category'] as String: (r['total'] as num).toDouble(),
    };
  }

  Future<List<Map<String, dynamic>>> getTopMerchants(
    DateTime from,
    DateTime to, {
    int limit = 7,
  }) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(normalized_merchant, merchant) AS merchant,
        SUM(amount)  AS total,
        COUNT(*)     AS txn_count
      FROM expenses
      WHERE type = 'expense'
        AND date >= ? AND date <= ?
      GROUP BY COALESCE(normalized_merchant, merchant)
      ORDER BY total DESC
      LIMIT ?
    ''',
      [from.toIso8601String(), to.toIso8601String(), limit],
    );
    return rows;
  }

  Future<Map<String, double>> getMonthlyBalance(int year, int month) async {
    final db = await instance.database;
    final pad = month.toString().padLeft(2, '0');
    final rows = await db.rawQuery(
      '''
      SELECT type, SUM(amount) AS total
      FROM expenses
      WHERE strftime('%Y-%m', date) = ?
      GROUP BY type
    ''',
      ['$year-$pad'],
    );
    final result = <String, double>{'income': 0, 'expense': 0};
    for (final r in rows) {
      result[r['type'] as String] = (r['total'] as num).toDouble();
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getBudgetProgress(
    int year,
    int month,
  ) async {
    final db = await instance.database;
    final pad = month.toString().padLeft(2, '0');
    final rows = await db.rawQuery(
      '''
      SELECT b.category,
             COALESCE(SUM(e.amount), 0) AS spent,
             b.limit_amount,
             b.currency
      FROM budgets b
      LEFT JOIN expenses e
        ON e.category = b.category
        AND e.type = 'expense'
        AND strftime('%Y-%m', e.date) = ?
      GROUP BY b.category
      ORDER BY b.category
    ''',
      ['$year-$pad'],
    );
    return rows;
  }

  /// Daily spend totals for heatmap calendar.
  Future<Map<DateTime, double>> getDailyTotals(
    DateTime from,
    DateTime to,
  ) async {
    final db = await instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT date(date) AS day, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense'
        AND date >= ? AND date <= ?
      GROUP BY day
    ''',
      [from.toIso8601String(), to.toIso8601String()],
    );
    final result = <DateTime, double>{};
    for (final r in rows) {
      final dayStr = r['day'] as String;
      final day = DateTime.parse(dayStr);
      result[day] = (r['total'] as num).toDouble();
    }
    return result;
  }

  /// Aggregate stats + 6-month monthly totals for one merchant.
  Future<MerchantStats> getMerchantStats(String merchant) async {
    final db = await instance.database;

    final agg = await db.rawQuery(
      '''
      SELECT
        SUM(amount) AS lifetime_total,
        COUNT(*) AS txn_count,
        MIN(date) AS first_date,
        AVG(amount) AS avg_amount
      FROM expenses
      WHERE type = 'expense'
        AND (LOWER(COALESCE(normalized_merchant, merchant)) = LOWER(?))
    ''',
      [merchant],
    );

    final cutoff = DateTime.now().subtract(const Duration(days: 180));
    final monthly = await db.rawQuery(
      '''
      SELECT
        CAST(strftime('%Y', date) AS INTEGER) AS year,
        CAST(strftime('%m', date) AS INTEGER) AS month,
        SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense'
        AND date >= ?
        AND (LOWER(COALESCE(normalized_merchant, merchant)) = LOWER(?))
      GROUP BY year, month
      ORDER BY year ASC, month ASC
    ''',
      [cutoff.toIso8601String(), merchant],
    );

    final aggRow = agg.isNotEmpty ? agg.first : {};
    return MerchantStats(
      merchant: merchant,
      lifetimeTotal: (aggRow['lifetime_total'] as num?)?.toDouble() ?? 0.0,
      transactionCount: (aggRow['txn_count'] as int?) ?? 0,
      firstTransactionDate: aggRow['first_date'] != null
          ? DateTime.tryParse(aggRow['first_date'] as String)
          : null,
      averageAmount: (aggRow['avg_amount'] as num?)?.toDouble() ?? 0.0,
      monthlyTotals: monthly
          .map(
            (r) => MonthlyMerchantTotal(
              year: r['year'] as int,
              month: r['month'] as int,
              total: (r['total'] as num).toDouble(),
            ),
          )
          .toList(),
    );
  }

  /// Year in review data.
  Future<Map<String, dynamic>> getYearInReview(int year) async {
    final db = await instance.database;

    final topMerchantRows = await db.rawQuery(
      '''
      SELECT COALESCE(normalized_merchant, merchant) AS merchant, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
      GROUP BY merchant ORDER BY total DESC LIMIT 1
    ''',
      ['$year'],
    );

    final topCategoryRows = await db.rawQuery(
      '''
      SELECT category, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
      GROUP BY category ORDER BY total DESC LIMIT 1
    ''',
      ['$year'],
    );

    final totalRows = await db.rawQuery(
      '''
      SELECT SUM(amount) AS total FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
    ''',
      ['$year'],
    );

    final maxDayRows = await db.rawQuery(
      '''
      SELECT date(date) AS day, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
      GROUP BY day ORDER BY total DESC LIMIT 1
    ''',
      ['$year'],
    );

    // Days with at least one expense
    final activeDayRows = await db.rawQuery(
      '''
      SELECT COUNT(DISTINCT date(date)) AS active_days
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
    ''',
      ['$year'],
    );

    return {
      'topMerchant': topMerchantRows.isNotEmpty
          ? topMerchantRows.first['merchant'] as String?
          : null,
      'topMerchantTotal': topMerchantRows.isNotEmpty
          ? (topMerchantRows.first['total'] as num?)?.toDouble() ?? 0.0
          : 0.0,
      'topCategory': topCategoryRows.isNotEmpty
          ? topCategoryRows.first['category'] as String?
          : null,
      'totalSpent':
          (totalRows.isNotEmpty
              ? (totalRows.first['total'] as num?)?.toDouble()
              : null) ??
          0.0,
      'maxSpendDay': maxDayRows.isNotEmpty
          ? maxDayRows.first['day'] as String?
          : null,
      'maxSpendAmount': maxDayRows.isNotEmpty
          ? (maxDayRows.first['total'] as num?)?.toDouble() ?? 0.0
          : 0.0,
      'activeDays':
          (activeDayRows.isNotEmpty
              ? activeDayRows.first['active_days'] as int?
              : null) ??
          0,
      'zeroSpendDays':
          365 -
          ((activeDayRows.isNotEmpty
                  ? activeDayRows.first['active_days'] as int?
                  : null) ??
              0),
    };
  }

  // ─── AI Log methods ──────────────────────────────────────────────────────

  Future<int> insertAiLog(AiLog log) async {
    final db = await instance.database;
    return await db.insert('ai_logs', log.toMap());
  }

  Future<List<AiLog>> getAllAiLogs() async {
    final db = await instance.database;
    final result = await db.query('ai_logs', orderBy: 'timestamp DESC');
    return result.map((json) => AiLog.fromMap(json)).toList();
  }

  Future<void> clearAiLogs() async {
    final db = await instance.database;
    await db.delete('ai_logs');
  }

  // ─── Savings Goals CRUD ──────────────────────────────────────────────────

  Future<int> insertOrUpdateSavingsGoal(SavingsGoal goal) async {
    final db = await instance.database;
    return await db.insert(
      'savings_goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SavingsGoal>> getAllSavingsGoals() async {
    final db = await instance.database;
    final result = await db.query('savings_goals', orderBy: 'name ASC');
    return result.map(SavingsGoal.fromMap).toList();
  }

  Future<void> deleteSavingsGoal(int id) async {
    final db = await instance.database;
    await db.delete('savings_goals', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Parsed SMS retry ────────────────────────────────────────────────────

  Future<void> unmarkSmsParsed(List<String> bodies) async {
    if (bodies.isEmpty) return;
    final db = await instance.database;
    final placeholders = List.filled(bodies.length, '?').join(', ');
    await db.rawDelete(
      'DELETE FROM parsed_sms WHERE body IN ($placeholders)',
      bodies,
    );
  }

  // ─── Action inbox dismissals ────────────────────────────────────────────

  Future<Set<String>> getDismissedActionKeys() async {
    final db = await instance.database;
    final rows = await db.query('dismissed_actions', columns: ['action_key']);
    return rows.map((row) => row['action_key'] as String).toSet();
  }

  Future<void> dismissAction(String key) async {
    final db = await instance.database;
    await db.insert('dismissed_actions', {
      'action_key': key,
      'dismissed_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> restoreAction(String key) async {
    final db = await instance.database;
    await db.delete(
      'dismissed_actions',
      where: 'action_key = ?',
      whereArgs: [key],
    );
  }

  Future close() async {
    final db = _database;
    if (db != null) await db.close();
    _database = null;
  }
}
