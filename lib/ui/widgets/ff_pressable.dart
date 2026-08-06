import 'package:flutter/material.dart';

import '../theme/ff_theme.dart';

/// Press feedback for everything in the app.
///
/// Two behaviours, chosen by [highlight]:
///
/// * `false` — the element dims. Correct for buttons, icons and links, where
///   the thing you touched is the thing that should react.
/// * `true` — a fill washes in behind the element. Correct for list rows,
///   where the row is a region rather than an object.
///
/// A ripple would be wrong for both: it spreads from a point and outlives the
/// touch, which reads as the interface deciding something rather than
/// acknowledging you.
class FFPressable extends StatefulWidget {
  const FFPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.highlight = false,
    this.radius = 0,
    this.dim = .4,
    this.semanticLabel,
    this.button = true,
    this.selected,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Wash a fill behind the child instead of dimming it.
  final bool highlight;
  final double radius;

  /// Opacity held while pressed, when dimming.
  final double dim;
  final String? semanticLabel;
  final bool button;
  final bool? selected;
  final HitTestBehavior behavior;

  @override
  State<FFPressable> createState() => _FFPressableState();
}

class _FFPressableState extends State<FFPressable> {
  bool _down = false;

  void _set(bool value) {
    if (_down == value || widget.onTap == null && widget.onLongPress == null) {
      return;
    }
    setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final still = context.ffStill;
    final duration = Duration(milliseconds: still ? 0 : (_down ? 40 : 220));

    Widget child = widget.child;
    if (widget.highlight) {
      child = AnimatedContainer(
        duration: duration,
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _down ? context.ff.fill : Colors.transparent,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
        child: child,
      );
    } else {
      child = AnimatedOpacity(
        duration: duration,
        curve: Curves.easeOut,
        opacity: _down && enabled ? widget.dim : 1,
        child: child,
      );
    }

    return Semantics(
      button: widget.button,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        child: child,
      ),
    );
  }
}

/// A hairline. Always exactly one physical pixel, never a rounded-up logical
/// one, because a 1dp rule on a 3x screen is a visible grey bar.
class FFSeparator extends StatelessWidget {
  const FFSeparator({super.key, this.indent = 0, this.opaque = false});

  final double indent;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final thickness = 1 / MediaQuery.devicePixelRatioOf(context);
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: Container(
        height: thickness,
        color: opaque ? context.ff.opaqueSeparator : context.ff.separator,
      ),
    );
  }
}
