import 'package:flutter/material.dart';

abstract final class CurrentColors {
  static const lightCanvas = Color(0xFFF5F3EE);
  static const lightSurface = Color(0xFFFCFBF8);
  static const lightSubtle = Color(0xFFECEBE5);
  static const lightInk = Color(0xFF202522);
  static const lightMuted = Color(0xFF68706B);
  static const lightRule = Color(0xFFD9DAD4);

  static const darkCanvas = Color(0xFF101411);
  static const darkSurface = Color(0xFF181D1A);
  static const darkSubtle = Color(0xFF222824);
  static const darkInk = Color(0xFFEEF1EC);
  static const darkMuted = Color(0xFFA8B0AA);
  static const darkRule = Color(0xFF343B36);

  static const river = Color(0xFF476F86);
  static const riverDark = Color(0xFF82AABD);
  static const moss = Color(0xFF4F765F);
  static const mossDark = Color(0xFF82AC90);
  static const clay = Color(0xFFA4604D);
  static const clayDark = Color(0xFFD39480);
  static const ochre = Color(0xFFA47C3B);
  static const ochreDark = Color(0xFFD2AA68);
}

@immutable
class CurrentPalette extends ThemeExtension<CurrentPalette> {
  const CurrentPalette({
    required this.canvas,
    required this.surface,
    required this.subtle,
    required this.ink,
    required this.muted,
    required this.rule,
    required this.intelligence,
    required this.income,
    required this.expense,
    required this.review,
  });

  final Color canvas;
  final Color surface;
  final Color subtle;
  final Color ink;
  final Color muted;
  final Color rule;
  final Color intelligence;
  final Color income;
  final Color expense;
  final Color review;

  static const light = CurrentPalette(
    canvas: CurrentColors.lightCanvas,
    surface: CurrentColors.lightSurface,
    subtle: CurrentColors.lightSubtle,
    ink: CurrentColors.lightInk,
    muted: CurrentColors.lightMuted,
    rule: CurrentColors.lightRule,
    intelligence: CurrentColors.river,
    income: CurrentColors.moss,
    expense: CurrentColors.clay,
    review: CurrentColors.ochre,
  );
  static const dark = CurrentPalette(
    canvas: CurrentColors.darkCanvas,
    surface: CurrentColors.darkSurface,
    subtle: CurrentColors.darkSubtle,
    ink: CurrentColors.darkInk,
    muted: CurrentColors.darkMuted,
    rule: CurrentColors.darkRule,
    intelligence: CurrentColors.riverDark,
    income: CurrentColors.mossDark,
    expense: CurrentColors.clayDark,
    review: CurrentColors.ochreDark,
  );

  @override
  CurrentPalette copyWith({
    Color? canvas,
    Color? surface,
    Color? subtle,
    Color? ink,
    Color? muted,
    Color? rule,
    Color? intelligence,
    Color? income,
    Color? expense,
    Color? review,
  }) => CurrentPalette(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    subtle: subtle ?? this.subtle,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    rule: rule ?? this.rule,
    intelligence: intelligence ?? this.intelligence,
    income: income ?? this.income,
    expense: expense ?? this.expense,
    review: review ?? this.review,
  );

  @override
  CurrentPalette lerp(covariant CurrentPalette? other, double t) => this;
}

extension CurrentContext on BuildContext {
  CurrentPalette get current => Theme.of(this).extension<CurrentPalette>()!;
}
