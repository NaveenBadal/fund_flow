import 'package:flutter/material.dart';

import '../foundation/current_colors.dart';

enum CurrentButtonStyle { filled, tonal, outline, text, destructive }

class CurrentButton extends StatelessWidget {
  const CurrentButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.style = CurrentButtonStyle.filled,
    this.expand = false,
    this.compact = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final CurrentButtonStyle style;
  final bool expand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.current;
    final enabled = onPressed != null;
    final (fill, foreground, border) = switch (style) {
      CurrentButtonStyle.filled => (
        p.intelligence,
        Colors.white,
        p.intelligence,
      ),
      CurrentButtonStyle.tonal => (p.subtle, p.ink, p.subtle),
      CurrentButtonStyle.outline => (Colors.transparent, p.ink, p.rule),
      CurrentButtonStyle.text => (
        Colors.transparent,
        p.intelligence,
        Colors.transparent,
      ),
      CurrentButtonStyle.destructive => (p.expense, Colors.white, p.expense),
    };
    final child = AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: enabled ? 1 : .42,
      child: Container(
        height: compact ? 48 : 56,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 9),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: expand ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}
