import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

@immutable
class FluxBar {
  const FluxBar({
    required this.value,
    this.label,
    this.color,
    this.highlight = false,
  });

  final double value;
  final String? label;
  final Color? color;

  /// Today, or the period being compared against — drawn in full strength
  /// while the rest recede.
  final bool highlight;
}

/// A bar series: daily spend, or two periods side by side.
///
/// Bars are anchored to the baseline with 4px rounded ends at the data end
/// only — rounding both ends detaches the bar from its axis and makes small
/// values look larger than they are. Adjacent bars are separated by a 2px gap
/// in the surface rather than by an outline.
///
/// There is deliberately no second y-axis and no gridlines: the labels under
/// the bars and the one figure above the chart carry the scale.
class FluxBars extends StatelessWidget {
  const FluxBars({
    super.key,
    required this.bars,
    this.height = 72,
    this.color,
    this.progress = 1,
    this.showLabels = false,
    this.onTapIndex,
  });

  final List<FluxBar> bars;
  final double height;
  final Color? color;
  final double progress;
  final bool showLabels;
  final ValueChanged<int>? onTapIndex;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    if (bars.isEmpty) return SizedBox(height: height);
    final chart = SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarsPainter(
          bars: bars,
          base: color ?? palette.iris,
          muted: (color ?? palette.iris).withValues(alpha: 0.35),
          empty: palette.surfaceHighest,
          progress: progress.clamp(0, 1),
        ),
      ),
    );
    final body = onTapIndex == null
        ? chart
        : LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              onTapDown: (details) {
                final slot = constraints.maxWidth / bars.length;
                final index = (details.localPosition.dx / slot).floor();
                onTapIndex!(index.clamp(0, bars.length - 1));
              },
              child: chart,
            ),
          );
    if (!showLabels) return body;
    return Column(
      children: [
        body,
        const SizedBox(height: FluxSpace.x2),
        Row(
          children: [
            for (final bar in bars)
              Expanded(
                child: Text(
                  bar.label ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: FluxType.caption.copyWith(
                    color: bar.highlight ? palette.text : palette.textFaint,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter({
    required this.bars,
    required this.base,
    required this.muted,
    required this.empty,
    required this.progress,
  });

  final List<FluxBar> bars;
  final Color base;
  final Color muted;
  final Color empty;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final highest = bars
        .map((bar) => bar.value)
        .fold<double>(0, (a, b) => a > b ? a : b);
    final slot = size.width / bars.length;
    // A 2px gap between bars, taken out of the slot rather than added to it, so
    // the series still spans the full width.
    final width = (slot - 2).clamp(2.0, 28.0);
    // A highlight only mutes the rest if the highlighted bar actually has
    // something in it. Today is highlighted by default, and on a morning with
    // no spending yet that dimmed the entire month to make room for a bar that
    // was not there.
    final anyHighlight = bars.any((bar) => bar.highlight && bar.value > 0);

    for (var index = 0; index < bars.length; index++) {
      final bar = bars[index];
      final centre = slot * index + slot / 2;
      final fraction = highest <= 0 ? 0.0 : bar.value / highest;
      // A day with no spending still gets a 2px stub. A gap in the row reads
      // as missing data; a stub reads as zero, which is what it is.
      final full = size.height * fraction * progress;
      final barHeight = bar.value <= 0 ? 2.0 : full.clamp(3.0, size.height);
      final rect = Rect.fromLTWH(
        centre - width / 2,
        size.height - barHeight,
        width,
        barHeight,
      );
      final paint = Paint()
        ..color = bar.value <= 0
            ? empty
            : (bar.color ?? (anyHighlight && !bar.highlight ? muted : base));
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          // Rounded at the data end only; square where it meets the baseline.
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress ||
      old.bars.length != bars.length ||
      old.base != base;
}

/// The inline proportional bar on a breakdown row.
///
/// Sits under the label rather than beside it, so the label and the amount keep
/// full width and the bar is read as an annotation of the row.
class FluxProportion extends StatelessWidget {
  const FluxProportion({
    super.key,
    required this.fraction,
    required this.color,
    this.height = 4,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: palette.surfaceHighest)),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.02, 1),
              child: AnimatedContainer(
                duration: FluxMotion.duration(context, FluxMotion.large),
                curve: FluxMotion.emphasized,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
