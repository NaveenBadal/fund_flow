import 'package:flutter/widgets.dart';

import 'flux_colors.dart';

/// Depth, expressed differently per theme because the same technique cannot
/// work in both.
///
/// In light, depth is a two-layer shadow: a tight contact shadow plus a wide
/// ambient one. A single blurred shadow reads as a smudge; the pair reads as an
/// object above a surface.
///
/// In dark, shadows are invisible — black on near-black is nothing. Depth is
/// instead a step up the surface ramp plus a 1px light edge along the top,
/// which is how a real edge catches light. Reaching for a shadow in dark mode
/// is the single most common way a dark UI ends up looking flat.
abstract final class FluxElevation {
  /// Shadow alphas are written out rather than derived from the palette's
  /// shadow token. `withValues(alpha:)` *replaces* the alpha instead of scaling
  /// it, so deriving the ambient layer from an already-transparent token
  /// produced a 50%-black smudge under every card in light mode.
  static List<BoxShadow> card(FluxPalette palette) => palette.isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0F0A0A0F),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x140A0A0F),
            offset: Offset(0, 8),
            blurRadius: 24,
            spreadRadius: -6,
          ),
        ];

  static List<BoxShadow> floating(FluxPalette palette) => palette.isDark
      ? const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 8),
            blurRadius: 24,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x140A0A0F),
            offset: Offset(0, 2),
            blurRadius: 4,
          ),
          BoxShadow(
            color: Color(0x1F0A0A0F),
            offset: Offset(0, 14),
            blurRadius: 36,
            spreadRadius: -8,
          ),
        ];

  /// The top edge that lifts a dark surface. Returns null in light, where the
  /// shadow already does the work and a highlight would look like a seam.
  static Border? lift(FluxPalette palette) => palette.isDark
      ? Border(top: BorderSide(color: palette.highlight, width: 1))
      : null;
}
