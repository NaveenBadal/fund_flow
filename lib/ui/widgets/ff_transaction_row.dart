import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/transaction.dart';
import '../ff_format.dart';
import '../theme/ff_theme.dart';
import 'ff_money.dart';
import 'ff_pressable.dart';

/// Category identity.
///
/// One glyph and one colour per category, so a list of thirty rows can be
/// skimmed by shape before a single word is read. The colours come from the
/// system palette rather than a bespoke set — they are already tuned to sit
/// beside each other without any one of them shouting.
abstract final class FFCategory {
  static const _map = <String, (IconData, Color)>{
    'Food': (Icons.restaurant_rounded, Color(0xffff9500)),
    'Groceries': (Icons.local_grocery_store_rounded, Color(0xff34c759)),
    'Transport': (Icons.directions_car_filled_rounded, Color(0xff007aff)),
    'Shopping': (Icons.shopping_bag_rounded, Color(0xffaf52de)),
    'Bills': (Icons.receipt_long_rounded, Color(0xff5856d6)),
    'Health': (Icons.favorite_rounded, Color(0xffff2d55)),
    'Entertainment': (Icons.movie_rounded, Color(0xffff375f)),
    'Subscriptions': (Icons.autorenew_rounded, Color(0xff5ac8fa)),
    'Transfer': (Icons.swap_horiz_rounded, Color(0xff8e8e93)),
    // Not in the catalogue, but a model reading real messages produces these
    // constantly. Falling through to a grey ellipsis makes the app look like
    // it did not understand a transaction it understood perfectly well.
    'Insurance': (Icons.shield_rounded, Color(0xff5856d6)),
    'Rent': (Icons.home_rounded, Color(0xffa2845e)),
    'Fuel': (Icons.local_gas_station_rounded, Color(0xffff9500)),
    'Travel': (Icons.flight_rounded, Color(0xff32ade6)),
    'Education': (Icons.school_rounded, Color(0xff5856d6)),
    'Investment': (Icons.show_chart_rounded, Color(0xff34c759)),
    'Fees': (Icons.request_quote_rounded, Color(0xff8e8e93)),
    'Cash': (Icons.payments_rounded, Color(0xff8e8e93)),
    'Income': (Icons.south_west_rounded, Color(0xff34c759)),
    'Salary': (Icons.account_balance_rounded, Color(0xff34c759)),
    'Refund': (Icons.undo_rounded, Color(0xff30b0c7)),
    'Cashback': (Icons.savings_rounded, Color(0xff34c759)),
    'Interest': (Icons.percent_rounded, Color(0xff32ade6)),
    'Business': (Icons.work_rounded, Color(0xff6d6d72)),
    'Other': (Icons.more_horiz_rounded, Color(0xff8e8e93)),
  };

  static IconData icon(String category) =>
      _map[category]?.$1 ?? Icons.more_horiz_rounded;

  static Color color(String category) =>
      _map[category]?.$2 ?? const Color(0xff8e8e93);
}

class FFCategoryGlyph extends StatelessWidget {
  const FFCategoryGlyph({super.key, required this.category, this.size = 36});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: FFCategory.color(category),
      shape: BoxShape.circle,
    ),
    child: Icon(
      FFCategory.icon(category),
      size: size * .5,
      color: Colors.white,
    ),
  );
}

/// One line of the ledger.
///
/// Merchant first because that is what is remembered; the amount right-aligned
/// and tabular because the column is scanned vertically, not read.
class FFTransactionRow extends StatelessWidget {
  const FFTransactionRow({
    super.key,
    required this.item,
    required this.hidden,
    this.onTap,
    this.showDay = false,
  });

  final MoneyTransaction item;
  final bool hidden;
  final VoidCallback? onTap;

  /// Show the date instead of the time, for lists that are not day-grouped.
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final incoming = item.direction == TransactionDirection.incoming;
    final review = item.reviewState == ReviewState.needsReview;

    return FFPressable(
      onTap: onTap,
      highlight: true,
      button: onTap != null,
      semanticLabel:
          '${readableMerchant(item.merchant)}, ${item.category}, '
          '${incoming ? 'received' : 'spent'}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(
          horizontal: FFSpace.lg,
          vertical: 10,
        ),
        child: Row(
          children: [
            FFCategoryGlyph(category: item.category),
            const SizedBox(width: FFSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    readableMerchant(item.merchant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FFText.body,
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (review) ...[
                        Icon(
                          Icons.error_rounded,
                          size: 13,
                          color: c.orange,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          review
                              ? 'Needs a look'
                              : showDay
                              ? '${item.category} · ${DateFormat('d MMM').format(item.occurredAt)}'
                              : '${item.category} · ${DateFormat.jm().format(item.occurredAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FFText.footnote.copyWith(
                            color: review ? c.orange : c.secondaryLabel,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: FFSpace.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: FFMoney(
                minor: incoming ? item.amountMinor : -item.amountMinor,
                currency: item.currency,
                hidden: hidden,
                signed: true,
                align: TextAlign.end,
                color: incoming ? c.green : c.label,
                style: FFText.body.copyWith(
                  fontWeight: incoming ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
