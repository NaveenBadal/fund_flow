import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// How a tap is acknowledged.
enum PressFeedback {
  /// The object shrinks and dims slightly. For cards, buttons, chips —
  /// anything that reads as a discrete thing being pushed.
  scale,

  /// A tint washes across the full bleed. For list rows, where scaling would
  /// detach the row from the rows around it.
  wash,

  none,
}

/// The single tap target in Flux.
///
/// Material's ink ripple is deliberately not used: a ripple animates outward
/// from the contact point, which draws the eye to where the finger was rather
/// than to the thing that is opening. Pressing an object down and letting it
/// spring back reads as direct manipulation instead.
class FluxPressable extends StatefulWidget {
  const FluxPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.feedback = PressFeedback.scale,
    this.haptic = true,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final PressFeedback feedback;
  final bool haptic;

  /// Only used by [PressFeedback.wash], to keep the tint inside the shape.
  final BorderRadius? borderRadius;

  @override
  State<FluxPressable> createState() => _FluxPressableState();
}

class _FluxPressableState extends State<FluxPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FluxMotion.micro,
    reverseDuration: FluxMotion.quick,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _press(bool down) {
    if (!_enabled || widget.feedback == PressFeedback.none) return;
    if (FluxMotion.reduced(context)) return;
    if (down) {
      _controller.forward();
    } else {
      // Releasing hands the value to a spring so the object settles rather
      // than stopping dead at rest.
      _controller.animateWith(
        FluxMotion.spring(FluxMotion.snap, from: _controller.value, to: 0),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: _enabled
          ? () {
              if (widget.haptic) HapticFeedback.selectionClick();
              widget.onTap?.call();
            }
          : null,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!.call();
            },
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final t = _controller.value;
          return switch (widget.feedback) {
            PressFeedback.none => child!,
            PressFeedback.scale => Transform.scale(
              scale: 1 - 0.025 * t,
              child: Opacity(opacity: 1 - 0.12 * t, child: child),
            ),
            PressFeedback.wash => DecoratedBox(
              decoration: BoxDecoration(
                color: palette.text.withValues(alpha: 0.05 * t),
                borderRadius: widget.borderRadius,
              ),
              child: child,
            ),
          };
        },
      ),
    );
  }
}
