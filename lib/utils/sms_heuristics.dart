/// Pure-Dart, zero-dependency fallbacks for SMS parsing.
///
/// Cheap regex/keyword heuristics used when the cloud model omits a field
/// (e.g. returns a merchant but no amount/category). No ML, no memory cost.
class SmsHeuristics {
  const SmsHeuristics._();

  static final _amountPatterns = [
    RegExp(r'(?:rs\.?|inr|₹)\s*([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
    RegExp(r'([0-9,]+(?:\.[0-9]{1,2})?)\s*(?:rs\.?|inr)', caseSensitive: false),
    RegExp(r'(?:amount|amt)\D{0,10}([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
    RegExp(r'(?:debited|credited|paid|charged|spent)\D{0,15}([0-9,]+(?:\.[0-9]{1,2})?)', caseSensitive: false),
  ];

  static double? extractAmount(String sms) {
    for (final pattern in _amountPatterns) {
      final m = pattern.firstMatch(sms);
      if (m != null) {
        final str = m.group(1)!.replaceAll(',', '');
        final val = double.tryParse(str);
        if (val != null && val > 0) return val;
      }
    }
    return null;
  }

  static String inferCategory(String merchant) {
    final m = merchant.toLowerCase();
    if (['swiggy', 'zomato', 'food', 'restaurant', 'cafe', 'hotel', 'biryani', 'pizza'].any(m.contains)) return 'Food';
    if (['uber', 'ola', 'rapido', 'railway', 'irctc', 'metro', 'flight', 'indigo', 'spicejet'].any(m.contains)) return 'Transport';
    if (['electricity', 'water', 'jio', 'airtel', 'bsnl', 'internet', 'broadband', 'recharge'].any(m.contains)) return 'Utilities';
    if (['netflix', 'hotstar', 'spotify', 'prime', 'zee5', 'cinema', 'pvr', 'inox', 'bookmyshow'].any(m.contains)) return 'Entertainment';
    if (['amazon', 'flipkart', 'myntra', 'meesho', 'nykaa', 'shop', 'mart', 'store', 'ajio'].any(m.contains)) return 'Shopping';
    if (['hospital', 'clinic', 'pharmacy', 'medical', 'doctor', 'apollo', 'medplus', '1mg', 'netmeds'].any(m.contains)) return 'Health';
    return 'Others';
  }
}
