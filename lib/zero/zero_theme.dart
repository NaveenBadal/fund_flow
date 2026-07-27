import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui2/tokens/flow_palette.dart';

@immutable
class ZeroColors extends ThemeExtension<ZeroColors> {
  const ZeroColors({
    required this.bg,
    required this.surface,
    required this.subtle,
    required this.line,
    required this.text,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.onAccent,
    required this.positive,
    required this.warning,
    required this.negative,
  });

  final Color bg;
  final Color surface;
  final Color subtle;
  final Color line;
  final Color text;
  final Color muted;
  final Color faint;
  final Color accent;
  final Color onAccent;
  final Color positive;
  final Color warning;
  final Color negative;

  static const light = ZeroColors(
    bg: Color(0xfff6f5f1),
    surface: Color(0xfffcfbf8),
    subtle: Color(0xffeeede8),
    line: Color(0xffdeddd7),
    text: Color(0xff171815),
    muted: Color(0xff62645d),
    faint: Color(0xff92958c),
    accent: Color(0xff304f3d),
    onAccent: Color(0xfff7faf7),
    positive: Color(0xff33714b),
    warning: Color(0xff956a2c),
    negative: Color(0xff984f49),
  );

  static const dark = ZeroColors(
    bg: Color(0xff0e100e),
    surface: Color(0xff171a17),
    subtle: Color(0xff20241f),
    line: Color(0xff2d322d),
    text: Color(0xfff1f2ed),
    muted: Color(0xffa7aba2),
    faint: Color(0xff747970),
    accent: Color(0xffafc9b4),
    onAccent: Color(0xff112018),
    positive: Color(0xff8fc29c),
    warning: Color(0xffd1ad6c),
    negative: Color(0xffd4938d),
  );

  @override
  ZeroColors copyWith() => this;

  @override
  ZeroColors lerp(covariant ZeroColors? other, double t) =>
      t < .5 ? this : (other ?? this);
}

extension ZeroContext on BuildContext {
  ZeroColors get zero => Theme.of(this).extension<ZeroColors>()!;
}

abstract final class ZeroTheme {
  static ThemeData light() => _make(Brightness.light, ZeroColors.light);
  static ThemeData dark() => _make(Brightness.dark, ZeroColors.dark);

  static ThemeData _make(Brightness brightness, ZeroColors z) {
    TextStyle style(
      double size, {
      FontWeight weight = FontWeight.w400,
      double height = 1.3,
      double? spacing,
    }) => TextStyle(
      fontFamily: 'Inter',
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: z.text,
    );

    final text = TextTheme(
      displayLarge: style(48, weight: FontWeight.w600, height: 1, spacing: -2),
      headlineLarge: style(
        32,
        weight: FontWeight.w600,
        height: 1.08,
        spacing: -1,
      ),
      headlineMedium: style(
        25,
        weight: FontWeight.w600,
        height: 1.15,
        spacing: -.5,
      ),
      titleLarge: style(19, weight: FontWeight.w600, height: 1.2),
      titleMedium: style(16, weight: FontWeight.w600),
      bodyLarge: style(16, height: 1.5),
      bodyMedium: style(14, height: 1.45),
      bodySmall: style(12.5, height: 1.4),
      labelLarge: style(14, weight: FontWeight.w600, height: 1.2),
      labelMedium: style(12, weight: FontWeight.w600, height: 1.2),
      labelSmall: style(11, weight: FontWeight.w500, height: 1.2),
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: z.accent,
      brightness: brightness,
      primary: z.accent,
      surface: z.bg,
      error: z.negative,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: z.bg,
      colorScheme: scheme.copyWith(
        surface: z.bg,
        onSurface: z.text,
        outline: z.line,
        surfaceContainer: z.surface,
      ),
      textTheme: text,
      fontFamily: 'Inter',
      visualDensity: VisualDensity.standard,
      splashFactory: NoSplash.splashFactory,
      highlightColor: z.subtle,
      dividerColor: z.line,
      appBarTheme: AppBarTheme(
        backgroundColor: z.bg,
        foregroundColor: z.text,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: z.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: z.subtle,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: z.accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 50),
          side: BorderSide(color: z.line),
          foregroundColor: z.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: z.accent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          foregroundColor: z.muted,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: z.subtle,
        selectedColor: z.accent,
        disabledColor: z.subtle,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: z.onAccent),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? z.accent : z.line,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? z.onAccent : z.surface,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: z.accent,
        linearTrackColor: z.subtle,
        circularTrackColor: z.subtle,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _ZeroTransitionBuilder(),
          TargetPlatform.iOS: _ZeroTransitionBuilder(),
        },
      ),
      extensions: [
        z,
        FlowColors(
          canvas: z.bg,
          sunken: z.subtle,
          raised: z.surface,
          line: z.line,
          ink: z.text,
          inkSoft: z.muted,
          inkFaint: z.faint,
          series: const [
            Color(0xff5f7666),
            Color(0xff6d7d83),
            Color(0xff927346),
            Color(0xff7d6875),
            Color(0xff61728a),
            Color(0xff8c6558),
          ],
          income: z.positive,
          expense: z.negative,
          attention: z.warning,
          accent: z.accent,
          onAccent: z.onAccent,
        ),
      ],
    );
  }
}

class _ZeroTransitionBuilder extends PageTransitionsBuilder {
  const _ZeroTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst) return child;
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) return child;
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: SlideTransition(
        position: Tween(begin: const Offset(0, .018), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }
}

abstract final class ZeroSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;
}
