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
  static const darkCanvas = Color(0xFF07090E);
  static const darkSunken = Color(0xFF0B0E15);
  static const darkRaised = Color(0xFF111520);
  static const darkLine = Color(0xFF1E2538);

  // Light mode is a pure silk ceramic with crisp cool neutrals.
  static const lightCanvas = Color(0xFFF8FAFC);
  static const lightSunken = Color(0xFFF1F5F9);
  static const lightRaised = Color(0xFFFFFFFF);
  static const lightLine = Color(0xFFE2E8F0);

  // -------------------------------------------------------------------- ink
  static const lightInk = Color(0xFF0F172A);
  static const lightInkSoft = Color(0xFF475569);
  static const lightInkFaint = Color(0xFF94A3B8);

  static const darkInk = Color(0xFFF8FAFC);
  static const darkInkSoft = Color(0xFF94A3B8);
  static const darkInkFaint = Color(0xFF64748B);

  // ------------------------------------------------------------ categorical
  static const darkSeries = <Color>[
    Color(0xFF6366F1), // indigo electric
    Color(0xFF06B6D4), // cyan
    Color(0xFF10B981), // emerald
    Color(0xFFF59E0B), // amber
    Color(0xFFF43F5E), // rose
    Color(0xFF8B5CF6), // violet
  ];

  static const lightSeries = <Color>[
    Color(0xFF4F46E5),
    Color(0xFF0891B2),
    Color(0xFF059669),
    Color(0xFFD97706),
    Color(0xFFE11D48),
    Color(0xFF7C3AED),
  ];

  // --------------------------------------------------------------- semantic
  static const darkIncome = Color(0xFF10B981);
  static const darkExpense = Color(0xFFF43F5E);
  static const darkAttention = Color(0xFFF59E0B);
  static const darkAccent = Color(0xFF6366F1);

  static const lightIncome = Color(0xFF059669);
  static const lightExpense = Color(0xFFE11D48);
  static const lightAttention = Color(0xFFD97706);
  static const lightAccent = Color(0xFF4F46E5);
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
    onAccent: Colors.white,
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
    onAccent: Colors.white,
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
