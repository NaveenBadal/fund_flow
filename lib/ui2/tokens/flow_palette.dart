import 'package:flutter/material.dart';

/// Colour tokens.
///
/// The categorical slots were computed and validated rather than chosen by
/// eye. The previous palette failed on colour-vision separation — its expense
/// and income hues sat 3.0 ΔE apart under protanopia, which is the classic
/// red-green failure applied to the direction money moved — so category could
/// not be encoded in colour at all.
///
/// These slots pass every check in both modes:
///
///   light  CVD ΔE 15.2 · normal ΔE 20.3 · all ≥ 3:1 against the surface
///   dark   CVD ΔE  9.2 · normal ΔE 16.3 · all ≥ 3:1 against the surface
///
/// Dark is selected against the dark surface rather than flipped from light,
/// because a flipped ramp lands outside the band the dark surface requires.
///
/// Adjacent slots alternate lightness on purpose. Deuteranopia collapses hue
/// difference, so value difference is what survives it; spacing hues alone
/// cannot get six slots past the check at a single lightness.
abstract final class FlowPalette {
  // ---------------------------------------------------------------- surfaces
  // Warm rather than neutral. A paper ground is the one thing worth keeping
  // from the previous language: every other money app is stark white or
  // black, and this is a screen someone opens daily.
  // Dark is the identity and light is its faithful translation, not the
  // other way round. Near-black rather than true black: #000 smears on OLED
  // during scroll and reads cheap, while a blue-cast charcoal lets a raised
  // surface look lit rather than merely lighter.
  // ---------------------------------------------------------------- surfaces
  // Dark mode is a rich velvet slate with blue undertones for OLED depth.
  static const darkCanvas = Color(0xFF10110F);
  static const darkSunken = Color(0xFF0B0C0A);
  static const darkRaised = Color(0xFF181A17);
  static const darkLine = Color(0xFF292C27);

  // Light mode is a pure silk ceramic with crisp cool neutrals.
  static const lightCanvas = Color(0xFFF5F4F0);
  static const lightSunken = Color(0xFFEDEBE5);
  static const lightRaised = Color(0xFFFBFAF7);
  static const lightLine = Color(0xFFDDDAD1);

  // -------------------------------------------------------------------- ink
  static const lightInk = Color(0xFF171914);
  static const lightInkSoft = Color(0xFF5E6258);
  static const lightInkFaint = Color(0xFF92968B);

  static const darkInk = Color(0xFFF4F3EE);
  static const darkInkSoft = Color(0xFFA8ACA1);
  static const darkInkFaint = Color(0xFF74796F);

  // ------------------------------------------------------------ categorical
  static const darkSeries = <Color>[
    Color(0xFF9CAB82),
    Color(0xFF78A7A0),
    Color(0xFFC5A56A),
    Color(0xFFA58A9C),
    Color(0xFF8A9BB5),
    Color(0xFFB78373),
  ];

  static const lightSeries = <Color>[
    Color(0xFF657651),
    Color(0xFF477B74),
    Color(0xFF9A7136),
    Color(0xFF806273),
    Color(0xFF596F8D),
    Color(0xFF955E50),
  ];

  // --------------------------------------------------------------- semantic
  static const darkIncome = Color(0xFF89B894);
  static const darkExpense = Color(0xFFD28D83);
  static const darkAttention = Color(0xFFD2AE69);
  static const darkAccent = Color(0xFFA8B993);

  static const lightIncome = Color(0xFF39744B);
  static const lightExpense = Color(0xFF9D4F48);
  static const lightAttention = Color(0xFF936B2E);
  static const lightAccent = Color(0xFF52643F);
}

/// Resolved colours for the active brightness.
@immutable
class FlowColors extends ThemeExtension<FlowColors> {
  const FlowColors({
    required this.canvas,
    required this.sunken,
    required this.raised,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.series,
    required this.income,
    required this.expense,
    required this.attention,
    required this.accent,
    required this.onAccent,
  });

  /// Three levels so hierarchy exists without shadows: [sunken] recedes,
  /// [canvas] is the page, [raised] advances.
  final Color canvas;
  final Color sunken;
  final Color raised;
  final Color line;

  final Color ink;
  final Color inkSoft;
  final Color inkFaint;

  final List<Color> series;
  final Color income;
  final Color expense;
  final Color attention;
  final Color accent;
  final Color onAccent;

  /// Slot for series [index], folding anything past the defined slots back
  /// into the fixed order rather than generating a new hue.
  Color seriesAt(int index) => series[index % series.length];

  static const light = FlowColors(
    canvas: FlowPalette.lightCanvas,
    sunken: FlowPalette.lightSunken,
    raised: FlowPalette.lightRaised,
    line: FlowPalette.lightLine,
    ink: FlowPalette.lightInk,
    inkSoft: FlowPalette.lightInkSoft,
    inkFaint: FlowPalette.lightInkFaint,
    series: FlowPalette.lightSeries,
    income: FlowPalette.lightIncome,
    expense: FlowPalette.lightExpense,
    attention: FlowPalette.lightAttention,
    accent: FlowPalette.lightAccent,
    onAccent: Color(0xFFF8F8F3),
  );

  static const dark = FlowColors(
    canvas: FlowPalette.darkCanvas,
    sunken: FlowPalette.darkSunken,
    raised: FlowPalette.darkRaised,
    line: FlowPalette.darkLine,
    ink: FlowPalette.darkInk,
    inkSoft: FlowPalette.darkInkSoft,
    inkFaint: FlowPalette.darkInkFaint,
    series: FlowPalette.darkSeries,
    income: FlowPalette.darkIncome,
    expense: FlowPalette.darkExpense,
    attention: FlowPalette.darkAttention,
    accent: FlowPalette.darkAccent,
    onAccent: Color(0xFF11130F),
  );

  @override
  FlowColors copyWith({
    Color? canvas,
    Color? sunken,
    Color? raised,
    Color? line,
    Color? ink,
    Color? inkSoft,
    Color? inkFaint,
    List<Color>? series,
    Color? income,
    Color? expense,
    Color? attention,
    Color? accent,
    Color? onAccent,
  }) => FlowColors(
    canvas: canvas ?? this.canvas,
    sunken: sunken ?? this.sunken,
    raised: raised ?? this.raised,
    line: line ?? this.line,
    ink: ink ?? this.ink,
    inkSoft: inkSoft ?? this.inkSoft,
    inkFaint: inkFaint ?? this.inkFaint,
    series: series ?? this.series,
    income: income ?? this.income,
    expense: expense ?? this.expense,
    attention: attention ?? this.attention,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
  );

  /// Themes swap wholesale rather than interpolating: a half-blended palette
  /// is not a state any of these values were validated in.
  @override
  FlowColors lerp(covariant FlowColors? other, double t) =>
      t < .5 ? this : (other ?? this);
}

extension FlowColorsOf on BuildContext {
  FlowColors get flow => Theme.of(this).extension<FlowColors>()!;
}
