import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// A trend line with no axes, no grid and no labels.
///
/// A sparkline answers "which way and how steadily", not "how much" — the
/// figure beside it answers that. Adding axes would turn a texture the eye
/// reads in a glance into a chart it has to study.
///
/// The line is 2px with a soft fill beneath it, and the last point carries a
/// dot so "where we are now" is findable without a label.
class FluxSparkline extends StatelessWidget {
  const FluxSparkline({
    super.key,
    required this.values,
    this.color,
    this.height = 44,
    this.fill = true,
    this.showLast = true,
    this.progress = 1,
  });

  final List<double> values;
  final Color? color;
  final double height;
  final bool fill;
  final bool showLast;

  /// Draw-on fraction, for the reveal when a screen first appears.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    if (values.length < 2) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color ?? palette.iris,
          fill: fill,
          showLast: showLast,
          progress: progress.clamp(0, 1),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.fill,
    required this.showLast,
    required this.progress,
  });

  final List<double> values;
  final Color color;
  final bool fill;
  final bool showLast;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final lowest = values.reduce((a, b) => a < b ? a : b);
    final highest = values.reduce((a, b) => a > b ? a : b);
    // A flat series would divide by zero and, drawn at the top of the box,
    // would read as a maximum. A zero span is drawn down the middle instead.
    final span = highest - lowest;
    const inset = 3.0;
    final usable = size.height - inset * 2;

    Offset pointAt(int index) {
      final x = size.width * (index / (values.length - 1));
      final normalised = span == 0 ? 0.5 : (values[index] - lowest) / span;
      return Offset(x, inset + usable * (1 - normalised));
    }

    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final point = pointAt(index);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        // A monotone-ish curve through the midpoint keeps the line smooth
        // without the overshoot a cubic through every point produces, which on
        // a spend series invents dips that are not in the data.
        final previous = pointAt(index - 1);
        final middle = Offset((previous.dx + point.dx) / 2, previous.dy);
        final middle2 = Offset((previous.dx + point.dx) / 2, point.dy);
        path.cubicTo(
          middle.dx,
          middle.dy,
          middle2.dx,
          middle2.dy,
          point.dx,
          point.dy,
        );
      }
    }

    final clip = Rect.fromLTWH(0, 0, size.width * progress, size.height);
    canvas.save();
    canvas.clipRect(clip);

    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.restore();

    if (showLast && progress >= 1) {
      final last = pointAt(values.length - 1);
      canvas.drawCircle(last, 3.5, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.progress != progress ||
      old.color != color ||
      !_sameValues(old.values, values);

  static bool _sameValues(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
