import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams, XFile;
import 'package:intl/intl.dart';
import '../models/expense.dart';
import 'pdf_service.dart';

class ExportService {
  const ExportService();

  Future<void> exportCsv(List<Expense> expenses) async {
    final buffer = StringBuffer();
    buffer.writeln('Date,Type,Merchant,NormalizedMerchant,Category,Amount,Currency,Tags,SplitShare,IsRecurring,OriginalSMS');

    for (final e in expenses) {
      buffer.writeln([
        _esc(DateFormat('yyyy-MM-dd HH:mm').format(e.date.toLocal())),
        _esc(e.type),
        _esc(e.merchant),
        _esc(e.normalizedMerchant ?? ''),
        _esc(e.category),
        e.amount.toStringAsFixed(2),
        _esc(e.currency),
        _esc(e.tags),
        e.splitShare?.toStringAsFixed(2) ?? '',
        e.isRecurring ? '1' : '0',
        _esc(e.originalSms.replaceAll('\n', ' ')),
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/expenses_export.csv');
    await file.writeAsString(buffer.toString());

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Expense Manager Export',
      ),
    );
  }

  Future<void> exportPdf({
    required int year,
    required int month,
    required List<Expense> expenses,
    required List<Map<String, dynamic>> budgetProgress,
  }) async {
    final file = await PdfService.generateMonthlyStatement(
      year: year,
      month: month,
      expenses: expenses,
      budgetProgress: budgetProgress,
    );

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Monthly Statement',
      ),
    );
  }

  String _esc(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') || escaped.contains('"') || escaped.contains('\n')) {
      return '"$escaped"';
    }
    return escaped;
  }
}
