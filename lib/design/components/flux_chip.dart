import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';
import 'flux_pressable.dart';

/// A filter or choice chip.
///
/// Selected chips are iris-filled rather than merely outlined, because an
/// outline-only selected state is nearly invisible against the row of
/// unselected chips beside it.
class FluxChip extends StatelessWidget {
  const FluxChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
    this.trailingIcon,
    this.tint,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// A dismiss affordance, for an applied filter.
  final IconData? trailingIcon;

  /// Overrides the selected fill — used by category chips so a chip carries
  /// the same hue as that category everywhere else.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final accent = tint ?? palette.iris;
    final background = selected
        ? (palette.isDark
              ? accent.withValues(alpha: 0.22)
              : accent.withValues(alpha: 0.12))
        : palette.surfaceHighest;
    final foreground = selected ? accent : palette.textMuted;

    return FluxPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: background,
          shape: StadiumBorder(
            side: selected
                ? BorderSide(color: accent.withValues(alpha: 0.5), width: 1)
                : BorderSide.none,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: icon == null ? FluxSpace.x3 : FluxSpace.x2 + 2,
            right: trailingIcon == null ? FluxSpace.x3 : FluxSpace.x2,
            top: FluxSpace.x2,
            bottom: FluxSpace.x2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: foreground),
                const SizedBox(width: FluxSpace.x1 + 2),
              ],
              Text(label, style: FluxType.label.copyWith(color: foreground)),
              if (trailingIcon != null) ...[
                const SizedBox(width: FluxSpace.x1),
                Icon(trailingIcon, size: 14, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A segmented control: two to four mutually exclusive options.
///
/// The selection is a sliding pill rather than a repaint, so the eye follows
/// which option was chosen instead of having to re-find it.
class FluxSegmented<T> extends StatelessWidget {
  const FluxSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final index = options.indexWhere((option) => option.$1 == value);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: palette.surfaceHighest,
        shape: FluxRadius.shape(FluxRadius.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth / options.length;
            return SizedBox(
              height: 36,
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: FluxMotion.duration(context, FluxMotion.quick),
                    curve: FluxMotion.emphasized,
                    alignment: options.length == 1
                        ? Alignment.center
                        : Alignment(
                            -1 +
                                2 *
                                    (index.clamp(0, options.length - 1)) /
                                    (options.length - 1),
                            0,
                          ),
                    child: SizedBox(
                      width: width,
                      child: DecoratedBox(
                        decoration: ShapeDecoration(
                          color: palette.isDark
                              ? palette.surfaceRaised
                              : palette.surface,
                          shape: FluxRadius.shape(FluxRadius.xs + 3),
                          shadows: FluxElevation.card(palette),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (final option in options)
                        Expanded(
                          child: FluxPressable(
                            feedback: PressFeedback.none,
                            onTap: () => onChanged(option.$1),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: FluxMotion.duration(
                                  context,
                                  FluxMotion.quick,
                                ),
                                style: FluxType.label.copyWith(
                                  color: option.$1 == value
                                      ? palette.text
                                      : palette.textMuted,
                                ),
                                child: Text(option.$2),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The horizontally scrolling filter row used by Activity.
class FluxChipBar extends StatelessWidget {
  const FluxChipBar({super.key, required this.children, this.onClear});
  final List<Widget> children;

  /// Shown as a leading chip only when something is actually applied, so the
  /// row does not carry a permanent dead control.
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: FluxSpace.page),
      itemCount: children.length + (onClear == null ? 0 : 1),
      separatorBuilder: (context, index) => const SizedBox(width: FluxSpace.x2),
      itemBuilder: (context, index) {
        if (onClear != null && index == 0) {
          return FluxChip(
            label: 'Clear',
            icon: Icons.close_rounded,
            onTap: onClear,
          );
        }
        return children[index - (onClear == null ? 0 : 1)];
      },
    ),
  );
}
