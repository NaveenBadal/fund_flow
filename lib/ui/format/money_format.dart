import 'package:intl/intl.dart';

String formatMoney(int minor, String currency, {bool hidden = false}) {
  if (hidden) return '••••';
  final digits = currency == 'JPY' ? 0 : 2;
  return NumberFormat.simpleCurrency(
    name: currency,
    decimalDigits: digits,
  ).format(minor / (digits == 0 ? 1 : 100));
}
