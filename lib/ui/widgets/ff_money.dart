import 'package:flutter/material.dart';

import '../../domain/money_format.dart';
import '../theme/ff_theme.dart';

/// A figure.
///
/// Always tabular, so a column of amounts lines up on the decimal instead of
/// shimmering as digits change width. Shrinks to fit rather than wrapping,
/// because a wrapped amount stops being one number.
class FFMoney extends StatelessWidget {
  const FFMoney({
    super.key,
    required this.minor,
    required this.currency,
    this.hidden = false,
    this.style,
    this.color,
    this.signed = false,
    this.align = TextAlign.start,
  });

  final int minor;
  final String currency;
  final bool hidden;
  final TextStyle? style;
  final Color? color;

  /// Prefix an explicit + or −, for a ledger line where direction matters.
  final bool signed;

  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final base = (style ?? FFText.body).copyWith(
      color: color ?? context.ff.label,
      fontFeatures: FFText.tabular,
    );
    if (hidden) {
      return Semantics(
        label: 'Amount hidden',
        excludeSemantics: true,
        child: Text('••••', style: base, textAlign: align),
      );
    }
    final amount = formatMoney(minor.abs(), currency);
    final text = signed ? '${minor < 0 ? '−' : '+'}$amount' : amount;
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align == TextAlign.end
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(text, maxLines: 1, style: base, textAlign: align),
      ),
    );
  }
}

/// The one big number a screen is about, with its caption above it.
class FFHeroAmount extends StatelessWidget {
  const FFHeroAmount({
    super.key,
    required this.caption,
    required this.minor,
    required this.currency,
    this.hidden = false,
    this.footnote,
    this.footnoteColor,
    this.large = false,
  });

  final String caption;
  final int minor;
  final String currency;
  final bool hidden;
  final String? footnote;
  final Color? footnoteColor;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: FFText.subhead.copyWith(color: c.secondaryLabel),
        ),
        const SizedBox(height: 6),
        FFMoney(
          minor: minor,
          currency: currency,
          hidden: hidden,
          style: large ? FFText.moneyLarge : FFText.money,
        ),
        if (footnote != null) ...[
          const SizedBox(height: FFSpace.sm),
          Text(
            footnote!,
            style: FFText.subhead.copyWith(
              color: footnoteColor ?? c.secondaryLabel,
            ),
          ),
        ],
      ],
    );
  }
}
