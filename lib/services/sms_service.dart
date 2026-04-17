import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';

class SmsService {
  final SmsQuery _query = SmsQuery();

  Future<bool> requestPermissions() async {
    var status = await Permission.sms.status;
    if (status.isDenied) {
      status = await Permission.sms.request();
    }
    return status.isGranted;
  }

  Future<List<SmsMessage>> getMessages() async {
    return await _query.querySms(
      kinds: [SmsQueryKind.inbox],
    );
  }

  // Filters for messages that look like financial transactions (debit, credit, spent, etc.)
  bool isFinancialSms(String body) {
    final lowerBody = body.toLowerCase();
    
    // OTPs should be excluded first for security
    if (lowerBody.contains('otp') || lowerBody.contains('verification code')) {
      return false;
    }

    // Key terms indicating a transaction.
    // We include currency symbols, abbreviations, and short forms used by Indian banks.
    final financialKeywords = [
      'spent', 'debited', 'credited', 'debit', 'credit', 'paid', 'txn',
      'purchase', 'vpa', 'upi', 'bank', 'amt', 'amount',
      'rs.', 'inr', 'rs ', '₹', r'\$', '€', 'withdrawn', 'deducted', 'avail bal',
      'refunded', 'reversed', 'collected', 'payment', 'bill', 'due', 'money transfer',
      // Short forms heavily used by HDFC, SBI, ICICI, Axis
      ' dr ', ' cr ', 'dr.', 'cr.', 'dr-', 'cr-',
      // Transfer/wallet keywords
      'transferred', 'received', 'imps', 'neft', 'rtgs', 'mandate',
      'a/c', 'acct', 'account', 'wallet', 'cashback',
    ];

    // We use a more relaxed regex that doesn't strictly require word boundaries 
    // for symbols like ₹ or $. 
    final pattern = RegExp(
      '(${financialKeywords.join('|')})',
      caseSensitive: false,
    );

    return pattern.hasMatch(lowerBody);
  }
}
