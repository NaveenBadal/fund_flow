import 'package:flutter/material.dart';
import '../tokens/precision_tokens.dart';

/// A set of highly refined, brutalist-minimal widgets for the Precision UI.

class PrecisionSurface extends StatelessWidget {
  final Widget child;
  final bool elevated;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;

  const PrecisionSurface({
    super.key,
    required this.child,
    this.elevated = false,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(PrecisionTokens.space16),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: elevated 
            ? (isDark ? PrecisionTokens.surfaceElevatedDark : PrecisionTokens.surfaceElevatedLight)
            : (isDark ? PrecisionTokens.surfaceDark : PrecisionTokens.surfaceLight),
        borderRadius: PrecisionTokens.borderRadius8,
        border: isDark ? PrecisionTokens.sideBorderDark : PrecisionTokens.sideBorderLight,
      ),
      child: child,
    );
  }
}

class PrecisionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isLoading;

  const PrecisionButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isPrimary = true,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    // Primary: High contrast (White bg in dark mode, Black bg in light mode)
    final primaryBg = isDark ? PrecisionTokens.backgroundLight : PrecisionTokens.backgroundDark;
    final primaryFg = isDark ? PrecisionTokens.textPrimaryLight : PrecisionTokens.textPrimaryDark;
    
    // Secondary: Transparent with border
    final secondaryBg = Colors.transparent;
    final secondaryFg = isDark ? PrecisionTokens.textPrimaryDark : PrecisionTokens.textPrimaryLight;

    return Material(
      color: isPrimary ? primaryBg : secondaryBg,
      shape: RoundedRectangleBorder(
        borderRadius: PrecisionTokens.borderRadius8,
        side: isPrimary 
            ? BorderSide.none 
            : BorderSide(color: isDark ? PrecisionTokens.borderDark : PrecisionTokens.borderLight),
      ),
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: PrecisionTokens.borderRadius8,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: PrecisionTokens.space16),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(isPrimary ? primaryFg : secondaryFg),
                    ),
                  )
                : Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isPrimary ? primaryFg : secondaryFg,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class PrecisionDivider extends StatelessWidget {
  const PrecisionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1);
  }
}

class PrecisionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const PrecisionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.displaySmall),
        if (subtitle != null) ...[
          const SizedBox(height: PrecisionTokens.space8),
          Text(
            subtitle!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.brightness == Brightness.dark 
                  ? PrecisionTokens.textSecondaryDark 
                  : PrecisionTokens.textSecondaryLight,
            ),
          ),
        ],
      ],
    );
  }
}
