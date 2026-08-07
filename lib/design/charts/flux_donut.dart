import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// One slice of a donut, or one row of a breakdown — the same data either way.
@immutable
class FluxSlice {
  const FluxSlice({
    required this.label,
    required this.value,
    required this.color,
    this.display,
  });

  final String label;
  final double value;
  final Color color;

  /// The formatted amount, shown as a direct label.
  final String? display;
}

/// A category donut with a headline in the hole.
///
/// Rules this follows on purpose:
///
/// * Slices are separated by a 2px gap in the surface colour, not by a stroke.
///   A stroke around a slice adds a colour that is not in the data; a gap just
///   lets the surface through.
/// * Slices are never labelled inside the ring. Labels go in the legend beside
///   it, where they can be read — a 4% slice cannot hold text.
/// * The centre holds the total, because the first question about a breakdown
///   is always "of what?".
/// * Every slice is legend-labelled, which is also what satisfies the relief
///   rule for the three light-mode hues that sit under 3:1 on white.
class FluxDonut extends StatelessWidget {
  const FluxDonut({
    super.key,
    required this.slices,
    this.size = 132,
    this.thickness = 16,
    this.centreLabel,
    this.centreValue,
    this.progress = 1,
    this.emphasised,
  });

  final List<FluxSlice> slices;
  final double size;
  final double thickness;
  final String? centreLabel;
  final String? centreValue;
  final double progress;

  /// Index of the slice under the finger, drawn slightly thicker.
  final int? emphasised;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(
              slices: total <= 0 ? const [] : slices,
              thickness: thickness,
              gapColor: palette.surface,
              trackColor: palette.surfaceHighest,
              progress: progress.clamp(0, 1),
              emphasised: emphasised,
            ),
          ),
          if (centreValue != null)
            // Constrained to the hole and scaled down to fit. An unbounded
            // figure grew straight through the ring, which looked like a
            // rendering fault rather than a long number.
            SizedBox(
              width: size - thickness * 2 - FluxSpace.x4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      centreValue!,
                      maxLines: 1,
                      style: FluxType.moneySmall.copyWith(
                        color: palette.text,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  if (centreLabel != null)
                    Text(
                      centreLabel!,
                      style: FluxType.caption.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.slices,
    required this.thickness,
    required this.gapColor,
    required this.trackColor,
    required this.progress,
    required this.emphasised,
  });

  final List<FluxSlice> slices;
  final double thickness;
  final Color gapColor;
  final Color trackColor;
  final double progress;
  final int? emphasised;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final radius = size.width / 2 - thickness / 2;
    final rect = Rect.fromCircle(center: centre, radius: radius);

    if (slices.isEmpty) {
      canvas.drawArc(
        rect,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = thickness
          ..color = trackColor,
      );
      return;
    }

    final total = slices.fold<double>(0, (sum, slice) => sum + slice.value);
    // Twelve o'clock, clockwise — where a clock and every pie chart start.
    var start = -math.pi / 2;
    // The gap is expressed in radians at this radius so it stays 2 physical
    // pixels whatever the donut's size.
    final gap = 2 / radius;

    for (var index = 0; index < slices.length; index++) {
      final slice = slices[index];
      final sweep = (slice.value / total) * math.pi * 2 * progress;
      // A slice thinner than the gap would render as a gap. Skipping it is
      // more honest than drawing a sliver that reads as a separator.
      if (sweep > gap) {
        final wide = emphasised == index;
        canvas.drawArc(
          wide ? rect.inflate(0) : rect,
          start + gap / 2,
          sweep - gap,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = wide ? thickness + 5 : thickness
            ..strokeCap = StrokeCap.butt
            ..color = slice.color,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.progress != progress ||
      old.emphasised != emphasised ||
      old.slices.length != slices.length ||
      old.gapColor != gapColor;
}

/// The legend beside a donut: a colour dot, the label, and the amount.
///
/// Present whenever there are two or more slices. Identity is never carried by
/// colour alone.
class FluxDonutLegend extends StatelessWidget {
  const FluxDonutLegend({
    super.key,
    required this.slices,
    this.onTap,
    this.max = 5,
  });

  final List<FluxSlice> slices;
  final void Function(FluxSlice slice)? onTap;
  final int max;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final slice in slices.take(max))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: GestureDetector(
              onTap: onTap == null ? null : () => onTap!(slice),
              behavior: HitTestBehavior.opaque,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: ShapeDecoration(
                      color: slice.color,
                      shape: const CircleBorder(),
                    ),
                  ),
                  const SizedBox(width: FluxSpace.x2),
                  Expanded(
                    child: Text(
                      slice.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // Text keeps ink colour; the dot beside it carries the
                      // identity. Colouring the label too would make a legend
                      // of eight differently-coloured words.
                      style: FluxType.body.copyWith(color: palette.text),
                    ),
                  ),
                  if (slice.display != null)
                    Text(
                      slice.display!,
                      style: FluxType.moneySmall.copyWith(
                        color: palette.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
