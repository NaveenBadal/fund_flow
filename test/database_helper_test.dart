import 'dart:io';

import 'package:expense_manager/models/assistant_message.dart';
import 'package:expense_manager/models/expense.dart';
import 'package:expense_manager/models/transaction_query.dart';
import 'package:expense_manager/services/database_helper.dart';
import 'package:expense_manager/services/local_money_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory databaseDirectory;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    databaseDirectory = await Directory.systemTemp.createTemp(
      'expense-manager-database-test-',
    );
    await databaseFactory.setDatabasesPath(databaseDirectory.path);
  });

  tearDownAll(() async {
    await DatabaseHelper.instance.close();
    await databaseDirectory.delete(recursive: true);
  });

  test(
    'persists conversations and aggregates filtered transactions in SQL',
    () async {
      final database = DatabaseHelper.instance;
      await database.insertExpenses([
        Expense(
          amount: 200,
          currency: 'INR',
          merchant: 'Cafe One',
          category: 'Food',
          date: DateTime(2026, 6, 20, 9),
          originalSms:
              'INR 200 debited from account at BLUE TOKAI on 20-06-2026.',
        ),
        Expense(
          amount: 300,
          currency: 'INR',
          merchant: 'Cafe Two',
          category: 'Food',
          date: DateTime(2026, 6, 20, 18),
          originalSms: '',
        ),
        Expense(
          amount: 999,
          currency: 'INR',
          merchant: 'Other day',
          category: 'Shopping',
          date: DateTime(2026, 6, 21),
          originalSms: '',
        ),
      ]);

      final summary = await database.summarizeTransactions(
        TransactionQuery(
          from: DateTime(2026, 6, 20),
          to: DateTime(2026, 6, 20, 23, 59, 59, 999, 999),
        ),
      );
      expect(summary['matched_count'], 2);
      expect(
        ((summary['totals_by_currency'] as Map)['INR'] as Map)['expense'],
        500,
      );

      final matching = await database.queryTransactions(
        const TransactionQuery(category: 'Food'),
      );
      final transactionId = matching
          .firstWhere((transaction) => transaction.merchant == 'Cafe One')
          .id!;
      final mcp = LocalMoneyMcpClient(LocalMoneyMcpServer(database));
      final source = await mcp.callTool('reanalyze_transaction_sms', {
        'id': transactionId,
      });
      expect(source.isError, isFalse);
      expect(source.structuredContent['original_sms'], contains('BLUE TOKAI'));

      final correction = await mcp.callTool('update_transaction', {
        'id': transactionId,
        'category': 'Dining',
        'recurring': true,
      });
      expect(correction.isError, isFalse);
      final corrected = await database.getExpenseById(transactionId);
      expect(corrected?.category, 'Dining');
      expect(corrected?.isRecurring, isTrue);

      final budget = await mcp.callTool('manage_budget', {
        'category': 'Dining',
        'limit_amount': 3000,
        'currency': 'INR',
      });
      expect(budget.isError, isFalse);
      expect((await database.getAllBudgets()).single.limitAmount, 3000);

      await database.insertAssistantMessage(
        AssistantMessage(
          user: true,
          text: 'What happened on 20 June?',
          timestamp: DateTime(2026, 7, 16),
        ),
      );
      final messages = await database.getAssistantMessages();
      expect(messages.single.text, 'What happened on 20 June?');
    },
  );
}
