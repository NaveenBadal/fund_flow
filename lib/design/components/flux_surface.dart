import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';
import 'flux_pressable.dart';

/// A card: a continuous-cornered surface one step above its background.
class FluxCard extends StatelessWidget {
  const FluxCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FluxSpace.x5),
    this.onTap,
    this.radius = FluxRadius.md,
    this.color,
    this.border,
    this.raised = false,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;

  /// An explicit edge, for cards that carry a state (attention, danger).
  final Color? border;

  /// One step further up the ramp, for cards sitting on another card.
  final bool raised;

  /// Clip children to the shape. Costs a save layer, so it is opt-in and used
  /// only where a chart or image actually reaches the edge.
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(radius),
      side: border == null
          ? (palette.isDark
                ? BorderSide(color: palette.line, width: 1)
                : BorderSide.none)
          : BorderSide(color: border!, width: 1),
    );
    Widget content = Padding(padding: padding, child: child);
    if (clip) {
      content = ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: content,
      );
    }
    final card = DecoratedBox(
      decoration: ShapeDecoration(
        color: color ?? (raised ? palette.surfaceRaised : palette.surface),
        shape: shape,
        shadows: FluxElevation.card(palette),
      ),
      child: content,
    );
    if (onTap == null) return card;
    return FluxPressable(onTap: onTap, child: card);
  }
}

/// Frosted chrome that floats over scrolling content.
///
/// Glass is allowed on exactly four things — the nav bar, a collapsed page
/// header, sheet chrome, and the chat composer. Two rules keep it from turning
/// into grey mush: never nest glass inside glass, and never put it over a
/// static background, where it has nothing to sample and costs a raster pass
/// for no visual gain.
class FluxGlass extends StatelessWidget {
  const FluxGlass({
    super.key,
    required this.child,
    this.blur = 24,
    this.opacity = 0.72,
    this.border,
    this.shape,
  });

  final Widget child;
  final double blur;
  final double opacity;

  /// Which edge separates the glass from the content it floats over.
  final Border? border;
  final BorderRadius? shape;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final surface = palette.background.withValues(alpha: opacity);
    final painted = DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        border: border,
        borderRadius: shape,
      ),
      child: child,
    );

    // No blur asked for, no filter built. A zero-sigma BackdropFilter still
    // costs a save layer for nothing.
    if (blur <= 0) {
      return shape == null
          ? painted
          : ClipRRect(borderRadius: shape!, child: painted);
    }

    // The clip is not optional. A BackdropFilter blurs everything behind it
    // within its layer, and an unclipped one takes the whole ancestor repaint
    // boundary with it — the tab bar's glass blurred the entire page under it,
    // which looked exactly like a broken render rather than like frosting.
    final blurred = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: painted,
    );
    return shape == null
        ? ClipRect(child: blurred)
        : ClipRRect(borderRadius: shape!, child: blurred);
  }
}

/// A hairline, inset to the page gutter by default so it separates content
/// rather than cutting the screen in half.
class FluxLine extends StatelessWidget {
  const FluxLine({super.key, this.indent = 0, this.strong = false});
  final double indent;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: strong ? palette.lineStrong : palette.line),
      ),
    );
  }
}
