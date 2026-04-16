import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/budget.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/ai_log.dart';
import '../models/merchant_stats.dart';

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
      version: 8,
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
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) await _createAiLogsTable(db);
    if (oldVersion < 3) {
      await _createParsedSmsTable(db);
      await db.execute('''
        INSERT OR IGNORE INTO parsed_sms (body, parsed_at)
        SELECT originalSms, date FROM expenses
      ''');
    }
    if (oldVersion < 4) {
      await db.execute(
          "ALTER TABLE expenses ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'");
      await _createBudgetsTable(db);
    }
    if (oldVersion < 5) {
      await db.execute("ALTER TABLE expenses ADD COLUMN tags TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE expenses ADD COLUMN split_share REAL DEFAULT NULL");
      await db.execute("ALTER TABLE expenses ADD COLUMN is_recurring INTEGER NOT NULL DEFAULT 0");
      await db.execute("ALTER TABLE expenses ADD COLUMN normalized_merchant TEXT DEFAULT NULL");
    }
    if (oldVersion < 6) {
      await _createCustomCategoriesTable(db);
    }
    if (oldVersion < 7) {
      await _createMerchantCategoryMapTable(db);
      await _createAppMetadataTable(db);
    }
    if (oldVersion < 8) {
      await db.execute("ALTER TABLE parsed_sms ADD COLUMN sender TEXT DEFAULT ''");
      await db.execute("ALTER TABLE parsed_sms ADD COLUMN date INTEGER DEFAULT 0");
      // Add unique constraint on (body, sender, date) if needed, 
      // but for now we just add the columns. 
      // sqlite doesn't support easy 'ALTER TABLE ADD UNIQUE'
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
  id        INTEGER PRIMARY KEY AUTOINCREMENT,
  body      TEXT    NOT NULL,
  sender    TEXT    NOT NULL,
  date      INTEGER NOT NULL,
  parsed_at TEXT    NOT NULL,
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

  Future _createAppMetadataTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS app_metadata (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');
    await db.execute(
        "INSERT OR IGNORE INTO app_metadata (key, value) VALUES ('last_sync_at', '')");
  }

  // ─── Expense CRUD ────────────────────────────────────────────────────────

  Future<int> insertExpense(Expense expense) async {
    final db = await instance.database;
    return await db.insert('expenses', expense.toMap());
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

  Future<int> deleteExpense(int id) async {
    final db = await instance.database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Expense>> getAllExpenses() async {
    final db = await instance.database;
    final result = await db.query('expenses', orderBy: 'date DESC');
    return result.map((json) => Expense.fromMap(json)).toList();
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

  Future<void> markSmsBatchParsed(List<Map<String, dynamic>> smsList) async {
    if (smsList.isEmpty) return;
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final sms in smsList) {
      batch.insert(
        'parsed_sms',
        {
          'body': sms['body'],
          'sender': sms['address'],
          'date': sms['timestamp'],
          'parsed_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
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
    return {for (final r in rows) r['merchant_key'] as String: r['category'] as String};
  }

  Future<void> upsertMerchantCategory(String merchantKey, String category) async {
    final db = await instance.database;
    await db.insert(
      'merchant_category_map',
      {
        'merchant_key': merchantKey.toLowerCase().trim(),
        'category': category,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
    await db.insert(
      'app_metadata',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── Analytics queries ───────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getMonthlyTotals({int months = 6}) async {
    final db = await instance.database;
    final cutoff = DateTime.now().subtract(Duration(days: months * 31));
    final rows = await db.rawQuery('''
      SELECT
        CAST(strftime('%Y', date) AS INTEGER) AS year,
        CAST(strftime('%m', date) AS INTEGER) AS month,
        SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) AS total_expense,
        SUM(CASE WHEN type = 'income'  THEN amount ELSE 0 END) AS total_income
      FROM expenses
      WHERE date >= ?
      GROUP BY year, month
      ORDER BY year DESC, month DESC
    ''', [cutoff.toIso8601String()]);
    return rows;
  }

  Future<Map<String, double>> getCategoryTotals(
      DateTime from, DateTime to) async {
    final db = await instance.database;
    final rows = await db.rawQuery('''
      SELECT category, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense'
        AND date >= ? AND date <= ?
      GROUP BY category
    ''', [from.toIso8601String(), to.toIso8601String()]);
    return {
      for (final r in rows)
        r['category'] as String: (r['total'] as num).toDouble()
    };
  }

  Future<List<Map<String, dynamic>>> getTopMerchants(
      DateTime from, DateTime to,
      {int limit = 7}) async {
    final db = await instance.database;
    final rows = await db.rawQuery('''
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
    ''', [from.toIso8601String(), to.toIso8601String(), limit]);
    return rows;
  }

  Future<Map<String, double>> getMonthlyBalance(int year, int month) async {
    final db = await instance.database;
    final pad = month.toString().padLeft(2, '0');
    final rows = await db.rawQuery('''
      SELECT type, SUM(amount) AS total
      FROM expenses
      WHERE strftime('%Y-%m', date) = ?
      GROUP BY type
    ''', ['$year-$pad']);
    final result = <String, double>{'income': 0, 'expense': 0};
    for (final r in rows) {
      result[r['type'] as String] = (r['total'] as num).toDouble();
    }
    return result;
  }

  Future<List<Map<String, dynamic>>> getBudgetProgress(
      int year, int month) async {
    final db = await instance.database;
    final pad = month.toString().padLeft(2, '0');
    final rows = await db.rawQuery('''
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
    ''', ['$year-$pad']);
    return rows;
  }

  /// Daily spend totals for heatmap calendar.
  Future<Map<DateTime, double>> getDailyTotals(
      DateTime from, DateTime to) async {
    final db = await instance.database;
    final rows = await db.rawQuery('''
      SELECT date(date) AS day, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense'
        AND date >= ? AND date <= ?
      GROUP BY day
    ''', [from.toIso8601String(), to.toIso8601String()]);
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

    final agg = await db.rawQuery('''
      SELECT
        SUM(amount) AS lifetime_total,
        COUNT(*) AS txn_count,
        MIN(date) AS first_date,
        AVG(amount) AS avg_amount
      FROM expenses
      WHERE type = 'expense'
        AND (LOWER(COALESCE(normalized_merchant, merchant)) = LOWER(?))
    ''', [merchant]);

    final cutoff = DateTime.now().subtract(const Duration(days: 180));
    final monthly = await db.rawQuery('''
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
    ''', [cutoff.toIso8601String(), merchant]);

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
          .map((r) => MonthlyMerchantTotal(
                year: r['year'] as int,
                month: r['month'] as int,
                total: (r['total'] as num).toDouble(),
              ))
          .toList(),
    );
  }

  /// Year in review data.
  Future<Map<String, dynamic>> getYearInReview(int year) async {
    final db = await instance.database;

    final topMerchantRows = await db.rawQuery('''
      SELECT COALESCE(normalized_merchant, merchant) AS merchant, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
      GROUP BY merchant ORDER BY total DESC LIMIT 1
    ''', ['$year']);

    final topCategoryRows = await db.rawQuery('''
      SELECT category, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
      GROUP BY category ORDER BY total DESC LIMIT 1
    ''', ['$year']);

    final totalRows = await db.rawQuery('''
      SELECT SUM(amount) AS total FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
    ''', ['$year']);

    final maxDayRows = await db.rawQuery('''
      SELECT date(date) AS day, SUM(amount) AS total
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
      GROUP BY day ORDER BY total DESC LIMIT 1
    ''', ['$year']);

    // Days with at least one expense
    final activeDayRows = await db.rawQuery('''
      SELECT COUNT(DISTINCT date(date)) AS active_days
      FROM expenses
      WHERE type = 'expense' AND strftime('%Y', date) = ?
    ''', ['$year']);

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
      'totalSpent': (totalRows.isNotEmpty
              ? (totalRows.first['total'] as num?)?.toDouble()
              : null) ??
          0.0,
      'maxSpendDay': maxDayRows.isNotEmpty
          ? maxDayRows.first['day'] as String?
          : null,
      'maxSpendAmount': maxDayRows.isNotEmpty
          ? (maxDayRows.first['total'] as num?)?.toDouble() ?? 0.0
          : 0.0,
      'activeDays': (activeDayRows.isNotEmpty
              ? activeDayRows.first['active_days'] as int?
              : null) ??
          0,
      'zeroSpendDays': 365 -
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

  Future close() async {
    final db = _database;
    if (db != null) await db.close();
    _database = null;
  }
}
