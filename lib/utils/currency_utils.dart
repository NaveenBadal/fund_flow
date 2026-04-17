import 'package:intl/intl.dart';

const _symbols = <String, String>{
  'INR': '₹',
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
  'JPY': '¥',
  'AED': 'د.إ',
  'SGD': 'S\$',
  'AUD': 'A\$',
  'CAD': 'C\$',
};

String symbolFor(String currency) =>
    _symbols[currency.toUpperCase()] ?? currency.toUpperCase();

/// Format an amount with the correct locale and symbol for the given currency.
String formatAmount(double amount, String currency) {
  final code = currency.toUpperCase();
  final symbol = _symbols[code] ?? code;
  final locale = code == 'INR' ? 'en_IN' : 'en_US';
  return NumberFormat.currency(locale: locale, symbol: symbol).format(amount);
}

/// Returns a masked placeholder for private mode, e.g. "₹ ••••".
String maskAmount(String currency) => '${symbolFor(currency)} ••••';
