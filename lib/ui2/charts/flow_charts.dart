import 'dart:math';

import 'package:flutter/material.dart';

import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';
import '../tokens/flow_type.dart';

/// Chart primitives.
///
/// Category is never encoded in colour alone and direction never rests on
/// hue. The palette now passes colour-vision separation, so colour is
/// legitimate reinforcement, but a bar length or an explicit sign still has
/// to carry the meaning on its own.

/// Signed change against a comparable period.
class FlowDelta extends StatelessWidget {
  const FlowDelta({
    super.key,
    required this.fraction,
    this.spending = true,
    this.compact = false,
  });

  /// 0.12 renders as +12%.
  final double fraction;

  /// When true a rise is spending more and reads as adverse. False for
  /// income, where a rise is favourable.
  final bool spending;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final rising = fraction >= 0;
    final adverse = spending ? rising : !rising;
    final color = adverse ? flow.expense : flow.income;
    final percent = (fraction.abs() * 100).round();
    return Semantics(
      label: '${rising ? 'up' : 'down'} $percent percent',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 4,
        ),
        decoration: BoxDecoration(
          color: flow.sunken,
          borderRadius: FlowRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              rising ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: compact ? 11 : 13,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              '${rising ? '+' : '−'}$percent%',
              style: FlowType.amountSmall.copyWith(
                color: color,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact trend of recent daily totals.
///
/// Unlabelled and unaxed on purpose: it answers "calm or spiky", which is a
/// shape question. Axes would spend the space that makes it readable at this
/// size, and the figures are one tap away.
class FlowSpark extends StatelessWidget {
  const FlowSpark({super.key, required this.values, this.height = 30});

  /// Oldest to newest. Fewer than two points has no trend to draw.
  final List<int> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return SizedBox(height: height);
    final flow = context.flow;
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _SparkPainter(
          values: values,
          line: flow.accent,
          fill: flow.accent.withValues(alpha: .10),
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.line, required this.fill});
  final List<int> values;
  final Color line;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final peak = values.reduce(max).toDouble();
    // A flat run must not collapse onto the baseline and read as no data.
    final scale = peak <= 0 ? 1.0 : peak;
    final step = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = step * i;
      final y = size.height - (values[i] / scale) * (size.height - 3) - 1.5;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.75
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.line != line;
}

/// A labelled row whose bar length carries the magnitude.
class FlowBarRow extends StatelessWidget {
  const FlowBarRow({
    super.key,
    required this.label,
    required this.amount,
    required this.fraction,
    this.share,
    this.color,
    this.onTap,
  });

  final String label;

  /// Already formatted: this widget does not decide how money is written.
  final String amount;

  /// 0..1 of the largest row, so every row shares one baseline.
  final double fraction;
  final double? share;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final percent = share == null ? null : (share! * 100).round();
    final body = Padding(
      padding: const EdgeInsets.symmetric(vertical: FlowSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              if (percent != null) ...[
                Text(
                  '$percent%',
                  style: FlowType.amountSmall.copyWith(color: flow.inkFaint),
                ),
                const SizedBox(width: FlowSpace.sm),
              ],
              Text(amount, style: FlowType.amountRow.copyWith(color: flow.ink)),
            ],
          ),
          const SizedBox(height: 6),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: flow.sunken,
                  borderRadius: FlowRadius.xs,
                ),
              ),
              FractionallySizedBox(
                // A small non-zero value keeps a visible mark rather than
                // reading as absent.
                widthFactor: fraction.clamp(.03, 1.0),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: color ?? flow.accent,
                    borderRadius: FlowRadius.xs,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: FlowRadius.sm,
      child: body,
    );
  }
}
