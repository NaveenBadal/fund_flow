import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Quiet editorial surface used by legacy detail views while they share the
/// command-center design language. Hierarchy comes from tone and hairlines;
/// elevation is reserved for truly floating controls.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.radius = AppRadius.xl,
    this.onTap,
    this.color,
    this.border = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final surface = color ?? scheme.surfaceContainerLow;

    final decorated = Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.all(radius),
        border: border
            ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5))
            : null,
        boxShadow: brightness == Brightness.dark
            ? null
            : [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.025),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.all(radius),
      child: InkWell(
        borderRadius: AppRadius.all(radius),
        onTap: onTap,
        child: decorated,
      ),
    );
  }
}

/// Consistent section heading with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
