import 'dart:io';
import '../models/expense.dart';
import 'merchant_normalizer.dart';

/// Parses bank statement CSV files into Expense objects.
/// Supports HDFC, ICICI, Axis, SBI, and Kotak formats.
class BankCsvImporter {
  const BankCsvImporter();

  static Future<List<Expense>> parse(File file) async {
    final lines = await file.readAsLines();
    if (lines.isEmpty) return [];

    // Find the header line (first line with 3+ comma-separated values)
    int headerIndex = -1;
    for (int i = 0; i < lines.length && i < 20; i++) {
      final parts = _splitCsv(lines[i]);
      if (parts.length >= 3) {
        headerIndex = i;
        break;
      }
    }
    if (headerIndex < 0) return [];

    final headers = _splitCsv(lines[headerIndex])
        .map((h) => h.toLowerCase().trim().replaceAll('"', ''))
        .toList();

    // Detect column indices
    final dateCol = _findCol(headers, ['date', 'txn date', 'transaction date', 'value date']);
    final descCol = _findCol(headers, [
      'description', 'narration', 'particulars', 'remarks', 'transaction details',
      'transaction remarks', 'details', 'merchant'
    ]);
    final debitCol = _findCol(headers, ['debit', 'debit amount', 'withdrawal', 'withdrawal amt']);
    final creditCol = _findCol(headers, ['credit', 'credit amount', 'deposit', 'deposit amt']);
    final amtCol = _findCol(headers, ['amount', 'transaction amount', 'txn amount']);

    if (dateCol < 0 || descCol < 0 || (debitCol < 0 && amtCol < 0)) {
      return [];
    }

    final expenses = <Expense>[];
    for (int i = headerIndex + 1; i < lines.length; i++) {
      final row = _splitCsv(lines[i]);
      if (row.isEmpty || row.every((c) => c.trim().isEmpty)) continue;

      try {
        final dateStr = _cell(row, dateCol);
        final desc = _cell(row, descCol);
        if (dateStr.isEmpty || desc.isEmpty) continue;

        final date = _parseDate(dateStr);
        if (date == null) continue;

        double amount = 0;
        String type = 'expense';

        if (amtCol >= 0) {
          amount = _parseAmount(_cell(row, amtCol));
          // Check sign to determine type
          if (creditCol >= 0 && _parseAmount(_cell(row, creditCol)) > 0) {
            type = 'income';
          }
        } else {
          final debit = debitCol >= 0 ? _parseAmount(_cell(row, debitCol)) : 0.0;
          final credit = creditCol >= 0 ? _parseAmount(_cell(row, creditCol)) : 0.0;
          if (debit > 0) {
            amount = debit;
            type = 'expense';
          } else if (credit > 0) {
            amount = credit;
            type = 'income';
          } else {
            continue;
          }
        }

        if (amount <= 0) continue;

        final merchant = MerchantNormalizer.normalize(desc);

        expenses.add(Expense(
          amount: amount,
          currency: 'INR',
          merchant: desc,
          normalizedMerchant: merchant != desc ? merchant : null,
          category: _guessCategory(desc),
          date: date,
          originalSms: 'imported:csv',
          type: type,
        ));
      } catch (_) {
        // Skip malformed rows
      }
    }

    return expenses;
  }

  static int _findCol(List<String> headers, List<String> candidates) {
    for (final candidate in candidates) {
      final idx = headers.indexOf(candidate);
      if (idx >= 0) return idx;
    }
    // Partial match
    for (final candidate in candidates) {
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].contains(candidate)) return i;
      }
    }
    return -1;
  }

  static String _cell(List<String> row, int col) {
    if (col < 0 || col >= row.length) return '';
    return row[col].trim().replaceAll('"', '');
  }

  static double _parseAmount(String raw) {
    if (raw.isEmpty) return 0;
    final cleaned = raw.replaceAll(RegExp(r'[^\d.]'), '');
    return double.tryParse(cleaned) ?? 0;
  }

  static DateTime? _parseDate(String raw) {
    final formats = [
      RegExp(r'^(\d{2})[/\-](\d{2})[/\-](\d{4})$'), // DD/MM/YYYY
      RegExp(r'^(\d{4})[/\-](\d{2})[/\-](\d{2})$'), // YYYY-MM-DD
      RegExp(r'^(\d{2})[/\-](\d{2})[/\-](\d{2})$'), // DD/MM/YY
    ];

    final cleaned = raw.trim().replaceAll('"', '');

    final m0 = formats[0].firstMatch(cleaned);
    if (m0 != null) {
      return DateTime.tryParse(
          '${m0.group(3)!}-${m0.group(2)!.padLeft(2, '0')}-${m0.group(1)!.padLeft(2, '0')}');
    }

    final m1 = formats[1].firstMatch(cleaned);
    if (m1 != null) return DateTime.tryParse(cleaned);

    final m2 = formats[2].firstMatch(cleaned);
    if (m2 != null) {
      final year = int.tryParse(m2.group(3)!) ?? 0;
      final fullYear = year < 50 ? 2000 + year : 1900 + year;
      return DateTime.tryParse(
          '$fullYear-${m2.group(2)!.padLeft(2, '0')}-${m2.group(1)!.padLeft(2, '0')}');
    }

    return null;
  }

  static List<String> _splitCsv(String line) {
    final result = <String>[];
    bool inQuotes = false;
    final current = StringBuffer();

    for (final char in line.runes) {
      final c = String.fromCharCode(char);
      if (c == '"') {
        inQuotes = !inQuotes;
      } else if (c == ',' && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(c);
      }
    }
    result.add(current.toString());
    return result;
  }

  static String _guessCategory(String desc) {
    final d = desc.toLowerCase();
    if (d.contains('swiggy') || d.contains('zomato') || d.contains('restaurant') ||
        d.contains('food') || d.contains('cafe') || d.contains('pizza') ||
        d.contains('kfc') || d.contains('mcdonald')) {
      return 'Food';
    }
    if (d.contains('uber') || d.contains('ola') || d.contains('metro') ||
        d.contains('petrol') || d.contains('fuel') || d.contains('irctc') ||
        d.contains('indigo') || d.contains('spicejet')) {
      return 'Transport';
    }
    if (d.contains('netflix') || d.contains('spotify') || d.contains('prime') ||
        d.contains('hotstar') || d.contains('youtube') || d.contains('movie') ||
        d.contains('pvr') || d.contains('inox')) {
      return 'Entertainment';
    }
    if (d.contains('electricity') || d.contains('water') || d.contains('gas') ||
        d.contains('broadband') || d.contains('airtel') || d.contains('jio') ||
        d.contains('bsnl') || d.contains('utility')) {
      return 'Utilities';
    }
    if (d.contains('amazon') || d.contains('flipkart') || d.contains('myntra') ||
        d.contains('meesho') || d.contains('nykaa') || d.contains('ajio')) {
      return 'Shopping';
    }
    if (d.contains('hospital') || d.contains('pharmacy') || d.contains('apollo') ||
        d.contains('medic') || d.contains('doctor') || d.contains('clinic')) {
      return 'Health';
    }
    return 'Others';
  }
}
