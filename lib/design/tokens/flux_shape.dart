import 'package:flutter/widgets.dart';

/// Spacing, radii and shape.
///
/// Corners are continuous (superellipse), not circular. Flutter ships
/// [RoundedSuperellipseBorder] natively, so this costs nothing and is most of
/// what reads as considered rather than default — a circular corner meets its
/// straight edge at a visible break, a continuous one does not.
abstract final class FluxSpace {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;
  static const double x16 = 64;

  /// Horizontal page inset. Everything on a page lines up on this.
  static const double page = 20;

  /// Minimum tappable extent. Anything smaller gets padding to reach it.
  static const double tap = 44;
}

abstract final class FluxRadius {
  static const double xs = 8;
  static const double sm = 14;
  static const double md = 20;
  static const double lg = 28;
  static const double sheet = 32;

  static ShapeBorder shape(
    double radius, {
    BorderSide side = BorderSide.none,
  }) => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.circular(radius),
    side: side,
  );

  static ShapeBorder get card => shape(md);

  static ShapeBorder get sheetShape => const RoundedSuperellipseBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(sheet)),
  );

  static const StadiumBorder pill = StadiumBorder();
}
