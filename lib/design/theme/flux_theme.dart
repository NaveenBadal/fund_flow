import 'package:flutter/material.dart';

import '../tokens/flux_colors.dart';
import '../tokens/flux_shape.dart';
import '../tokens/flux_type.dart';

export '../tokens/flux_colors.dart';
export '../tokens/flux_elevation.dart';
export '../tokens/flux_motion.dart';
export '../tokens/flux_shape.dart';
export '../tokens/flux_type.dart';

/// Carries the Flux palette through the widget tree.
///
/// The palette is reached with `context.flux` rather than through Material's
/// `ColorScheme`, because Material's roles (primary, tertiary, surfaceVariant)
/// cannot express the ones this app actually needs — "money arriving",
/// "needs a person" — and mapping onto them loses the meaning that makes the
/// design system enforceable.
@immutable
class FluxTokens extends ThemeExtension<FluxTokens> {
  const FluxTokens({required this.palette});
  final FluxPalette palette;

  @override
  FluxTokens copyWith({FluxPalette? palette}) =>
      FluxTokens(palette: palette ?? this.palette);

  /// Light and dark are distinct designs rather than points on a ramp, so
  /// there is nothing meaningful to interpolate. Snapping at the midpoint is
  /// honest; a blended palette would just be muddy for 200ms.
  @override
  FluxTokens lerp(FluxTokens? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension FluxContext on BuildContext {
  /// The active palette.
  FluxPalette get flux => Theme.of(this).extension<FluxTokens>()!.palette;
}

abstract final class FluxTheme {
  static ThemeData get light => _build(FluxPalette.light);
  static ThemeData get dark => _build(FluxPalette.dark);

  static ThemeData _build(FluxPalette p) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.iris,
          brightness: p.isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          primary: p.iris,
          onPrimary: p.onIris,
          surface: p.background,
          onSurface: p.text,
          error: p.danger,
          outlineVariant: p.line,
        );

    TextStyle body(TextStyle style) => style.copyWith(color: p.text);
    TextStyle muted(TextStyle style) => style.copyWith(color: p.textMuted);

    return ThemeData(
      useMaterial3: true,
      brightness: p.isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      fontFamily: FluxType.family,
      extensions: [FluxTokens(palette: p)],
      // Flux presses objects rather than rippling them: a ripple originates
      // where the finger landed, which draws attention to the touch instead of
      // to the thing being opened. FluxPressable handles the feedback.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerColor: p.line,
      dividerTheme: DividerThemeData(
        color: p.line,
        thickness: 1,
        space: 1,
        indent: 0,
        endIndent: 0,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.iris,
        selectionColor: p.irisSoft,
        selectionHandleColor: p.iris,
      ),
      iconTheme: IconThemeData(color: p.text, size: 22),
      primaryIconTheme: IconThemeData(color: p.iris),
      textTheme: TextTheme(
        displayLarge: body(FluxType.display),
        displayMedium: body(FluxType.display),
        headlineLarge: body(FluxType.display),
        headlineMedium: body(FluxType.title),
        headlineSmall: body(FluxType.title),
        titleLarge: body(FluxType.title),
        titleMedium: body(FluxType.subtitle),
        titleSmall: body(FluxType.label),
        bodyLarge: body(FluxType.bodyLarge),
        bodyMedium: body(FluxType.body),
        bodySmall: muted(FluxType.caption),
        labelLarge: body(FluxType.label),
        labelMedium: body(FluxType.label),
        labelSmall: muted(FluxType.overline),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: p.scrim,
        shape: FluxRadius.sheetShape,
        showDragHandle: false,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: FluxRadius.shape(FluxRadius.lg),
        elevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.isDark ? p.surfaceHighest : const Color(0xFF1B1B22),
        contentTextStyle: FluxType.body.copyWith(
          color: const Color(0xFFF5F5F7),
        ),
        actionTextColor: p.isDark ? p.irisPressed : const Color(0xFF9797F2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(FluxRadius.sm),
        ),
        elevation: 0,
        insetPadding: const EdgeInsets.all(FluxSpace.x4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.iris,
        linearTrackColor: p.surfaceHighest,
        circularTrackColor: p.surfaceHighest,
        strokeWidth: 2.5,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.iris,
        inactiveTrackColor: p.surfaceHighest,
        thumbColor: p.isDark ? p.text : p.surface,
        overlayColor: p.irisSoft,
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.onIris
              : (p.isDark ? p.textMuted : p.surface),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.iris : p.surfaceHighest,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.iris : p.lineStrong,
        ),
        trackOutlineWidth: const WidgetStatePropertyAll(1),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
