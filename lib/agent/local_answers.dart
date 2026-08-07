import '../domain/analytics.dart';
import '../domain/budget.dart';
import '../domain/category_catalog.dart';
import '../domain/insight_engine.dart';
import '../domain/money_format.dart';
import '../domain/transaction.dart';
import 'agent_presentation.dart';

/// An answer computed on the device, in the same shape a model answer takes.
class LocalAnswer {
  const LocalAnswer({required this.presentation, this.evidenceIds = const []});
  final AgentPresentation presentation;
  final List<int> evidenceIds;
}

/// Answers the questions that are arithmetic, without asking a model.
///
/// Most of what people ask a money agent — "how much on food this month", "how
/// does that compare with last month", "what needs review" — is a sum over rows
/// the device already holds. Sending those to a provider costs five to fifteen
/// seconds and real money to compute something SQLite does in microseconds, and
/// it means an install with no provider key can answer nothing at all.
///
/// Two rules keep this honest:
///
/// * It matches conservatively. Anything it is not confident about returns null
///   and goes to the model, which is strictly more capable. A wrong fast answer
///   is far worse than a slow right one.
/// * It never invents a subject. A category or merchant named in a question has
///   to actually exist in the ledger before this will answer about it.
///
/// The answers it returns are more trustworthy than the model's, not less: the
/// figures come from the same functions Home draws, so the two can never
/// disagree.
abstract final class LocalAnswers {
  static LocalAnswer? attempt({
    required String question,
    required List<MoneyTransaction> transactions,
    required List<CategoryBudget> budgets,
    required DateTime now,
    required String fallbackCurrency,
  }) {
    if (transactions.isEmpty) return null;
    final text = question.toLowerCase().trim();
    if (text.isEmpty) return null;

    final currency =
        Analytics.dominantCurrency(transactions) ?? fallbackCurrency;
    final period = _period(text, now);
    final context = _Context(
      transactions: transactions,
      budgets: budgets,
      currency: currency,
      period: period,
      now: now,
    );

    // Ordered by how specific the question is. "What needs review" must be
    // matched before the generic overview, or the overview swallows it.
    for (final matcher in <LocalAnswer? Function(String, _Context)>[
      _review,
      _duplicates,
      _recurring,
      _budgetStatus,
      _merchant,
      _category,
      _biggest,
      _breakdown,
      _comparison,
      _overview,
    ]) {
      final answer = matcher(text, context);
      if (answer != null) return answer;
    }
    return null;
  }

  // ---------------------------------------------------------------- matchers

