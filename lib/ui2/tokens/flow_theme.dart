import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'flow_metrics.dart';
import 'flow_palette.dart';
import 'flow_type.dart';

/// Assembles the tokens into a Material theme.
///
/// Material defaults are overridden rather than inherited wherever they carry
/// their own visual opinion: elevation tints, splash colour and surface tint
/// would otherwise reintroduce a second design language underneath this one.
abstract final class FlowTheme {
  static ThemeData light() => _build(Brightness.light, FlowColors.light);
  static ThemeData dark() => _build(Brightness.dark, FlowColors.dark);

  static ThemeData _build(Brightness brightness, FlowColors flow) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: flow.accent,
      onPrimary: flow.onAccent,
      secondary: flow.income,
      onSecondary: flow.onAccent,
      error: flow.expense,
      onError: flow.onAccent,
      surface: flow.canvas,
      onSurface: flow.ink,
      surfaceContainerLowest: flow.sunken,
      surfaceContainerLow: flow.canvas,
      surfaceContainer: flow.raised,
      surfaceContainerHigh: flow.raised,
      surfaceContainerHighest: flow.raised,
      onSurfaceVariant: flow.inkSoft,
      outline: flow.inkFaint,
      outlineVariant: flow.line,
      inverseSurface: flow.ink,
      onInverseSurface: flow.canvas,
      inversePrimary: flow.accent,
      shadow: const Color(0x00000000),
      scrim: const Color(0x66000000),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: flow.canvas,
      canvasColor: flow.canvas,
      textTheme: FlowType.theme(flow.ink),
      // Hierarchy comes from the three surface levels, not from tinted
      // elevation, which would shift colour with depth.
      applyElevationOverlayColor: false,
      splashFactory: NoSplash.splashFactory,
      highlightColor: flow.line.withValues(alpha: .4),
      dividerTheme: DividerThemeData(color: flow.line, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: flow.canvas,
        foregroundColor: flow.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: flow.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: flow.ink,
        contentTextStyle: FlowType.theme(flow.canvas).bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: FlowRadius.sm),
      ),
      extensions: [flow],
    );
  }
}
