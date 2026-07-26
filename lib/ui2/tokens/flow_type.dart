import 'package:flutter/material.dart';

/// Typography.
///
/// Amounts are the primary content of this app, so they are treated as a
/// separate role rather than as body text that happens to contain digits.
/// The previous language set balances in the display face, whose wide
/// apertures and distinctive terminals give it personality that competes
/// with precision. A balance should read as exact, not as characterful.
///
/// Every numeric style carries tabular figures so columns align and a
/// changing amount does not reflow the text around it.
abstract final class FlowType {
  /// One family keeps the product visually quieter and avoids shipping a
  /// second font solely for headings.
  static const String display = 'sans-serif';

  /// Body, labels, controls.
  static const String text = 'Inter';

  static const List<FontFeature> _tabular = [
    FontFeature.tabularFigures(),
    FontFeature.slashedZero(),
  ];

  /// The single most important number on a screen.
  ///
  /// Deliberately enormous. The interface has almost no decoration, so what
  /// carries it is the ratio between this and the 11pt label above it — at
  /// 40pt against 12pt body there was no ratio and nothing led.
  static const TextStyle amountHero = TextStyle(
    fontFamily: text,
    fontSize: 48,
    height: 1.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -1.8,
    fontFeatures: _tabular,
  );

  /// The quiet line above a figure. Small, tracked wide, never sentence case.
  ///
  /// Tracking is what stops something this small reading as an afterthought;
  /// it is the counterweight that makes the figure below it feel placed
  /// rather than merely big.
  static const TextStyle eyebrow = TextStyle(
    fontFamily: text,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: .1,
  );

  /// Section totals and card headline figures.
  static const TextStyle amountLarge = TextStyle(
    fontFamily: text,
    fontSize: 24,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -.6,
    fontFeatures: _tabular,
  );

  /// Ledger rows.
  static const TextStyle amountRow = TextStyle(
    fontFamily: text,
    fontSize: 15,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -.2,
    fontFeatures: _tabular,
  );

  /// Axis ticks, percentages, dense annotations.
  static const TextStyle amountSmall = TextStyle(
    fontFamily: text,
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
    fontFeatures: _tabular,
  );

  static TextTheme theme(Color ink) => TextTheme(
    displayLarge: TextStyle(
      fontFamily: display,
      fontSize: 36,
      height: 1.04,
      fontWeight: FontWeight.w600,
      letterSpacing: -1.1,
      color: ink,
    ),
    headlineLarge: TextStyle(
      fontFamily: display,
      fontSize: 27,
      height: 1.1,
      fontWeight: FontWeight.w600,
      letterSpacing: -.8,
      color: ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: display,
      fontSize: 22,
      height: 1.15,
      fontWeight: FontWeight.w600,
      letterSpacing: -.5,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontFamily: text,
      fontSize: 17,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -.2,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontFamily: text,
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    bodyLarge: TextStyle(
      fontFamily: text,
      fontSize: 15,
      height: 1.5,
      color: ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: text,
      fontSize: 14,
      height: 1.45,
      color: ink,
    ),
    bodySmall: TextStyle(
      fontFamily: text,
      fontSize: 12.5,
      height: 1.35,
      color: ink,
    ),
    labelLarge: TextStyle(
      fontFamily: text,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    labelMedium: TextStyle(
      fontFamily: text,
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    labelSmall: TextStyle(
      fontFamily: text,
      fontSize: 11,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: .2,
      color: ink,
    ),
  );
}
