import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for spacing, shape, motion,
/// and elevation across the app. Keeps every screen visually consistent.
class AppRadius {
  const AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
  static const double pill = 999;

  static BorderRadius all(double r) => BorderRadius.circular(r);
}

class ExpressiveShape {
  const ExpressiveShape._();

  static OutlinedBorder soft({Color color = Colors.transparent}) =>
      ContinuousRectangleBorder(
        borderRadius: BorderRadius.circular(40),
        side: BorderSide(color: color),
      );

  static OutlinedBorder hero({Color color = Colors.transparent}) =>
      ContinuousRectangleBorder(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(72),
          bottomLeft: Radius.circular(72),
          bottomRight: Radius.circular(32),
        ),
        side: BorderSide(color: color),
      );

  static BorderRadius playful(int index) => index.isEven
      ? const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(30),
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(18),
        )
      : const BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(30),
        );
}

/// Semantic finance colors resolved per theme brightness.
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
  });

  final Color income;
  final Color incomeSurface;
  final Color expense;
  final Color expenseSurface;
  final Color warning;
  final Color warningSurface;

  static const light = FinanceColors(
    income: Color(0xFF188038),
    incomeSurface: Color(0xFFE6F4EA),
    expense: Color(0xFFD93025),
    expenseSurface: Color(0xFFFCE8E6),
    warning: Color(0xFFB06000),
    warningSurface: Color(0xFFFEF7E0),
  );

  static const dark = FinanceColors(
    income: Color(0xFF81C995),
    incomeSurface: Color(0xFF0D3B22),
    expense: Color(0xFFF28B82),
    expenseSurface: Color(0xFF44201D),
    warning: Color(0xFFFDD663),
    warningSurface: Color(0xFF3D3000),
  );

  @override
  FinanceColors copyWith({
    Color? income,
    Color? incomeSurface,
    Color? expense,
    Color? expenseSurface,
    Color? warning,
    Color? warningSurface,
  }) {
    return FinanceColors(
      income: income ?? this.income,
      incomeSurface: incomeSurface ?? this.incomeSurface,
      expense: expense ?? this.expense,
      expenseSurface: expenseSurface ?? this.expenseSurface,
      warning: warning ?? this.warning,
      warningSurface: warningSurface ?? this.warningSurface,
    );
  }

  @override
  FinanceColors lerp(ThemeExtension<FinanceColors>? other, double t) {
    if (other is! FinanceColors) return this;
    return FinanceColors(
      income: Color.lerp(income, other.income, t)!,
      incomeSurface: Color.lerp(incomeSurface, other.incomeSurface, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseSurface: Color.lerp(expenseSurface, other.expenseSurface, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
    );
  }
}

/// Convenience accessor so widgets can write `context.finance.income`.
extension FinanceColorsX on BuildContext {
  FinanceColors get finance =>
      Theme.of(this).extension<FinanceColors>() ?? FinanceColors.light;
}
