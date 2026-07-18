import 'package:flutter/material.dart';

import 'app_tokens.dart';

class AppTheme {
  const AppTheme._();

  static const seed = Color(0xFF5B4BDB);
  static const _tabular = [FontFeature.tabularFigures()];

  static ThemeData light(ColorScheme? _) => _build(Brightness.light);
  static ThemeData dark(ColorScheme? _) => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final generated = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
      contrastLevel: .15,
    );
    // Flow's intelligence signal and financial semantics must remain stable.
    // Device wallpaper colors are intentionally not allowed to redefine the
    // brand or trust states of this finance product.
    final scheme = generated;
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
    // Space Grotesk is reserved for display, headline, and big numbers — the
    // expressive voice. Titles/labels/body stay Inter for calm legibility.
    TextStyle? display(TextStyle? style, FontWeight weight, double tracking) =>
        style?.copyWith(
          fontFamily: 'Space Grotesk',
          fontWeight: weight,
          letterSpacing: tracking,
          height: 1.04,
        );
    return base.copyWith(
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
      textTheme: text.copyWith(
        displayLarge: display(text.displayLarge, FontWeight.w700, -1.5),
        displayMedium: display(text.displayMedium, FontWeight.w700, -1.2),
        displaySmall: display(text.displaySmall, FontWeight.w700, -1),
        headlineLarge: display(text.headlineLarge, FontWeight.w600, -0.8),
        headlineMedium: display(text.headlineMedium, FontWeight.w600, -0.6),
        headlineSmall: display(text.headlineSmall, FontWeight.w600, -0.4),
        titleLarge: display(text.titleLarge, FontWeight.w600, -0.2),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
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
          FontWeight.w600,
          -0.4,
        )?.copyWith(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: ExpressiveShape.card(),
      ),
      listTileTheme: ListTileThemeData(
        shape: ExpressiveShape.card(radius: AppRadius.lg),
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
        shape: const StadiumBorder(),
        side: BorderSide(color: scheme.outlineVariant),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 54),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: ExpressiveShape.soft(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 54),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: ExpressiveShape.soft(),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const CircleBorder(),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        elevation: 0,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        selectedLabelTextStyle: text.labelLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: text.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 2,
        focusElevation: 4,
        highlightElevation: 5,
        extendedTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
        shape: ExpressiveShape.soft(),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: .7),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
        shape: ExpressiveShape.card(radius: AppRadius.md),
        insetPadding: const EdgeInsets.all(16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLow,
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