  static LocalAnswer? _review(String text, _Context c) {
    if (!RegExp(
      r'\b(needs? review|to review|unreviewed|not sure about|low confidence|'
      r'unconfirmed)\b',
    ).hasMatch(text)) {
      return null;
    }
    final queue =
        c.transactions
            .where((item) => item.reviewState == ReviewState.needsReview)
            .toList()
          ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    if (queue.isEmpty) {
      return _answer([
        _part(AgentPartKind.conclusion, {
          'text':
              'Nothing is waiting for review — every transaction has either '
              'been read confidently or checked by you.',
        }),
      ]);
    }
    final total = queue
        .where((item) => item.currency == c.currency)
        .fold<int>(0, (sum, item) => sum + item.signedMinor.abs());
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text':
            '${queue.length} ${_plural(queue.length, 'transaction')} '
            '${queue.length == 1 ? 'is' : 'are'} waiting for you to check, '
            'worth ${formatMoney(total, c.currency)} in total. They are already '
            'counted in every figure.',
      }),
      _part(AgentPartKind.transactionList, {
        'transactionIds': [
          for (final item in queue.take(6))
            if (item.id != null) item.id!,
        ],
      }),
      _part(AgentPartKind.followUps, {
        'questions': ['Where did my money go this month?', 'How am I doing?'],
      }),
      _localNote('the review queue, oldest first'),
    ], evidence: queue);
  }

  static LocalAnswer? _duplicates(String text, _Context c) {
    if (!RegExp(
      r'\b(duplicate|charged twice|double charge|billed twice|same charge)\b',
    ).hasMatch(text)) {
      return null;
    }
    final findings = InsightEngine.duplicates(
      c.transactions
          .where(
            (item) => item.occurredAt.isAfter(
              c.now.subtract(const Duration(days: 90)),
            ),
          )
          .toList(),
    );
    if (findings.isEmpty) {
      return _answer([
        _part(AgentPartKind.conclusion, {
          'text':
              'Nothing in the last 90 days looks like a double charge — no two '
              'charges at one merchant share an amount within 48 hours.',
        }),
      ]);
    }
    final ids = <int>[];
    for (final finding in findings.take(4)) {
      if (finding.earlier.id != null) ids.add(finding.earlier.id!);
      if (finding.later.id != null) ids.add(finding.later.id!);
    }
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text':
            '${findings.length} possible ${_plural(findings.length, 'duplicate')} '
            'in the last 90 days. The clearest is ${findings.first.later.merchant} '
            'at ${formatMoney(findings.first.later.amountMinor, findings.first.later.currency)}, '
            'charged twice ${findings.first.apart.inHours < 24 ? 'within a day' : '${findings.first.apart.inDays} days apart'}.',
      }),
      _part(AgentPartKind.warning, {
        'text':
            'These are candidates, not proven duplicates — a renewal and a '
            'double charge look identical from the ledger alone.',
      }),
      _part(AgentPartKind.transactionList, {'transactionIds': ids}),
      _localNote('same merchant, amount and currency within 48 hours'),
    ]);
  }

  static LocalAnswer? _recurring(String text, _Context c) {
    if (!RegExp(
      r'\b(subscription|subscriptions|recurring|repeat charge|repeating|renew|'
      r'every month am i paying)\b',
    ).hasMatch(text)) {
      return null;
    }
    final charges = Analytics.recurring(
      transactions: c.transactions,
      now: c.now,
    );
    if (charges.isEmpty) {
      return _answer([
        _part(AgentPartKind.conclusion, {
          'text':
              'Nothing repeats often enough to call it a subscription yet. That '
              'needs three charges at one merchant, similar in size and about a '
              'month apart.',
        }),
      ]);
    }
    final monthly = charges
        .where((charge) => charge.currency == c.currency)
        .fold<int>(0, (sum, charge) => sum + charge.typicalMinor);
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text':
            '${charges.length} ${_plural(charges.length, 'merchant')} '
            '${charges.length == 1 ? 'charges' : 'charge'} you on a cycle, about '
            '${formatMoney(monthly, c.currency)} a month in total.',
      }),
      _part(AgentPartKind.breakdown, {
        'title': 'About every month',
        'rows': [
          for (final charge in charges.take(8))
            {
              'label': charge.merchant,
              'amountMinor': charge.typicalMinor,
              'currency': charge.currency,
            },
        ],
      }),
      _part(AgentPartKind.warning, {
        'text':
            'Worked out from repeat charges, not confirmed with the merchant. '
            'A monthly rent transfer looks the same from here.',
      }),
      _localNote('three or more similar charges 21–45 days apart'),
    ]);
  }

  static LocalAnswer? _budgetStatus(String text, _Context c) {
    if (!RegExp(
      r'\b(budget|budgets|limit|limits|on track|over ?spend|overspending)\b',
    ).hasMatch(text)) {
      return null;
    }
    if (c.budgets.isEmpty) {
      return _answer([
        _part(AgentPartKind.conclusion, {
          'text':
              'You have not set any monthly limits yet, so there is nothing to '
              'measure this month against.',
        }),
        _part(AgentPartKind.followUps, {
          'questions': [
            'Where did my money go this month?',
            'What do I spend most on?',
          ],
        }),
      ]);
    }
    final (monthFrom, monthTo) = Analytics.monthOf(c.now);
    final spent = {
      for (final row in Analytics.byCategory(
        transactions: c.transactions,
        from: monthFrom,
        to: monthTo,
        currency: c.currency,
      ))
        row.category.toLowerCase(): row.amountMinor,
    };
    final statuses = [
      for (final budget in c.budgets)
        BudgetStatus(
          budget: budget,
          spentMinor: spent[budget.category.toLowerCase()] ?? 0,
          transactionCount: 0,
        ),
    ]..sort((a, b) => b.fraction.compareTo(a.fraction));

    final over = statuses.where((status) => status.over).toList();
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text': over.isEmpty
            ? 'Every limit is still intact this month. ${statuses.first.category} '
                  'is the closest, at ${(statuses.first.fraction * 100).round()}% '
                  'of ${formatMoney(statuses.first.limitMinor, statuses.first.currency)}.'
            : '${over.length} ${_plural(over.length, 'limit')} '
                  '${over.length == 1 ? 'is' : 'are'} already past: '
                  '${over.map((status) => '${status.category} at ${(status.fraction * 100).round()}%').join(', ')}.',
      }),
      _part(AgentPartKind.breakdown, {
        'title': 'Spent against each limit',
        'rows': [
          for (final status in statuses)
            {
              'label': status.category,
              'amountMinor': status.spentMinor,
              'currency': status.currency,
            },
        ],
      }),
      _localNote('this calendar month against the limits you set'),
    ]);
  }

  static LocalAnswer? _merchant(String text, _Context c) {
    if (!RegExp(
      r'\b(how much|how many|what|total|spend|spent)\b',
    ).hasMatch(text)) {
      return null;
    }
    // The longest merchant name mentioned wins, so "book my show" does not
    // match a merchant called "Book".
    MoneyTransaction? best;
    var bestLength = 0;
    for (final item in c.transactions) {
      final name = item.merchant.trim().toLowerCase();
      if (name.length < 4 || name.length <= bestLength) continue;
      if (text.contains(name)) {
        best = item;
        bestLength = name.length;
      }
    }
    if (best == null) return null;

    final key = best.merchant.trim().toLowerCase();
    final matches =
        c.transactions
            .where(
              (item) =>
                  item.merchant.trim().toLowerCase() == key &&
                  item.currency == best!.currency &&
                  Analytics.inPeriod(item, c.period.from, c.period.to),
            )
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (matches.isEmpty) return null;

    final total = matches.fold<int>(0, (sum, item) => sum + item.amountMinor);
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text':
            'You spent ${formatMoney(total, best.currency)} at ${best.merchant} '
            '${c.period.label}, across ${matches.length} '
            '${_plural(matches.length, 'charge')}.',
      }),
      _part(AgentPartKind.metricRow, {
        'metrics': [
          {'label': 'Total', 'amountMinor': total, 'currency': best.currency},
          {
            'label': 'Typical',
            'amountMinor': total ~/ matches.length,
            'currency': best.currency,
          },
          {'label': 'Charges', 'value': '${matches.length}'},
        ],
      }),
      _part(AgentPartKind.transactionList, {
        'transactionIds': [
          for (final item in matches.take(6))
            if (item.id != null) item.id!,
        ],
      }),
      _localNote('${best.merchant}, ${c.period.label}'),
    ], evidence: matches);
  }

  static LocalAnswer? _category(String text, _Context c) {
    if (!RegExp(
      r'\b(how much|spend|spent|spending|total|cost|costs)\b',
    ).hasMatch(text)) {
      return null;
    }
    final known = {
      ...expenseCategories.map((value) => value.toLowerCase()),
      ...incomeCategories.map((value) => value.toLowerCase()),
    };
    String? found;
    for (final category in known) {
      if (RegExp('\\b$category\\b').hasMatch(text)) {
        found = category;
        break;
      }
    }
    if (found == null) return null;

    final incoming = incomeCategories
        .map((value) => value.toLowerCase())
        .contains(found);
    final direction = incoming
        ? TransactionDirection.incoming
        : TransactionDirection.outgoing;

    int totalFor(DateTime from, DateTime to) => c.transactions
        .where(
          (item) =>
              item.currency == c.currency &&
              item.direction == direction &&
              item.category.toLowerCase() == found &&
              Analytics.inPeriod(item, from, to),
        )
        .fold(0, (sum, item) => sum + item.amountMinor);

    final current = totalFor(c.period.from, c.period.to);
    final previous = totalFor(c.period.previousFrom, c.period.previousTo);
    // Nothing at all in that category is a real answer, but only if the
    // category is one the ledger actually uses — otherwise the model may know
    // something about the phrasing that this does not.
    final everUsed = c.transactions.any(
      (item) => item.category.toLowerCase() == found,
    );
    if (!everUsed) return null;

    final matches =
        c.transactions
            .where(
              (item) =>
                  item.category.toLowerCase() == found &&
                  item.currency == c.currency &&
                  Analytics.inPeriod(item, c.period.from, c.period.to),
            )
            .toList()
          ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));

    final label = found[0].toUpperCase() + found.substring(1);
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text': current == 0
            ? 'Nothing on $label ${c.period.label}.'
            : '$label came to ${formatMoney(current, c.currency)} '
                  '${c.period.label}, across ${matches.length} '
                  '${_plural(matches.length, 'transaction')}.',
      }),
      if (previous > 0)
        _part(AgentPartKind.comparison, {
          'title': '$label, ${c.period.label} vs ${c.period.previousLabel}',
          'currentLabel': c.period.label,
          'currentMinor': current,
          'previousLabel': c.period.previousLabel,
          'previousMinor': previous,
          'currency': c.currency,
          'detail': current >= previous
              ? '${formatMoney(current - previous, c.currency)} more than the '
                    'comparable stretch before it.'
              : '${formatMoney(previous - current, c.currency)} less than the '
                    'comparable stretch before it.',
        }),
      if (matches.isNotEmpty)
        _part(AgentPartKind.transactionList, {
          'transactionIds': [
            for (final item in matches.take(5))
              if (item.id != null) item.id!,
          ],
        }),
      _localNote('$label, ${c.period.label}, ${c.currency} only'),
    ], evidence: matches);
  }

  static LocalAnswer? _biggest(String text, _Context c) {
    if (!RegExp(
      r'\b(biggest|largest|most expensive|highest|priciest|worst)\b',
    ).hasMatch(text)) {
      return null;
    }
    final matches =
        c.transactions
            .where(
              (item) =>
                  item.currency == c.currency &&
                  item.direction == TransactionDirection.outgoing &&
                  Analytics.inPeriod(item, c.period.from, c.period.to),
            )
            .toList()
          ..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    if (matches.isEmpty) return null;
    final top = matches.first;
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text':
            'Your largest single charge ${c.period.label} was '
            '${formatMoney(top.amountMinor, top.currency)} at ${top.merchant}, '
            'on ${_day(top.occurredAt)}.',
      }),
      _part(AgentPartKind.transactionList, {
        'transactionIds': [
          for (final item in matches.take(5))
            if (item.id != null) item.id!,
        ],
      }),
      _localNote('largest outgoing charges, ${c.period.label}'),
    ], evidence: matches.take(5).toList());
  }

  static LocalAnswer? _breakdown(String text, _Context c) {
    if (!RegExp(
      r'\b(where.{0,20}(money|go|going|went|spend)|top categor|breakdown|'
      r'what do i spend|what did i spend|spend most|categories)\b',
    ).hasMatch(text)) {
      return null;
    }
    final rows = Analytics.byCategory(
      transactions: c.transactions,
      from: c.period.from,
      to: c.period.to,
      currency: c.currency,
    );
    if (rows.isEmpty) return null;
    final total = rows.fold<int>(0, (sum, row) => sum + row.amountMinor);
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text':
            'You spent ${formatMoney(total, c.currency)} ${c.period.label}, and '
            '${rows.first.category} took the most of it at '
            '${formatMoney(rows.first.amountMinor, c.currency)}.',
      }),
      _part(AgentPartKind.breakdown, {
        'title': 'By category, ${c.period.label}',
        'rows': [
          for (final row in rows.take(8))
            {
              'label': row.category,
              'amountMinor': row.amountMinor,
              'currency': c.currency,
            },
        ],
      }),
      _localNote('${c.period.label}, ${c.currency} only'),
    ]);
  }

  static LocalAnswer? _comparison(String text, _Context c) {
    if (!RegExp(
      r'\b(compare|comparison|vs\.?|versus|than last (month|week)|'
      r'more or less than)\b',
    ).hasMatch(text)) {
      return null;
    }
    final current = Analytics.overview(
      transactions: c.transactions,
      from: c.period.from,
      to: c.period.to,
      currency: c.currency,
    );
    final previous = Analytics.overview(
      transactions: c.transactions,
      from: c.period.previousFrom,
      to: c.period.previousTo,
      currency: c.currency,
    );
    if (current.empty && previous.empty) return null;
    final difference = current.outgoingMinor - previous.outgoingMinor;
    return _answer([
      _part(AgentPartKind.conclusion, {
        'text': previous.outgoingMinor == 0
            ? 'You spent ${formatMoney(current.outgoingMinor, c.currency)} '
                  '${c.period.label}. There is nothing in ${c.period.previousLabel} '
                  'to compare it with.'
            : 'You spent ${formatMoney(current.outgoingMinor, c.currency)} '
                  '${c.period.label} — '
                  '${formatMoney(difference.abs(), c.currency)} '
                  '${difference >= 0 ? 'more' : 'less'} than '
                  '${c.period.previousLabel}.',
      }),
      _part(AgentPartKind.comparison, {
        'title': 'Spending, ${c.period.label} vs ${c.period.previousLabel}',
        'currentLabel': c.period.label,
        'currentMinor': current.outgoingMinor,
        'previousLabel': c.period.previousLabel,
        'previousMinor': previous.outgoingMinor,
        'currency': c.currency,
      }),
      _localNote(
        'the same length of time in each period, so a part-finished month is '
        'not compared against a whole one',
      ),
    ]);
  }

  static LocalAnswer? _overview(String text, _Context c) {
    if (!RegExp(
      r'\b(how am i doing|how are my finances|overview|summary|summarise|'
      r'summarize|briefing|how much (did|have) i (spend|spent)|total spend|'
      r'my month|this month)\b',
    ).hasMatch(text)) {
      return null;
    }
    final overview = Analytics.overview(
      transactions: c.transactions,
      from: c.period.from,
      to: c.period.to,
      currency: c.currency,
    );
    if (overview.empty) return null;
    final previous = Analytics.overview(
      transactions: c.transactions,
      from: c.period.previousFrom,
      to: c.period.previousTo,
      currency: c.currency,
    );
    final rows = Analytics.byCategory(
      transactions: c.transactions,
      from: c.period.from,
      to: c.period.to,
      currency: c.currency,
    );
    final change = previous.outgoingMinor <= 0
        ? null
        : (overview.outgoingMinor - previous.outgoingMinor) /
              previous.outgoingMinor;
    final reviewCount = c.transactions
        .where((item) => item.reviewState == ReviewState.needsReview)
        .length;

    return _answer([
      _part(AgentPartKind.conclusion, {
        'text':
            '${c.period.label.substring(0, 1).toUpperCase()}${c.period.label.substring(1)} '
            'you took in ${formatMoney(overview.incomingMinor, c.currency)} and '
            'spent ${formatMoney(overview.outgoingMinor, c.currency)}, leaving '
            '${overview.netMinor >= 0 ? '' : 'you down '}'
            '${formatMoney(overview.netMinor.abs(), c.currency)}'
            '${overview.netMinor >= 0 ? ' in hand' : ''}.',
      }),
      _part(AgentPartKind.metricRow, {
        'metrics': [
          {
            'label': 'In',
            'amountMinor': overview.incomingMinor,
            'currency': c.currency,
          },
          {
            'label': 'Out',
            'amountMinor': overview.outgoingMinor,
            'currency': c.currency,
            'changeFraction': ?change,
          },
          {
            'label': 'Net',
            'amountMinor': overview.netMinor,
            'currency': c.currency,
          },
        ],
      }),
      if (rows.isNotEmpty)
        _part(AgentPartKind.breakdown, {
          'title': 'Where it went',
          'rows': [
            for (final row in rows.take(5))
              {
                'label': row.category,
                'amountMinor': row.amountMinor,
                'currency': c.currency,
              },
          ],
        }),
      if (reviewCount > 0)
        _part(AgentPartKind.insight, {
          'text':
              '$reviewCount ${_plural(reviewCount, 'transaction')} still '
              '${reviewCount == 1 ? 'needs' : 'need'} checking, and '
              '${reviewCount == 1 ? 'it is' : 'they are'} already counted above.',
        }),
      _part(AgentPartKind.followUps, {
        'questions': [
          'What was my biggest expense?',
          'What repeat charges do I have?',
        ],
      }),
      _localNote('${c.period.label}, ${c.currency} only'),
    ]);
  }

  // ----------------------------------------------------------------- helpers

  static LocalAnswer _answer(
    List<AgentPart?> parts, {
    List<MoneyTransaction> evidence = const [],
  }) => LocalAnswer(
    presentation: AgentPresentation(
      parts: AgentPresentation.ordered(parts.whereType<AgentPart>().toList()),
    ),
    evidenceIds: [
      for (final item in evidence)
        if (item.id != null) item.id!,
    ],
  );

  static AgentPart _part(AgentPartKind kind, Map<String, Object?> data) =>
      AgentPart(kind: kind, data: data);

  /// Every local answer says so.
  ///
  /// Someone should be able to tell why an answer came back instantly, and the
  /// fact that no model was involved is the strongest provenance this app can
  /// offer — not a caveat.
  static AgentPart _localNote(String detail) => AgentPart(
    kind: AgentPartKind.sourceNote,
    data: {
      'text': 'Worked out on this device from $detail. No model was involved.',
    },
  );

  static String _plural(int count, String word) =>
      count == 1 ? word : '${word}s';

  static String _day(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day} ${months[value.month - 1]}';
  }

  /// The period a question is about, and the comparable stretch before it.
  static _Period _period(String text, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    if (RegExp(r'\blast month\b').hasMatch(text)) {
      final from = DateTime(now.year, now.month - 1);
      return _Period(
        from: from,
        to: DateTime(now.year, now.month),
        label: 'last month',
        previousFrom: DateTime(now.year, now.month - 2),
        previousTo: from,
        previousLabel: 'the month before',
      );
    }
    if (RegExp(r'\b(last|past) (7|seven) days|\blast week\b').hasMatch(text)) {
      final from = today.subtract(const Duration(days: 7));
      return _Period(
        from: from,
        to: today.add(const Duration(days: 1)),
        label: 'in the last 7 days',
        previousFrom: from.subtract(const Duration(days: 7)),
        previousTo: from,
        previousLabel: 'the 7 days before',
      );
    }
    if (RegExp(r'\b(last|past) (30|thirty) days\b').hasMatch(text)) {
      final from = today.subtract(const Duration(days: 30));
      return _Period(
        from: from,
        to: today.add(const Duration(days: 1)),
        label: 'in the last 30 days',
        previousFrom: from.subtract(const Duration(days: 30)),
        previousTo: from,
        previousLabel: 'the 30 days before',
      );
    }
    if (RegExp(r'\b(last|past) (90|ninety) days|3 months\b').hasMatch(text)) {
      final from = today.subtract(const Duration(days: 90));
      return _Period(
        from: from,
        to: today.add(const Duration(days: 1)),
        label: 'in the last 90 days',
        previousFrom: from.subtract(const Duration(days: 90)),
        previousTo: from,
        previousLabel: 'the 90 days before',
      );
    }
    // Default: this month, measured against the same stretch of last month
    // rather than the whole of it.
    final from = DateTime(now.year, now.month);
    final elapsed = now.difference(from);
    final previousFrom = DateTime(now.year, now.month - 1);
    return _Period(
      from: from,
      to: DateTime(now.year, now.month + 1),
      label: 'this month',
      previousFrom: previousFrom,
      previousTo: previousFrom.add(elapsed),
      previousLabel: 'the same stretch of last month',
    );
  }
}

class _Period {
  const _Period({
    required this.from,
    required this.to,
    required this.label,
    required this.previousFrom,
    required this.previousTo,
    required this.previousLabel,
  });

  final DateTime from;
  final DateTime to;
  final String label;
  final DateTime previousFrom;
  final DateTime previousTo;
  final String previousLabel;
}

class _Context {
  const _Context({
    required this.transactions,
    required this.budgets,
    required this.currency,
    required this.period,
    required this.now,
  });

  final List<MoneyTransaction> transactions;
  final List<CategoryBudget> budgets;
  final String currency;
  final _Period period;
  final DateTime now;
}
