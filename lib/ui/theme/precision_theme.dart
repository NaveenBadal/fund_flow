import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../tokens/precision_tokens.dart';

class PrecisionTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: PrecisionTokens.backgroundDark,
      fontFamily: PrecisionTokens.fontFamily,
      
      // Text Theme
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -1.5, color: PrecisionTokens.textPrimaryDark),
        displayMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1.0, color: PrecisionTokens.textPrimaryDark),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: PrecisionTokens.textPrimaryDark),
        
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: PrecisionTokens.textPrimaryDark),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: PrecisionTokens.textPrimaryDark),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: PrecisionTokens.textSecondaryDark),
        
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: PrecisionTokens.textPrimaryDark),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: PrecisionTokens.textPrimaryDark),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: PrecisionTokens.textSecondaryDark, letterSpacing: 0.5),
      ),

      // App Bar
      appBarTheme: const AppBarTheme(
        backgroundColor: PrecisionTokens.backgroundDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          fontFamily: PrecisionTokens.fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: PrecisionTokens.textPrimaryDark,
        ),
      ),

      // Ink effects - removed for a more precise, instant feel
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      
      // Divider
      dividerTheme: const DividerThemeData(
        color: PrecisionTokens.borderDark,
        thickness: 1.0,
        space: 1.0,
      ),

      // Bottom Sheet
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PrecisionTokens.surfaceDark,
        modalBackgroundColor: PrecisionTokens.surfaceDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: PrecisionTokens.radius12),
        ),
      ),
    );
  }

  // Light theme follows the same principles but inverted
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: PrecisionTokens.backgroundLight,
      fontFamily: PrecisionTokens.fontFamily,
      
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 48, fontWeight: FontWeight.w700, letterSpacing: -1.5, color: PrecisionTokens.textPrimaryLight),
        displayMedium: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1.0, color: PrecisionTokens.textPrimaryLight),
        displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: PrecisionTokens.textPrimaryLight),
        
        bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: PrecisionTokens.textPrimaryLight),
        bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: PrecisionTokens.textPrimaryLight),
        bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: PrecisionTokens.textSecondaryLight),
        
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: PrecisionTokens.textPrimaryLight),
        labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: PrecisionTokens.textPrimaryLight),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: PrecisionTokens.textSecondaryLight, letterSpacing: 0.5),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: PrecisionTokens.backgroundLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontFamily: PrecisionTokens.fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.5,
          color: PrecisionTokens.textPrimaryLight,
        ),
      ),

      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      
      dividerTheme: const DividerThemeData(
        color: PrecisionTokens.borderLight,
        thickness: 1.0,
        space: 1.0,
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PrecisionTokens.surfaceLight,
        modalBackgroundColor: PrecisionTokens.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: PrecisionTokens.radius12),
        ),
      ),
    );
  }
}

extension TextStyleExtensions on TextStyle {
  /// Applies tabular figures to numbers to prevent jittering during layout
  TextStyle get tabular => copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}
