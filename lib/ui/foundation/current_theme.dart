import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'current_colors.dart';

abstract final class CurrentTheme {
  static ThemeData light() => _build(Brightness.light, CurrentPalette.light);
  static ThemeData dark() => _build(Brightness.dark, CurrentPalette.dark);

  static ThemeData _build(Brightness brightness, CurrentPalette palette) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: palette.intelligence,
      onPrimary: Colors.white,
      secondary: palette.income,
      onSecondary: Colors.white,
      error: palette.expense,
      onError: Colors.white,
      surface: palette.canvas,
      onSurface: palette.ink,
      surfaceContainerLowest: palette.canvas,
      surfaceContainerLow: palette.surface,
      surfaceContainer: palette.surface,
      surfaceContainerHigh: palette.subtle,
      surfaceContainerHighest: palette.subtle,
      onSurfaceVariant: palette.muted,
      outline: palette.muted,
      outlineVariant: palette.rule,
      inverseSurface: palette.ink,
      onInverseSurface: palette.canvas,
      inversePrimary: palette.intelligence,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.canvas,
      fontFamily: 'Inter',
      splashFactory: NoSplash.splashFactory,
    );
    final text = base.textTheme.apply(
      bodyColor: palette.ink,
      displayColor: palette.ink,
    );
    return base.copyWith(
      textTheme: text.copyWith(
        displayLarge: text.displayLarge?.copyWith(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w700,
          letterSpacing: -1.5,
          height: 1.04,
        ),
        headlineLarge: text.headlineLarge?.copyWith(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
          height: 1.08,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontFamily: 'Space Grotesk',
          fontWeight: FontWeight.w700,
          letterSpacing: -.5,
          height: 1.1,
        ),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: palette.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: palette.rule, thickness: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.canvas,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      extensions: [palette],
    );
  }
}
