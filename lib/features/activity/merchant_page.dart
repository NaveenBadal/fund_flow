import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/transaction.dart';
import '../common/formatting.dart';
import '../shell/shell.dart';
import 'transaction_page.dart';
import 'transaction_row.dart';

/// Everything one merchant has ever taken.
///
/// Reachable from any row, and worth its own page because "how much do I
/// actually spend at this place" is a question the ledger can answer exactly and
/// a person cannot answer at all by scrolling.
class MerchantPage extends ConsumerWidget {
  const MerchantPage({super.key, required this.merchant});
  final String merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final money = ref.watch(moneyProvider);
    final key = merchant.trim().toLowerCase();

    final items =
        (app?.transactions ?? const <MoneyTransaction>[])
            .where((item) => item.merchant.trim().toLowerCase() == key)
            .toList()
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    if (items.isEmpty) {
      return FluxDetailPage(
        title: merchant,
        slivers: const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: FluxEmpty(
              icon: Icons.storefront_outlined,
              title: 'Nothing here any more',
              message: 'Every transaction for this merchant has been removed.',
            ),
          ),
        ],
      );
    }

    // One currency: the dominant one. Totalling across currencies would be
    // arithmetic on incomparable numbers.
    final counts = <String, int>{};
    for (final item in items) {
      counts[item.currency] = (counts[item.currency] ?? 0) + 1;
    }
    final currency =
        (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final sameCurrency = items
        .where((item) => item.currency == currency)
        .toList();
    final spent = sameCurrency
        .where((item) => item.direction == TransactionDirection.outgoing)
        .fold<int>(0, (sum, item) => sum + item.amountMinor);
    final average = sameCurrency.isEmpty ? 0 : spent ~/ sameCurrency.length;

    // Oldest first for the trend: a sparkline read right-to-left is a lie.
    final series = [
      for (final item in sameCurrency.reversed) item.amountMinor.toDouble(),
    ];

    final cadence = _cadence(sameCurrency);

    return FluxDetailPage(
      title: merchant,
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: FluxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL SPENT',
                  style: FluxType.overline.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: FluxSpace.x2),
                MoneyText(money(spent, currency), style: FluxType.moneyLarge),
                const SizedBox(height: FluxSpace.x4),
                if (series.length > 2) ...[
                  FluxSparkline(
                    values: series,
                    color: palette.forCategory(items.first.category),
                    height: 40,
                  ),
                  const SizedBox(height: FluxSpace.x4),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Charges',
                        value: '${sameCurrency.length}',
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        label: 'Typical',
                        value: money(average, currency),
                      ),
                    ),
                    Expanded(
                      child: _Stat(label: 'Cadence', value: cadence),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: FluxChip(
            label: 'Ask about $merchant',
            icon: Icons.auto_awesome_rounded,
            onTap: () => openAsk(
              context,
              ref,
              seed: 'How much do I spend at $merchant, and how often?',
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: FluxSectionHeader(title: 'Every charge'),
        ),
        SliverList.separated(
          itemCount: items.length,
          separatorBuilder: (context, index) =>
              const FluxLine(indent: FluxSpace.x16),
          itemBuilder: (context, index) => TransactionRow(
            transaction: items[index],
            money: money,
            showDate: true,
            onTap: items[index].id == null
                ? null
                : () => fluxPush(
                    context,
                    (context) => TransactionPage(id: items[index].id!),
                  ),
          ),
        ),
      ],
    );
  }

  /// "About monthly", "About weekly", "Irregular".
  ///
  /// Named rather than numeric: "every 29.4 days" is precision the data does
  /// not have, since a billing date moves around weekends.
  static String _cadence(List<MoneyTransaction> items) {
    if (items.length < 3) return 'Too few';
    final sorted = [...items]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final gaps = <int>[];
    for (var index = 1; index < sorted.length; index++) {
      gaps.add(
        sorted[index].occurredAt
            .difference(sorted[index - 1].occurredAt)
            .inDays,
      );
    }
    final average = gaps.reduce((a, b) => a + b) / gaps.length;
    if (average <= 2) return 'Most days';
    if (average <= 10) return 'Weekly-ish';
    if (average <= 45) return 'Monthly-ish';
    if (average <= 120) return 'Quarterly';
    return 'Irregular';
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FluxType.caption.copyWith(color: palette.textMuted)),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FluxType.moneySmall.copyWith(
            color: palette.text,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
