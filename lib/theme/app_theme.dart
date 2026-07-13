import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Central theme factory. Produces cohesive light/dark [ThemeData] from a
/// seed or dynamic [ColorScheme], with a two-typeface system:
/// Space Grotesk for display/headings, Inter for body/labels, tabular
/// figures on numeric styles so currency columns align perfectly.
///
/// Fonts are bundled (see pubspec `fonts:`) — no runtime network fetch, so
/// typography renders correctly offline.
class AppTheme {
  const AppTheme._();

  /// Brand fallback seed when the platform provides no dynamic color.
  static const seed = Color(0xFF78A900);

  static const _bodyFont = 'Inter';
  static const _displayFont = 'Space Grotesk';

  static const _sub = FlexSubThemesData(
    blendOnLevel: 8,
    blendOnColors: false,
    useMaterial3Typography: true,
    useM2StyleDividerInM3: false,
    alignedDropdown: true,
    useInputDecoratorThemeInDialogs: true,
    cardRadius: AppRadius.xl,
    defaultRadius: AppRadius.md,
    inputDecoratorRadius: AppRadius.md,
    inputDecoratorBorderType: FlexInputBorderType.outline,
    inputDecoratorIsFilled: true,
    chipRadius: AppRadius.pill,
    chipSchemeColor: SchemeColor.primaryContainer,
    fabUseShape: true,
    fabRadius: AppRadius.lg,
    navigationBarHeight: 74,
    navigationBarIndicatorSchemeColor: SchemeColor.primaryContainer,
    navigationBarSelectedLabelSchemeColor: SchemeColor.onSurface,
    elevatedButtonRadius: AppRadius.pill,
    filledButtonRadius: AppRadius.pill,
    outlinedButtonRadius: AppRadius.pill,
    textButtonRadius: AppRadius.pill,
    bottomSheetRadius: AppRadius.xxl,
    dialogRadius: AppRadius.xl,
    snackBarRadius: AppRadius.md,
    tooltipRadius: AppRadius.sm,
  );

  static ThemeData light(ColorScheme? dynamicScheme) =>
      _build(Brightness.light, dynamicScheme);

  static ThemeData dark(ColorScheme? dynamicScheme) =>
      _build(Brightness.dark, dynamicScheme);

  static ThemeData _build(Brightness brightness, ColorScheme? dynamicScheme) {
    final isLight = brightness == Brightness.light;

    final ThemeData base = dynamicScheme != null
        ? (isLight
              ? FlexThemeData.light(
                  colorScheme: dynamicScheme,
                  subThemesData: _sub,
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                )
              : FlexThemeData.dark(
                  colorScheme: dynamicScheme,
                  subThemesData: _sub.copyWith(blendOnLevel: 16),
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                ))
        : (isLight
              ? FlexThemeData.light(
                  colors: const FlexSchemeColor(
                    primary: Color(0xFF4E7100),
                    primaryContainer: Color(0xFFDDF7A2),
                    secondary: Color(0xFF416456),
                    secondaryContainer: Color(0xFFD2EDDF),
                    tertiary: Color(0xFF7A594D),
                    tertiaryContainer: Color(0xFFFFDBCF),
                  ),
                  surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
                  blendLevel: 4,
                  subThemesData: _sub,
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                )
              : FlexThemeData.dark(
                  colors: const FlexSchemeColor(
                    primary: Color(0xFFB9F227),
                    primaryContainer: Color(0xFF334600),
                    secondary: Color(0xFF9CD4BD),
                    secondaryContainer: Color(0xFF244C3D),
                    tertiary: Color(0xFFFFB5A0),
                    tertiaryContainer: Color(0xFF65372A),
                  ),
                  surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
                  blendLevel: 8,
                  subThemesData: _sub.copyWith(blendOnLevel: 16),
                  visualDensity: FlexColorScheme.comfortablePlatformDensity,
                  useMaterial3: true,
                ));

    return base.copyWith(
      scaffoldBackgroundColor: base.colorScheme.surface,
      textTheme: _textTheme(base.textTheme),
      appBarTheme: base.appBarTheme.copyWith(
        centerTitle: false,
        scrolledUnderElevation: 0.5,
        titleTextStyle: TextStyle(
          fontFamily: _displayFont,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: base.colorScheme.onSurface,
        ),
      ),
      extensions: [isLight ? FinanceColors.light : FinanceColors.dark],
    );
  }

  static const _tabular = [FontFeature.tabularFigures()];

  /// Space Grotesk on the large/heading roles, Inter on the reading roles.
  static TextTheme _textTheme(TextTheme base) {
    final body = base.apply(fontFamily: _bodyFont);

    TextStyle? head(TextStyle? s, FontWeight w) => s?.copyWith(
      fontFamily: _displayFont,
      fontWeight: w,
      fontFeatures: _tabular,
      letterSpacing: -0.5,
    );

    return body.copyWith(
      displayLarge: head(body.displayLarge, FontWeight.w700),
      displayMedium: head(body.displayMedium, FontWeight.w700),
      displaySmall: head(body.displaySmall, FontWeight.w700),
      headlineLarge: head(body.headlineLarge, FontWeight.w700),
      headlineMedium: head(body.headlineMedium, FontWeight.w800),
      headlineSmall: head(body.headlineSmall, FontWeight.w700),
      titleLarge: body.titleLarge?.copyWith(
        fontFamily: _displayFont,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleMedium: body.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: body.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  /// Tabular numeric style for currency values — use on any amount so digits
  /// stay column-aligned regardless of value.
  static TextStyle money(TextStyle? base) => (base ?? const TextStyle())
      .copyWith(fontFeatures: _tabular, fontWeight: FontWeight.w800);
}
