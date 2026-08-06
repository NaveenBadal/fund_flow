import 'package:flutter/material.dart';

/// PrecisionTokens defines the fundamental building blocks of the Precision design system.
/// This system relies on true blacks, high-contrast whites, minimal grays,
/// and absolute 1px hairlines.
class PrecisionTokens {
  // Colors - Backgrounds & Surfaces
  static const Color backgroundDark = Color(0xFF000000); // True OLED Black
  static const Color surfaceDark = Color(0xFF0A0A0A);
  static const Color surfaceElevatedDark = Color(0xFF111111);
  
  static const Color backgroundLight = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF7F7F7);
  static const Color surfaceElevatedLight = Color(0xFFEBEBEB);

  // Colors - Borders
  static const Color borderDark = Color(0x1FFFFFFF); // 12% white
  static const Color borderLight = Color(0x1F000000); // 12% black

  // Colors - Typography
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFA1A1A1);
  static const Color textTertiaryDark = Color(0xFF666666);

  static const Color textPrimaryLight = Color(0xFF000000);
  static const Color textSecondaryLight = Color(0xFF666666);
  static const Color textTertiaryLight = Color(0xFFA1A1A1);

  // Accents (Used extremely sparingly)
  static const Color accentMoneyIn = Color(0xFF00FF9D); // Neon Mint
  static const Color accentMoneyOut = Color(0xFFFF5252); // Soft Rose
  static const Color accentIntelligence = Color(0xFF5E6AD2); // Deep Iris
  static const Color accentReview = Color(0xFFFFD54F); // Ochre/Warning

  // Typography - Font Families
  static const String fontFamily = 'Inter';

  // Spacing
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;
  static const double space64 = 64.0;

  // Radii - Precision uses tighter curves than typical Material/Cupertino
  static const Radius radius4 = Radius.circular(4.0);
  static const Radius radius8 = Radius.circular(8.0);
  static const Radius radius12 = Radius.circular(12.0);
  static const Radius radiusRound = Radius.circular(999.0); // For pills when necessary

  static const BorderRadius borderRadius8 = BorderRadius.all(radius8);
  static const BorderRadius borderRadius12 = BorderRadius.all(radius12);
  static const BorderRadius borderRadiusRound = BorderRadius.all(radiusRound);

  // Borders
  static BorderSide borderSideDark = const BorderSide(color: borderDark, width: 1.0);
  static BorderSide borderSideLight = const BorderSide(color: borderLight, width: 1.0);
  
  static Border sideBorderDark = Border.fromBorderSide(borderSideDark);
  static Border sideBorderLight = Border.fromBorderSide(borderSideLight);
}
