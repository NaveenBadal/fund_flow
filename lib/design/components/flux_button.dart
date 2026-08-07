import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';
import 'flux_pressable.dart';

enum FluxButtonKind {
  /// Iris fill. One per screen — the thing you came here to do.
  primary,

  /// Filled with a neutral surface. For secondary but real actions.
  secondary,

  /// Text only. For actions that undo, dismiss or navigate sideways.
  ghost,

  /// Red text on a red-tinted surface. Always behind a confirmation.
  danger,
}

class FluxButton extends StatelessWidget {
  const FluxButton({
    super.key,
    required this.label,
    this.onPressed,
    this.kind = FluxButtonKind.primary,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final FluxButtonKind kind;
  final IconData? icon;

  /// Shows a spinner in place of the icon and blocks the tap. The label stays,
  /// because a button that loses its label mid-action leaves someone unsure
  /// what they pressed.
  final bool busy;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final enabled = onPressed != null && !busy;

    final (Color background, Color foreground) = switch (kind) {
      FluxButtonKind.primary => (palette.iris, palette.onIris),
      FluxButtonKind.secondary => (palette.surfaceHighest, palette.text),
      FluxButtonKind.ghost => (const Color(0x00000000), palette.iris),
      FluxButtonKind.danger => (palette.dangerSoft, palette.danger),
    };

    final height = compact ? 38.0 : FluxSpace.tap + 4;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox(width: 15, height: 15, child: _Spinner(color: foreground))
        else if (icon != null)
          Icon(icon, size: compact ? 16 : 18, color: foreground),
        if (busy || icon != null) const SizedBox(width: FluxSpace.x2),
        Text(
          label,
          style: (compact ? FluxType.label : FluxType.subtitle).copyWith(
            color: foreground,
          ),
        ),
      ],
    );

    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: FluxPressable(
        onTap: enabled ? onPressed : null,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: background,
            shape: FluxRadius.shape(
              compact ? FluxRadius.xs : FluxRadius.sm,
              side: kind == FluxButtonKind.ghost
                  ? BorderSide.none
                  : BorderSide.none,
            ),
          ),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? FluxSpace.x3 : FluxSpace.x5,
              ),
              child: Center(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular icon button, sized to the minimum tap target.
class FluxIconButton extends StatelessWidget {
  const FluxIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.filled = false,
    this.color,
    this.size = 20,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool filled;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final button = FluxPressable(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: filled ? palette.surfaceHighest : const Color(0x00000000),
          shape: const CircleBorder(),
        ),
        child: SizedBox(
          width: FluxSpace.tap,
          height: FluxSpace.tap,
          child: Center(
            child: Icon(
              icon,
              size: size,
              color: (color ?? palette.text).withValues(
                alpha: onPressed == null ? 0.35 : 1,
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Semantics(label: tooltip, button: true, child: button);
  }
}

class _Spinner extends StatefulWidget {
  const _Spinner({required this.color});
  final Color color;

  @override
  State<_Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<_Spinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: CustomPaint(painter: _ArcPainter(widget.color)),
  );
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(Offset.zero & size, -1.4, 3.6, false, paint);
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) => oldDelegate.color != color;
}
