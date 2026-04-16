import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/expense.dart';

class PdfService {
  const PdfService();

  static Future<File> generateMonthlyStatement({
    required int year,
    required int month,
    required List<Expense> expenses,
    required List<Map<String, dynamic>> budgetProgress,
  }) async {
    final pdf = pw.Document();
    final monthLabel = DateFormat('MMMM yyyy').format(DateTime(year, month));
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    final monthExpenses = expenses
        .where((e) => !e.isIncome && e.date.year == year && e.date.month == month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final totalExpense = monthExpenses.fold(0.0, (s, e) => s + e.amount);
    final totalIncome = expenses
        .where((e) => e.isIncome && e.date.year == year && e.date.month == month)
        .fold(0.0, (s, e) => s + e.amount);

    // Category breakdown
    final categoryTotals = <String, double>{};
    for (final e in monthExpenses) {
      categoryTotals.update(e.category, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    final sortedCategories = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Top merchants
    final merchantTotals = <String, double>{};
    for (final e in monthExpenses) {
      final key = e.displayMerchant;
      merchantTotals.update(key, (v) => v + e.amount, ifAbsent: () => e.amount);
    }
    final topMerchants = merchantTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = topMerchants.take(5).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Expense Statement',
              style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              monthLabel,
              style: const pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
            ),
            pw.Divider(),
          ],
        ),
        build: (ctx) => [
          // Summary
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _summaryItem('Total Expenses', fmt.format(totalExpense)),
                _summaryItem('Total Income', fmt.format(totalIncome)),
                _summaryItem('Net', fmt.format(totalIncome - totalExpense)),
                _summaryItem('Transactions', '${monthExpenses.length}'),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // Category breakdown
          if (sortedCategories.isNotEmpty) ...[
            pw.Text('Category Breakdown',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('Category', bold: true),
                    _tableCell('Amount', bold: true),
                    _tableCell('% of Total', bold: true),
                  ],
                ),
                ...sortedCategories.map((e) => pw.TableRow(
                      children: [
                        _tableCell(e.key),
                        _tableCell(fmt.format(e.value)),
                        _tableCell(
                          totalExpense > 0
                              ? '${(e.value / totalExpense * 100).toStringAsFixed(1)}%'
                              : '—',
                        ),
                      ],
                    )),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          // Top merchants
          if (top5.isNotEmpty) ...[
            pw.Text('Top Merchants',
                style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _tableCell('Merchant', bold: true),
                    _tableCell('Total', bold: true),
                  ],
                ),
                ...top5.map((e) => pw.TableRow(
                      children: [
                        _tableCell(e.key),
                        _tableCell(fmt.format(e.value)),
                      ],
                    )),
              ],
            ),
            pw.SizedBox(height: 20),
          ],

          // Transaction list
          pw.Text('Transactions',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.5),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1.5),
              3: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _tableCell('Date', bold: true),
                  _tableCell('Merchant', bold: true),
                  _tableCell('Category', bold: true),
                  _tableCell('Amount', bold: true),
                ],
              ),
              ...monthExpenses.map((e) => pw.TableRow(
                    children: [
                      _tableCell(DateFormat('dd MMM').format(e.date)),
                      _tableCell(e.displayMerchant),
                      _tableCell(e.category),
                      _tableCell(fmt.format(e.amount)),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/statement_${year}_${month.toString().padLeft(2, '0')}.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static pw.Widget _summaryItem(String label, String value) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.Text(value, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ],
      );

  static pw.Widget _tableCell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.all(6),
        child: pw.Text(
          text,
          style: bold ? pw.TextStyle(fontWeight: pw.FontWeight.bold) : null,
        ),
      );
}
