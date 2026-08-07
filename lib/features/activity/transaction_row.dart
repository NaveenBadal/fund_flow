import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../design/flux.dart';
import '../../domain/transaction.dart';
import '../common/formatting.dart';

/// One transaction in the ledger.
///
/// The needs-review state is a 2px amber edge down the left rather than a badge:
/// a badge competes with the amount for the right-hand side, and the edge scans
/// as a column when several rows need attention.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    super.key,
    required this.transaction,
    required this.money,
    this.onTap,
    this.onLongPress,
    this.selected,
    this.showDate = false,
  });

  final MoneyTransaction transaction;
  final MoneyFormatter money;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Non-null puts the row in multi-select mode.
  final bool? selected;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final incoming = transaction.direction == TransactionDirection.incoming;
    final needsReview = transaction.reviewState == ReviewState.needsReview;
    final tint = palette.forCategory(transaction.category);

    return FluxPressable(
      onTap: onTap,
      onLongPress: onLongPress,
      feedback: PressFeedback.wash,
      haptic: false,
      child: Row(
        children: [
          SizedBox(
            width: 3,
            height: 62,
            child: needsReview
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.attention,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(2),
                      ),
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                FluxSpace.page - 3,
                FluxSpace.x3,
                FluxSpace.page,
                FluxSpace.x3,
              ),
              child: Row(
                children: [
                  if (selected != null) ...[
                    Icon(
                      selected!
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 22,
                      color: selected! ? palette.iris : palette.textFaint,
                    ),
                    const SizedBox(width: FluxSpace.x3),
                  ] else ...[
                    FluxAvatar(
                      name: transaction.merchant,
                      tint: incoming ? palette.income : tint,
                      icon: incoming ? Icons.south_west_rounded : null,
                    ),
                    const SizedBox(width: FluxSpace.x3),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          transaction.merchant,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluxType.bodyLarge.copyWith(
                            color: palette.text,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: ShapeDecoration(
                                color: tint,
                                shape: const CircleBorder(),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                [
                                  transaction.category,
                                  if (showDate)
                                    shortDay(transaction.occurredAt),
                                  timeLabel(transaction.occurredAt),
                                  if (transaction.account != null)
                                    transaction.account!,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FluxType.caption.copyWith(
                                  color: palette.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: FluxSpace.x2),
                  MoneyText(
                    money(transaction.amountMinor, transaction.currency),
                    incoming: incoming,
                    signed: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The day header, carrying that day's net.
class DayHeader extends StatelessWidget {
  const DayHeader({
    super.key,
    required this.label,
    required this.netLabel,
    required this.positive,
  });

  final String label;
  final String netLabel;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Container(
      color: palette.background,
      padding: const EdgeInsets.only(
        left: FluxSpace.page,
        right: FluxSpace.page,
        top: FluxSpace.x5,
        bottom: FluxSpace.x2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: FluxType.overline.copyWith(color: palette.textMuted),
            ),
          ),
          Text(
            netLabel,
            style: FluxType.moneySmall.copyWith(
              color: positive ? palette.income : palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
