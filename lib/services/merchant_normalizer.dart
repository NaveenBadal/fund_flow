/// Pure-Dart merchant name normalizer.
/// Cleans raw SMS merchant strings into canonical display names.
class MerchantNormalizer {
  static final _rules = <(RegExp, String)>[
    // Food delivery
    (RegExp(r'SWIGGY', caseSensitive: false), 'Swiggy'),
    (RegExp(r'ZOMATO|BUNDL\s*TECH', caseSensitive: false), 'Zomato'),
    (RegExp(r'BLINKIT|GROFERS', caseSensitive: false), 'Blinkit'),
    (RegExp(r'DUNZO', caseSensitive: false), 'Dunzo'),
    (RegExp(r'BIGBASKET', caseSensitive: false), 'BigBasket'),
    (RegExp(r'ZEPTO', caseSensitive: false), 'Zepto'),
    // Ride sharing
    (RegExp(r'\bOLA\b', caseSensitive: false), 'Ola'),
    (RegExp(r'\bUBER\b', caseSensitive: false), 'Uber'),
    (RegExp(r'RAPIDO', caseSensitive: false), 'Rapido'),
    // Streaming
    (RegExp(r'NETFLIX', caseSensitive: false), 'Netflix'),
    (RegExp(r'SPOTIFY', caseSensitive: false), 'Spotify'),
    (RegExp(r'PRIME\s*VIDEO|AMAZON\s*PRIME', caseSensitive: false), 'Amazon Prime'),
    (RegExp(r'HOTSTAR|DISNEY', caseSensitive: false), 'Disney+ Hotstar'),
    (RegExp(r'YOUTUBE\s*PREMIUM', caseSensitive: false), 'YouTube Premium'),
    (RegExp(r'SONYLIV', caseSensitive: false), 'SonyLIV'),
    (RegExp(r'ZEE5', caseSensitive: false), 'ZEE5'),
    // E-commerce
    (RegExp(r'\bAMAZON\b', caseSensitive: false), 'Amazon'),
    (RegExp(r'\bFLIPKART\b', caseSensitive: false), 'Flipkart'),
    (RegExp(r'\bMEESHO\b', caseSensitive: false), 'Meesho'),
    (RegExp(r'\bMYNTRA\b', caseSensitive: false), 'Myntra'),
    (RegExp(r'NYKAA', caseSensitive: false), 'Nykaa'),
    (RegExp(r'AJIO', caseSensitive: false), 'AJIO'),
    // Payments/wallets
    (RegExp(r'PHONEPE|PHONE\s*PE', caseSensitive: false), 'PhonePe'),
    (RegExp(r'PAYTM', caseSensitive: false), 'Paytm'),
    (RegExp(r'GPAY|GOOGLE\s*PAY', caseSensitive: false), 'Google Pay'),
    (RegExp(r'\bCRED\b', caseSensitive: false), 'CRED'),
    // Banks / finance
    (RegExp(r'HDFC\s*BANK', caseSensitive: false), 'HDFC Bank'),
    (RegExp(r'ICICI\s*BANK', caseSensitive: false), 'ICICI Bank'),
    (RegExp(r'AXIS\s*BANK', caseSensitive: false), 'Axis Bank'),
    (RegExp(r'\bSBI\b', caseSensitive: false), 'SBI'),
    (RegExp(r'KOTAK', caseSensitive: false), 'Kotak'),
    // Fuel
    (RegExp(r'\bHPCL\b', caseSensitive: false), 'HPCL'),
    (RegExp(r'\bIOCL?\b', caseSensitive: false), 'IOC'),
    (RegExp(r'\bBPCL\b', caseSensitive: false), 'BPCL'),
    // Telecom
    (RegExp(r'\bAIRTEL\b', caseSensitive: false), 'Airtel'),
    (RegExp(r'\bJIO\b', caseSensitive: false), 'Jio'),
    (RegExp(r'\bVODAFONE\b|\bVI\b', caseSensitive: false), 'Vi'),
    (RegExp(r'\bBSNL\b', caseSensitive: false), 'BSNL'),
    // Food chains
    (RegExp(r"MCDONALD'?S?|MCF|MCDEE", caseSensitive: false), "McDonald's"),
    (RegExp(r'\bKFC\b', caseSensitive: false), 'KFC'),
    (RegExp(r'\bDOMINO', caseSensitive: false), "Domino's"),
    (RegExp(r'PIZZA\s*HUT', caseSensitive: false), 'Pizza Hut'),
    (RegExp(r'\bSTARBUCKS\b', caseSensitive: false), 'Starbucks'),
    (RegExp(r'CAFE\s*COFFEE\s*DAY|CCD', caseSensitive: false), 'CCD'),
    (RegExp(r'HALDIRAMS?', caseSensitive: false), "Haldiram's"),
    // Grocery
    (RegExp(r'\bDMART\b|D-MART', caseSensitive: false), 'DMart'),
    (RegExp(r'\bRELIANCE\s*FRESH\b', caseSensitive: false), 'Reliance Fresh'),
    (RegExp(r'\bSPENCERS?\b', caseSensitive: false), "Spencer's"),
    // Health
    (RegExp(r'APOLLO\s*PHARMA|APOLLOPHARMACY', caseSensitive: false), 'Apollo Pharmacy'),
    (RegExp(r'NETMEDS', caseSensitive: false), 'Netmeds'),
    (RegExp(r'PHARMEASY', caseSensitive: false), 'PharmEasy'),
    (RegExp(r'1MG|TATA\s*1MG', caseSensitive: false), 'Tata 1mg'),
  ];

  /// Normalize a raw merchant string to a canonical display name.
  static String normalize(String raw) {
    if (raw.trim().isEmpty) return raw;

    for (final (pattern, canonical) in _rules) {
      if (pattern.hasMatch(raw)) return canonical;
    }

    // Generic cleanup: strip transaction IDs, order numbers, and noise
    var cleaned = raw
        .replaceAll(RegExp(r'\*[A-Z0-9\-]+'), '') // *ORD-12345
        .replaceAll(RegExp(r'#[A-Z0-9\-]+'), '') // #TXN123
        .replaceAll(RegExp(r'\b[0-9]{6,}\b'), '') // long numbers
        .replaceAll(RegExp(r'(PVT\.?\s*LTD\.?|LIMITED|LTD\.?|INC\.?|CORP\.?)', caseSensitive: false), '')
        .replaceAll(RegExp(r'(TECHNOLOGIES?|INTERNET|DIGITAL|PAYMENTS?|SOLUTIONS?)', caseSensitive: false), '')
        .replaceAll(RegExp(r'[_\-]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    if (cleaned.isEmpty) return raw.trim();

    // Title-case the result
    return cleaned
        .split(' ')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }
}
