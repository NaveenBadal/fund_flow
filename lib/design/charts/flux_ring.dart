import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// A budget ring: spent against a limit.
///
/// Status colour, not a categorical hue — a budget has states (fine, close,
/// over) and states are exactly what the status palette is for. Over-budget
/// also draws a second lap over the first, so 140% reads as past the limit
/// rather than as a full ring indistinguishable from 100%.
///
/// The percentage sits inside the ring and the category name under it, so the
/// state is never carried by colour alone.
class FluxRing extends StatelessWidget {
  const FluxRing({
    super.key,
    required this.fraction,
    required this.label,
    this.detail,
    this.size = 72,
    this.thickness = 7,
    this.onTap,
  });

  /// Spent ÷ limit. May exceed 1.
  final double fraction;
  final String label;
  final String? detail;
  final double size;
  final double thickness;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final over = fraction > 1;
    final close = !over && fraction >= 0.85;
    final color = over
        ? palette.danger
        : (close ? palette.attention : palette.iris);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: size + 8,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size.square(size),
                    painter: _RingPainter(
                      fraction: fraction,
                      color: color,
                      track: palette.surfaceHighest,
                      thickness: thickness,
                    ),
                  ),
                  Text(
                    '${(fraction * 100).round()}%',
                    style: FluxType.moneySmall.copyWith(
                      color: over ? palette.danger : palette.text,
                      fontSize: size * 0.19,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: FluxSpace.x2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FluxType.caption.copyWith(color: palette.text),
            ),
            if (detail != null)
              Text(
                detail!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FluxType.caption.copyWith(
                  color: palette.textMuted,
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.thickness,
  });

  final double fraction;
  final Color color;
  final Color track;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - thickness / 2,
    );
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..color = track,
    );
    final first = fraction.clamp(0.0, 1.0);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * first,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
    if (fraction > 1) {
      // The overflow lap is drawn thinner and inset, so it reads as a second
      // pass rather than as a thicker ring.
      canvas.drawArc(
        rect.deflate(thickness * 0.75),
        -math.pi / 2,
        math.pi * 2 * (fraction - 1).clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness * 0.5
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color;
}

/// A month-progress arc: how far through the period the spending figure is.
///
/// "₹42,000 spent" means something different on the 3rd than on the 28th, and
/// this is the cheapest way to put that on screen without a second number.
class FluxProgressArc extends StatelessWidget {
  const FluxProgressArc({
    super.key,
    required this.fraction,
    this.height = 3,
    this.color,
  });

  final double fraction;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: palette.line)),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.01, 1),
              child: ColoredBox(color: color ?? palette.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
