import 'package:flutter/material.dart' show Icons, Switch;
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';
import 'flux_pressable.dart';
import 'flux_surface.dart';

/// A quiet section header. Caps and wide tracking, muted — it labels the
/// content below without competing with it.
class FluxSectionHeader extends StatelessWidget {
  const FluxSectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
    this.padding = const EdgeInsets.only(
      left: FluxSpace.page,
      right: FluxSpace.page,
      top: FluxSpace.x6,
      bottom: FluxSpace.x2,
    ),
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: FluxType.overline.copyWith(color: palette.textMuted),
            ),
          ),
          if (action != null)
            FluxPressable(
              onTap: onAction,
              feedback: PressFeedback.scale,
              child: Text(
                action!,
                style: FluxType.label.copyWith(color: palette.iris),
              ),
            ),
        ],
      ),
    );
  }
}

/// A grouped list: one card, rows inside it, hairlines between.
///
/// Grouping is what makes a settings tree scannable — a flat run of rows gives
/// the eye nothing to rest on.
class FluxGroup extends StatelessWidget {
  const FluxGroup({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.margin = const EdgeInsets.symmetric(horizontal: FluxSpace.page),
  });

  final List<Widget> children;
  final String? header;

  /// Explanatory text under the group. This is where an honest explanation of
  /// a permission or a trade-off belongs, rather than inside the row.
  final String? footer;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final rows = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) rows.add(const FluxLine(indent: FluxSpace.x4));
      rows.add(children[index]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A header carries its own top padding; a group without one still needs
        // separating from whatever came before, or the footer of the previous
        // group ends up touching this group's first row.
        if (header == null) const SizedBox(height: FluxSpace.x6),
        if (header != null)
          FluxSectionHeader(
            title: header!,
            padding: const EdgeInsets.only(
              left: FluxSpace.x4,
              right: FluxSpace.x4,
              top: FluxSpace.x6,
              bottom: FluxSpace.x2,
            ),
          ),
        Padding(
          padding: margin,
          child: FluxCard(
            padding: EdgeInsets.zero,
            clip: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.only(
              left: FluxSpace.page + FluxSpace.x1,
              right: FluxSpace.page + FluxSpace.x1,
              top: FluxSpace.x2,
            ),
            child: Text(
              footer!,
              style: FluxType.caption.copyWith(color: palette.textMuted),
            ),
          ),
      ],
    );
  }
}

/// One row in a [FluxGroup]: a label, an optional value, and one trailing
/// affordance.
class FluxRow extends StatelessWidget {
  const FluxRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.chevron = false,
    this.danger = false,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final String? value;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool chevron;
  final bool danger;
  final bool busy;

  /// A row whose trailing affordance is a switch.
  factory FluxRow.toggle({
    required String title,
    String? subtitle,
    IconData? icon,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) => FluxRow(
    title: title,
    subtitle: subtitle,
    icon: icon,
    onTap: onChanged == null ? null : () => onChanged(!value),
    trailing: Switch(value: value, onChanged: onChanged),
  );

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final tint = danger ? palette.danger : palette.text;
    return FluxPressable(
      onTap: onTap,
      feedback: PressFeedback.wash,
      haptic: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FluxSpace.tap + 8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FluxSpace.x4,
            vertical: FluxSpace.x3,
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: iconColor ?? palette.textMuted),
                const SizedBox(width: FluxSpace.x3),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: FluxType.body.copyWith(color: tint)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: FluxType.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: FluxSpace.x3),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 168),
                    child: Text(
                      value!,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluxType.body.copyWith(color: palette.textMuted),
                    ),
                  ),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(left: FluxSpace.x2),
                  child: SizedBox(width: 14, height: 14, child: _RowSpinner()),
                ),
              if (trailing != null)
                Padding(
                  padding: const EdgeInsets.only(left: FluxSpace.x2),
                  child: trailing!,
                ),
              if (chevron)
                Padding(
                  padding: const EdgeInsets.only(left: FluxSpace.x1),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: palette.textFaint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowSpinner extends StatefulWidget {
  const _RowSpinner();

  @override
  State<_RowSpinner> createState() => _RowSpinnerState();
}

class _RowSpinnerState extends State<_RowSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _controller,
    child: Icon(Icons.refresh_rounded, size: 14, color: context.flux.textMuted),
  );
}
