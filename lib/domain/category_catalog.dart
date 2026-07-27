import 'transaction.dart';

const expenseCategories = [
  'Food',
  'Groceries',
  'Transport',
  'Shopping',
  'Bills',
  'Health',
  'Entertainment',
  'Subscriptions',
  'Transfer',
  'Other',
];

const incomeCategories = [
  'Income',
  'Salary',
  'Refund',
  'Cashback',
  'Interest',
  'Business',
  'Transfer',
  'Other',
];

List<String> categoriesFor(TransactionDirection direction) =>
    direction == TransactionDirection.incoming
    ? incomeCategories
    : expenseCategories;

String defaultCategoryFor(TransactionDirection direction) =>
    direction == TransactionDirection.incoming ? 'Income' : 'Other';
