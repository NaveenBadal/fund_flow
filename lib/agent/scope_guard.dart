/// Refuses obviously out-of-scope questions before a single token is spent.
///
/// The system contract already tells the agent it only works on this person's
/// money, and a prose reply gets one repair turn. Both of those run *after* the
/// question has been sent to a provider and paid for, and both are
/// probabilistic — a contract is an instruction a model may or may not follow.
///
/// This is the deterministic half. It fires only on unambiguous signals, and
/// anything it is not sure about falls through to the model, where the contract
/// still applies. A guard that guesses would be worse than no guard: refusing
/// "how much did I invest in my PPF this month" is a bug, and it is a question
/// about their own ledger.
abstract final class ScopeGuard {
  /// Why this question is out of scope, or null to let it through.
  static String? refuse(String question) {
    final text = question.toLowerCase().trim();
    if (text.isEmpty) return null;

    for (final rule in _rules) {
      if (!rule.pattern.hasMatch(text)) continue;
      // A ledger question that happens to contain a trigger word stays a ledger
      // question: "how much do I spend on my Python course" is about spending.
      if (rule.yieldsToLedger && _looksLikeALedgerQuestion(text)) continue;
      return rule.reason;
    }
    return null;
  }

  /// Signals that a question is about this person's own recorded money.
  static bool _looksLikeALedgerQuestion(String text) =>
      _ledgerSignals.hasMatch(text);

  static final _ledgerSignals = RegExp(
    r'\b(i\s+(spend|spent|paid|pay|earn|earned|save|saved)|my\s+(spend|spending|'
    r'transactions?|ledger|budget|limit|account|salary|income|money|expenses?|'
    r'subscription|course|class|membership|plan|fees?)|'
    r'how much (did|do|have) i|this month|last month|my statement)\b',
  );

  static final _rules = <_Rule>[
    _Rule(
      // Writing or explaining software, asked for as such. The user's own
      // report of the old behaviour was that asking for a Python program
      // worked.
      //
      // `app` is deliberately absent from these nouns: how this app works is
      // in scope, and the old list refused "explain how the app works" as a
      // request to explain code. `class` and `query` are absent for the same
      // reason — a yoga class is a category of spending.
      pattern: RegExp(
        r'\b(write|generate|debug|refactor|implement)\b[^.?!]{0,40}'
        r'\b(code|program|script|function|regex|api|algorithm)\b'
        r'|\b(explain|fix)\b[^.?!]{0,40}\b(code|regex|algorithm|this (function|'
        r'script|error)|stack trace)\b'
        r'|\b(leetcode|stack trace|compiler|null pointer)\b',
      ),
      reason: 'I only work on your money — I do not write or explain code.',
      yieldsToLedger: false,
    ),
    _Rule(
      // A programming language named on its own is almost always a coding
      // request — but not when it is the subject of a purchase. "How much did
      // I spend on my Python course" is a ledger question, and refusing it was
      // the guard contradicting its own contract.
      pattern: RegExp(
        r'\b(python|javascript|typescript|dart|kotlin|swift|golang|rust|c\+\+|'
        r'sql|html|css|bash|shell script)\b',
      ),
      reason: 'I only work on your money — I do not write or explain code.',
      yieldsToLedger: true,
    ),
    _Rule(
      // Investment and product advice. Describing their own figures is fine;
      // recommending what to buy is not, however the question is phrased.
      pattern: RegExp(
        r'\b(should i|shall i|is it (a )?good|worth|recommend|advice on|which)\b'
        r'[^.?!]{0,50}\b(invest|invests|investing|investment|stock|stocks|share|'
        r'shares|equity|crypto|bitcoin|ethereum|mutual fund|sip|ipo|nifty|'
        r'sensex|gold|fd|fixed deposit|insurance policy|loan|credit card)\b'
        r'|\b(stock|share) price\b|\bmarket (outlook|forecast|prediction)\b',
      ),
      reason:
          'I can tell you what your money has done, but I do not give '
          'investment or product advice.',
      yieldsToLedger: false,
    ),
    _Rule(
      // General knowledge, translation, creative writing, chit-chat.
      pattern: RegExp(
        r'\b(who (is|was|are)|what is the capital|when did|where is)\b'
        r'|\b(translate|summari[sz]e this|write (me )?(a|an) (essay|poem|story|'
        r'song|joke|email|letter)|tell me a joke|recipe for|weather (in|today|'
        r'tomorrow)|news about|meaning of life)\b',
      ),
      reason: 'I only work on your money — that is outside what I do.',
      yieldsToLedger: true,
    ),
    _Rule(
      // Finance as a school subject. Settled deliberately: the boundary between
      // "what is an emergency fund" and "should I start one" cannot be held.
      pattern: RegExp(
        r'\bwhat (is|are) (an?|the) (emergency fund|mutual fund|index fund|'
        r'credit score|inflation|compound interest|apr|nav|sip|elss|ppf|nps)\b'
        r'|\bhow (do|does) (inflation|compound interest|tax|gst|tds|the stock '
        r'market) work\b|\bexplain (inflation|compound interest|mutual funds?|'
        r'the stock market)\b',
      ),
      reason:
          'I explain your money rather than finance in general, so that one '
          'is outside what I do.',
      yieldsToLedger: true,
    ),
  ];
}

class _Rule {
  const _Rule({
    required this.pattern,
    required this.reason,
    required this.yieldsToLedger,
  });

  final RegExp pattern;
  final String reason;

  /// Whether a ledger-shaped question overrides this rule. False for code and
  /// investment advice, which stay refused however they are framed.
  final bool yieldsToLedger;
}
