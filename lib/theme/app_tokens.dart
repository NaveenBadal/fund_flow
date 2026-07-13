import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for spacing, shape, motion,
/// and elevation across the app. Keeps every screen visually consistent.
class AppSpacing {
  const AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const EdgeInsets screen = EdgeInsets.fromLTRB(16, 8, 16, 24);
}

class AppRadius {
  const AppRadius._();
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double xl = 28;
  static const double xxl = 32;
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

class AppMotion {
  const AppMotion._();
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration medium = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 600);
  static const Curve emphasized = Curves.easeOutCubic;
  static const Curve standard = Curves.easeInOutCubic;
}

/// Soft, layered shadows tuned per brightness. Real depth without heaviness.
class AppShadow {
  const AppShadow._();

  static List<BoxShadow> soft(Brightness b, {Color? tint}) {
    if (b == Brightness.dark) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];
    }
    final base = (tint ?? const Color(0xFF1B1B3A));
    return [
      BoxShadow(
        color: base.withValues(alpha: 0.06),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: base.withValues(alpha: 0.04),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
    ];
  }
}

/// Semantic finance colors + brand gradients, resolved per theme brightness.
/// Registered as a [ThemeExtension] so any widget can read them via
/// `Theme.of(context).extension<FinanceColors>()!`.
@immutable
class FinanceColors extends ThemeExtension<FinanceColors> {
  const FinanceColors({
    required this.income,
    required this.incomeSurface,
    required this.expense,
    required this.expenseSurface,
    required this.warning,
    required this.warningSurface,
    required this.heroGradient,
    required this.accentGradient,
  });

  final Color income;
  final Color incomeSurface;
  final Color expense;
  final Color expenseSurface;
  final Color warning;
  final Color warningSurface;
  final List<Color> heroGradient;
  final List<Color> accentGradient;

  static const light = FinanceColors(
    income: Color(0xFF16845B),
    incomeSurface: Color(0xFFDDF4E9),
    expense: Color(0xFFD95745),
    expenseSurface: Color(0xFFFBE5DF),
    warning: Color(0xFF9A6800),
    warningSurface: Color(0xFFFFEDC1),
    heroGradient: [Color(0xFF171916), Color(0xFF30352C), Color(0xFFB9F227)],
    accentGradient: [Color(0xFFB9F227), Color(0xFF73D6B0)],
  );

  static const dark = FinanceColors(
    income: Color(0xFF72DDB2),
    incomeSurface: Color(0xFF13372B),
    expense: Color(0xFFFF866F),
    expenseSurface: Color(0xFF42201A),
    warning: Color(0xFFFFCF62),
    warningSurface: Color(0xFF3A2E11),
    heroGradient: [Color(0xFF10120F), Color(0xFF2C3129), Color(0xFFB9F227)],
    accentGradient: [Color(0xFFB9F227), Color(0xFF72DDB2)],
  );

  @override
  FinanceColors copyWith({
    Color? income,
    Color? incomeSurface,
    Color? expense,
    Color? expenseSurface,
    Color? warning,
    Color? warningSurface,
    List<Color>? heroGradient,
    List<Color>? accentGradient,
  }) {
    return FinanceColors(
      income: income ?? this.income,
      incomeSurface: incomeSurface ?? this.incomeSurface,
      expense: expense ?? this.expense,
      expenseSurface: expenseSurface ?? this.expenseSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
      heroGradient: heroGradient ?? this.heroGradient,
      accentGradient: accentGradient ?? this.accentGradient,
    );
  }

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    List<Color> lerpList(List<Color> a, List<Color> b) => [
      for (var i = 0; i < a.length && i < b.length; i++)
        Color.lerp(a[i], b[i], t)!,
    ];
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      incomeSurface: Color.lerp(incomeSurface, other.incomeSurface, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseSurface: Color.lerp(expenseSurface, other.expenseSurface, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      heroGradient: lerpList(heroGradient, other.heroGradient),
      accentGradient: lerpList(accentGradient, other.accentGradient),
    );
  }
}

/// Convenience accessor so widgets can write `context.finance.income`.
extension FinanceColorsX on BuildContext {
  FinanceColors get finance =>
      Theme.of(this).extension<FinanceColors>() ?? FinanceColors.light;
}
