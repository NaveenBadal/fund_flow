import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// A signed change against a previous period.
///
/// Direction is carried by an arrow as well as by colour, so it survives
/// colour-blindness and a greyscale screenshot.
///
/// [higherIsWorse] is the whole subtlety: spending more is worse, earning more
/// is better, and the same +12% therefore has to be able to mean either. A
/// badge that always paints "up" green would congratulate someone for
/// overspending.
class FluxDelta extends StatelessWidget {
  const FluxDelta({
    super.key,
    required this.fraction,
    this.higherIsWorse = true,
    this.suffix,
    this.compact = false,
  });

  final double fraction;
  final bool higherIsWorse;
  final String? suffix;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final up = fraction > 0;
    // Under 1% is noise on a month of spending; presenting it as a change
    // trains people to ignore the badge.
    final flat = fraction.abs() < 0.01;
    final bad = higherIsWorse ? up : !up;
    final color = flat
        ? palette.textMuted
        : (bad ? palette.attention : palette.income);
    final percent = '${(fraction.abs() * 100).round()}%';

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: flat ? palette.surfaceHighest : color.withValues(alpha: 0.14),
        shape: const StadiumBorder(),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : FluxSpace.x2,
          vertical: compact ? 2 : 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              flat
                  ? Icons.remove_rounded
                  : (up
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded),
              size: compact ? 11 : 13,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              flat ? 'flat' : percent,
              style: FluxType.caption.copyWith(
                color: color,
                fontSize: compact ? 10 : 12,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (suffix != null && !compact) ...[
              const SizedBox(width: 3),
              Text(
                suffix!,
                style: FluxType.caption.copyWith(color: color, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Two periods side by side.
///
/// One shared scale, one measure, no second axis: the comparison is only
/// meaningful if both bars are measured the same way, and a dual axis is the
/// fastest way to make two numbers look like whatever you want.
class FluxComparison extends StatelessWidget {
  const FluxComparison({
    super.key,
    required this.currentLabel,
    required this.currentValue,
    required this.currentDisplay,
    required this.previousLabel,
    required this.previousValue,
    required this.previousDisplay,
    this.color,
  });

  final String currentLabel;
  final double currentValue;
  final String currentDisplay;
  final String previousLabel;
  final double previousValue;
  final String previousDisplay;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final accent = color ?? palette.iris;
    final highest = [
      currentValue,
      previousValue,
    ].reduce((a, b) => a > b ? a : b);

    Widget row(String label, double value, String display, bool current) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: FluxSpace.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: FluxType.caption.copyWith(
                        color: current ? palette.text : palette.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    display,
                    style: FluxType.moneySmall.copyWith(
                      color: current ? palette.text : palette.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluxSpace.x1 + 2),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ColoredBox(color: palette.surfaceHighest),
                      ),
                      FractionallySizedBox(
                        widthFactor: highest <= 0
                            ? 0.02
                            : (value / highest).clamp(0.02, 1),
                        child: ColoredBox(
                          color: current
                              ? accent
                              : accent.withValues(alpha: 0.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(currentLabel, currentValue, currentDisplay, true),
        row(previousLabel, previousValue, previousDisplay, false),
      ],
    );
  }
}
