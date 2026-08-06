import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ff_theme.dart';

/// A column chart you can drag a finger across.
///
/// No gridlines, no axis, no legend. A month of spending is a shape, and the
/// shape is the whole message; the exact figure belongs to whichever bar is
/// being touched, which is why selection is the only affordance here.
class FFBars extends StatefulWidget {
  const FFBars({
    super.key,
    required this.values,
    required this.onSelected,
    this.height = 130,
    this.selected,
    this.emphasis,
  });

  final List<int> values;

  /// Null when the finger lifts, so the caller can go back to the total.
  final ValueChanged<int?> onSelected;

  final double height;
  final int? selected;

  /// Bars at or past this index are drawn solid; earlier ones are quieted.
  /// Used to grey out days that have not happened yet.
  final int? emphasis;

  @override
  State<FFBars> createState() => _FFBarsState();
}

class _FFBarsState extends State<FFBars> {
  int? _touched;
  int? _lastHaptic;

  void _pick(double dx, double width) {
    if (widget.values.isEmpty) return;
    final index = (dx / width * widget.values.length).floor().clamp(
      0,
      widget.values.length - 1,
    );
    if (index == _touched) return;
    if (_lastHaptic != index) {
      HapticFeedback.selectionClick();
      _lastHaptic = index;
    }
    setState(() => _touched = index);
    widget.onSelected(index);
  }

  void _release() {
    if (_touched == null) return;
    setState(() => _touched = null);
    _lastHaptic = null;
    widget.onSelected(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final values = widget.values;
    if (values.isEmpty) return SizedBox(height: widget.height);
    final max = values.fold(0, (a, b) => a > b ? a : b);
    final active = _touched ?? widget.selected;

    return Semantics(
      label: 'Daily spending. Drag across the chart to inspect a day.',
      child: LayoutBuilder(
        builder: (context, box) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
          onTapUp: (_) => _release(),
          onTapCancel: _release,
          onHorizontalDragStart: (d) => _pick(d.localPosition.dx, box.maxWidth),
          onHorizontalDragUpdate: (d) =>
              _pick(d.localPosition.dx, box.maxWidth),
          onHorizontalDragEnd: (_) => _release(),
          onHorizontalDragCancel: _release,
          child: SizedBox(
            height: widget.height,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: values.length > 20 ? 1.5 : 3,
                      ),
                      child: AnimatedContainer(
                        duration: Duration(
                          milliseconds: context.ffStill ? 0 : 200,
                        ),
                        curve: Curves.easeOutCubic,
                        height: max <= 0
                            ? 3
                            : 3 + (widget.height - 3) * values[i] / max,
                        decoration: BoxDecoration(
                          color: active == null
                              ? _barColor(context, i)
                              : active == i
                              ? c.label
                              : _barColor(context, i).withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _barColor(BuildContext context, int index) {
    final c = context.ff;
    // A day with nothing spent still needs a mark to keep the axis readable,
    // but drawing it in the accent claims there was activity.
    if (widget.values[index] == 0) return c.quaternaryLabel;
    if (widget.emphasis == null || index <= widget.emphasis!) return c.tint;
    return c.quaternaryLabel;
  }
}

/// A line, for the small trend that sits under a headline figure.
class FFTrend extends StatelessWidget {
  const FFTrend({
    super.key,
    required this.values,
    this.height = 56,
    this.color,
  });

  final List<int> values;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendPainter(
          values: values,
          color: color ?? context.ff.tint,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({required this.values, required this.color});
  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return;

    // Cumulative, not daily: the question a trend line answers is "how far
    // through the month's money am I", and a jagged per-day line answers a
    // different one badly.
    var running = 0;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      running += values[i];
      points.add(Offset(size.width * i / (values.length - 1), running.toDouble()));
    }
    final peak = running == 0 ? 1 : running;
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final y = size.height - 2 - (size.height - 6) * points[i].dy / peak;
      i == 0 ? path.moveTo(points[i].dx, y) : path.lineTo(points[i].dx, y);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.values != values || old.color != color;
}

/// A share-of-total row: label, amount, and a bar that carries the proportion
/// so the list can be read without doing arithmetic.
class FFProportion extends StatelessWidget {
  const FFProportion({
    super.key,
    required this.label,
    required this.trailing,
    required this.fraction,
    this.color,
  });

  final String label;
  final Widget trailing;
  final double fraction;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FFText.callout,
                ),
              ),
              const SizedBox(width: FFSpace.md),
              trailing,
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            // Both widths are measured, not inferred. A fill that takes its
            // size from a factor rather than a number ends up with nothing to
            // measure against and collapses to an invisible bar.
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Container(width: box.maxWidth, height: 5, color: c.fill),
                  Container(
                    width: box.maxWidth * fraction.clamp(0.0, 1.0),
                    height: 5,
                    color: color ?? c.tint,
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
