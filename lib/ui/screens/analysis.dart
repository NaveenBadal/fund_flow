import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../ff_format.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_charts.dart';
import '../widgets/ff_group.dart';
import '../widgets/ff_money.dart';
import '../widgets/ff_notice.dart';
import '../widgets/ff_screen.dart';
import '../widgets/ff_transaction_row.dart';

/// Where the month's money went.
///
/// Outgoing only, one currency, no projections. Every figure is a sum of rows
/// the person can open, which is what lets the page be read as fact rather
/// than as an estimate produced somewhere out of sight.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key, required this.period});
  final DateTime period;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  int? _scrubbed;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final c = context.ff;
    final period = widget.period;
    final days = DateUtils.getDaysInMonth(period.year, period.month);

    final month = app.transactions
        .where(
          (t) =>
              t.occurredAt.year == period.year &&
              t.occurredAt.month == period.month,
        )
        .toList();
    final currency = dominantCurrency(month, app.preferences.currency);
    final outgoing = month
        .where(
          (t) =>
              t.direction == TransactionDirection.outgoing &&
              t.currency == currency,
        )
        .toList();
    final total = outgoing.fold(0, (sum, t) => sum + t.amountMinor);
    final daily = dailyTotals(outgoing, currency, days);
    final hidden = app.preferences.hideAmounts;

    final categories = _rank(outgoing, (t) => t.category);
    final merchants = _rank(outgoing, (t) => readableMerchant(t.merchant));

    return FFScreen(
      title: 'Breakdown',
      large: false,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              FFSpace.sm,
              FFSpace.gutter,
              FFSpace.xl,
            ),
            child: Container(
              padding: const EdgeInsets.all(FFSpace.lg),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(FFRadius.group),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _scrubbed == null
                        ? '${DateFormat('MMMM yyyy').format(period)} · spent'
                        : DateFormat('EEEE d MMMM').format(
                            DateTime(period.year, period.month, _scrubbed! + 1),
                          ),
                    style: FFText.subhead.copyWith(color: c.secondaryLabel),
                  ),
                  const SizedBox(height: 4),
                  FFMoney(
                    minor: _scrubbed == null ? total : daily[_scrubbed!],
                    currency: currency,
                    hidden: hidden,
                    style: FFText.money,
                  ),
                  const SizedBox(height: FFSpace.lg),
                  FFBars(
                    values: daily,
                    selected: _scrubbed,
                    height: 150,
                    onSelected: (value) => setState(() => _scrubbed = value),
                  ),
                  const SizedBox(height: FFSpace.sm),
                  Text(
                    '${outgoing.length} outgoing transactions in $currency',
                    style: FFText.caption.copyWith(color: c.tertiaryLabel),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (outgoing.isEmpty)
          const SliverToBoxAdapter(
            child: FFEmpty(
              icon: Icons.donut_large_rounded,
              title: 'Nothing spent this month',
              message: 'There is nothing to break down yet.',
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: _Section(
              title: 'By category',
              rows: categories,
              total: total,
              currency: currency,
              hidden: hidden,
              coloured: true,
            ),
          ),
          SliverToBoxAdapter(
            child: _Section(
              title: 'Top merchants',
              rows: merchants.take(8).toList(),
              total: total,
              currency: currency,
              hidden: hidden,
              coloured: false,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                FFSpace.gutter + FFSpace.lg,
                0,
                FFSpace.gutter + FFSpace.lg,
                FFSpace.xl,
              ),
              child: Text(
                'Confirmed and unconfirmed outgoing records in $currency. '
                'Money in is excluded. Every figure is calculated on this '
                'device.',
                style: FFText.footnote.copyWith(color: c.secondaryLabel),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<(String, int)> _rank(
    List<MoneyTransaction> values,
    String Function(MoneyTransaction) key,
  ) {
    final totals = <String, int>{};
    for (final value in values) {
      totals[key(value)] = (totals[key(value)] ?? 0) + value.amountMinor;
    }
    return totals.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.rows,
    required this.total,
    required this.currency,
    required this.hidden,
    required this.coloured,
  });

  final String title;
  final List<(String, int)> rows;
  final int total;
  final String currency;
  final bool hidden;
  final bool coloured;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FFHeading(title),
      FFGroup(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.lg,
              FFSpace.sm,
              FFSpace.lg,
              FFSpace.sm,
            ),
            child: Column(
              children: [
                for (final row in rows)
                  FFProportion(
                    label: row.$1,
                    fraction: total == 0 ? 0 : row.$2 / total,
                    color: coloured ? FFCategory.color(row.$1) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FFMoney(
                          minor: row.$2,
                          currency: currency,
                          hidden: hidden,
                          style: FFText.callout.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: FFSpace.sm),
                        SizedBox(
                          width: 38,
                          child: Text(
                            total == 0
                                ? '—'
                                : '${(row.$2 / total * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: FFText.footnote.copyWith(
                              color: context.ff.tertiaryLabel,
                              fontFeatures: FFText.tabular,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}
