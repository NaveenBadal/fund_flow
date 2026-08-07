import 'package:flutter/widgets.dart';

/// The Flux type ramp.
///
/// Inter is bundled as a variable font, so weight is a continuous axis. The
/// in-between weights (450 for body, 550 for labels, 650 for titles) are most
/// of the difference between a designed interface and a default one, and they
/// only render if [FontVariation] is set — [TextStyle.fontWeight] alone snaps
/// to the nearest hundred. Both are set: the variation drives the axis, the
/// weight keeps a sane fallback if the font ever fails to load.
///
/// The scale is deliberately jumpy (52 → 30 → 17). A money screen has to make
/// "how much" readable from arm's length while "what it was" stays quiet, and
/// an evenly-stepped ramp cannot do that.
///
/// Every money style carries [FontFeature.tabularFigures]. Proportional digits
/// shift width as they change, so an animating balance jitters and a column of
/// amounts fails to line up.
abstract final class FluxType {
  static const family = 'Inter';

  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  static TextStyle _style({
    required double size,
    required double height,
    required double weight,
    double tracking = 0,
    bool tabular = false,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: height / size,
    letterSpacing: tracking,
    fontWeight: FontWeight.values[((weight / 100).round() - 1).clamp(0, 8)],
    // Explicitly none. Every style here is merged onto whatever ambient
    // DefaultTextStyle is in scope, and Flutter's fallback style — the one in
    // effect outside a Material ancestor — carries a yellow debug underline
    // that then shows up on real text.
    decoration: TextDecoration.none,
    fontVariations: [FontVariation('wght', weight)],
    fontFeatures: tabular ? _tabular : null,
  );

  /// The single largest figure on a screen — the month's net flow.
  static final moneyHero = _style(
    size: 52,
    height: 56,
    weight: 700,
    tracking: -2,
    tabular: true,
  );

  /// A detail page's amount, or a stat tile.
  static final moneyLarge = _style(
    size: 30,
    height: 34,
    weight: 650,
    tracking: -1,
    tabular: true,
  );

  /// The amount on a ledger row.
  static final moneyRow = _style(
    size: 17,
    height: 22,
    weight: 600,
    tracking: -0.2,
    tabular: true,
  );

  static final moneySmall = _style(
    size: 13,
    height: 17,
    weight: 600,
    tabular: true,
  );

  /// A page's large collapsing title.
  static final display = _style(
    size: 34,
    height: 40,
    weight: 700,
    tracking: -1.2,
  );

  static final title = _style(
    size: 22,
    height: 28,
    weight: 650,
    tracking: -0.4,
  );

  static final subtitle = _style(
    size: 17,
    height: 22,
    weight: 600,
    tracking: -0.2,
  );

  /// Chat prose and merchant names — the one place text gets room to breathe.
  static final bodyLarge = _style(size: 17, height: 25, weight: 450);

  static final body = _style(size: 15, height: 22, weight: 450);

  static final label = _style(size: 13, height: 16, weight: 550, tracking: 0.1);

  static final caption = _style(size: 12, height: 16, weight: 500);

  /// Section headers. Caps with wide tracking, used sparingly.
  static final overline = _style(
    size: 11,
    height: 14,
    weight: 650,
    tracking: 0.8,
  );
}
