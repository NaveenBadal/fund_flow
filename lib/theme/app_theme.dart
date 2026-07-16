import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  const AppTheme._();

  static const seed = Color(0xFF5B4BDB);
  static const _tabular = [FontFeature.tabularFigures()];

  static ThemeData light(ColorScheme? dynamic) =>
      _build(Brightness.light, dynamic);
  static ThemeData dark(ColorScheme? dynamic) =>
      _build(Brightness.dark, dynamic);

  static ThemeData _build(Brightness brightness, ColorScheme? dynamic) {
    final dark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
      contrastLevel: .15,
    );
    final source = dynamic ?? generated;
    final scheme = source.copyWith(
      primary: dark ? const Color(0xFFC7BFFF) : const Color(0xFF5545D6),
      onPrimary: dark ? const Color(0xFF281A93) : Colors.white,
      primaryContainer: dark
          ? const Color(0xFF3D2EB1)
          : const Color(0xFFE5DEFF),
      onPrimaryContainer: dark
          ? const Color(0xFFE5DEFF)
          : const Color(0xFF1A0065),
      secondary: dark ? const Color(0xFF80D5C7) : const Color(0xFF006B5F),
      secondaryContainer: dark
          ? const Color(0xFF005047)
          : const Color(0xFFA1F2E3),
      tertiary: dark ? const Color(0xFFFFB77C) : const Color(0xFF9A4600),
      tertiaryContainer: dark
          ? const Color(0xFF713200)
          : const Color(0xFFFFDCC3),
      surface: dark ? const Color(0xFF121118) : const Color(0xFFFFF8FF),
      surfaceContainer: dark
          ? const Color(0xFF211F27)
          : const Color(0xFFF7F0FA),
      surfaceContainerHigh: dark
          ? const Color(0xFF2C2932)
          : const Color(0xFFEFE7F2),
      onSurface: dark ? const Color(0xFFECE7F0) : const Color(0xFF211F24),
      onSurfaceVariant: dark
          ? const Color(0xFFCCC4D0)
          : const Color(0xFF625D66),
      outlineVariant: dark ? const Color(0xFF49454F) : const Color(0xFFD0C8D4),
      error: dark ? const Color(0xFFFFB4AB) : const Color(0xFFBA1A1A),
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      fontFamily: 'Inter',
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
    );
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle? display(TextStyle? style, FontWeight weight) => style?.copyWith(
      fontFamily: 'Space Grotesk',
      fontWeight: weight,
      letterSpacing: -1,
      height: 1.05,
    );
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      textTheme: text.copyWith(
        displayLarge: display(text.displayLarge, FontWeight.w700),
        displayMedium: display(text.displayMedium, FontWeight.w700),
        displaySmall: display(text.displaySmall, FontWeight.w700),
        headlineLarge: display(text.headlineLarge, FontWeight.w700),
        headlineMedium: display(text.headlineMedium, FontWeight.w700),
        headlineSmall: display(text.headlineSmall, FontWeight.w700),
        titleLarge: display(text.titleLarge, FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: display(
          text.headlineSmall,
          FontWeight.w700,
        )?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: ExpressiveShape.soft(color: scheme.outlineVariant),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          borderSide: BorderSide(color: scheme.primary, width: 2.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: ExpressiveShape.soft(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 52),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
          shape: ExpressiveShape.soft(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 3,
        focusElevation: 5,
        highlightElevation: 6,
        shape: ExpressiveShape.soft(),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .75),
        thickness: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const ContinuousRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(56)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        shape: ExpressiveShape.hero(),
      ),
      extensions: [dark ? FinanceColors.dark : FinanceColors.light],
    );
  }

  static TextStyle money(TextStyle? base) => (base ?? const TextStyle())
      .copyWith(fontFeatures: _tabular, fontWeight: FontWeight.w700);
}
