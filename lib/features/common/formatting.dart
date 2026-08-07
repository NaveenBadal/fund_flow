import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/money_format.dart';

/// Money as this install wants to see it.
///
/// One place decides whether amounts are masked, so turning on "hide amounts"
/// cannot be honoured on the ledger and forgotten on the donut. Every surface
/// that prints money goes through here.
class MoneyFormatter {
  const MoneyFormatter({required this.hidden});
  final bool hidden;

  String call(int minor, String currency) =>
      formatMoney(minor, currency, hidden: hidden);

  /// Always visible, whatever the preference.
  ///
  /// Used inside the transaction editor and the approval card: masking the
  /// figure someone is about to change or approve would make them agree to
  /// something they cannot see.
  String exact(int minor, String currency) => formatMoney(minor, currency);
}

final moneyProvider = Provider<MoneyFormatter>(
  (ref) => MoneyFormatter(
    hidden:
        ref.watch(appControllerProvider).value?.preferences.hideAmounts ??
        false,
  ),
);

/// "Today", "Yesterday", "Wed 6 Aug", "6 Aug 2025".
///
/// Relative names for the two days people think of relatively, then the
/// weekday, then the year once it stops being obvious — a ledger scanned by
/// date is read by weekday more than by number.
String dayLabel(DateTime value, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final day = DateTime(value.year, value.month, value.day);
  final base = DateTime(today.year, today.month, today.day);
  final difference = base.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  if (day.year != base.year) return DateFormat('d MMM y').format(value);
  if (difference < 7 && difference > 0) {
    return DateFormat('EEE d MMM').format(value);
  }
  return DateFormat('EEE d MMM').format(value);
}

String timeLabel(DateTime value) => DateFormat('h:mm a').format(value);

String shortDay(DateTime value) => DateFormat('d MMM').format(value);

String monthLabel(DateTime value) => DateFormat('MMMM').format(value);

String monthYearLabel(DateTime value) => DateFormat('MMMM y').format(value);

/// "in 3 days", "tomorrow", "today", "2 days ago".
String relativeDays(int days) {
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days == -1) return 'yesterday';
  if (days > 1) return 'in $days days';
  return '${days.abs()} days ago';
}

/// Minor units from what someone typed into a major-unit field.
///
/// The model once proposed forty dollars as forty cents. A person typing into
/// the app must never be able to make the same mistake, so the conversion lives
/// in exactly one function with the currency's own exponent.
int? parseMajorToMinor(String input, String currency) {
  final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value <= 0) return null;
  return (value * _minorPerMajor(currency)).round();
}

String minorToMajorInput(int minor, String currency) {
  final per = _minorPerMajor(currency);
  final value = minor / per;
  return per == 1
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
}

int _minorPerMajor(String currency) {
  const zero = {'JPY', 'KRW', 'VND', 'CLP', 'ISK'};
  const three = {'BHD', 'KWD', 'OMR', 'JOD', 'TND'};
  final code = currency.toUpperCase();
  if (zero.contains(code)) return 1;
  if (three.contains(code)) return 1000;
  return 100;
}
