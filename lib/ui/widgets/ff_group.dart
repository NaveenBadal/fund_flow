import 'package:flutter/material.dart';

import '../theme/ff_theme.dart';
import 'ff_pressable.dart';

/// An inset group of rows.
///
/// The grouping is the card; the card is not decoration. Related settings sit
/// on one rounded field with hairlines between them, so the eye reads "these
/// belong together" without a border, a shadow or a heading having to say it.
class FFGroup extends StatelessWidget {
  const FFGroup({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.separatorIndent = FFSpace.lg,
    this.margin,
  });

  final List<Widget> children;

  /// Quiet line above the card.
  final String? header;

  /// Quiet line below it, for the sentence that explains a switch.
  final String? footer;

  final double separatorIndent;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(FFSeparator(indent: separatorIndent));
      }
    }
    return Padding(
      padding:
          margin ??
          const EdgeInsets.fromLTRB(
            FFSpace.gutter,
            0,
            FFSpace.gutter,
            FFSpace.xl,
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFSpace.lg,
                0,
                FFSpace.lg,
                FFSpace.sm,
              ),
              child: Text(
                header!,
                style: FFText.footnote.copyWith(color: c.secondaryLabel),
              ),
            ),
          ClipRRect(
            borderRadius: BorderRadius.circular(FFRadius.group),
            child: ColoredBox(
              color: c.card,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFSpace.lg,
                FFSpace.sm,
                FFSpace.lg,
                0,
              ),
              child: Text(
                footer!,
                style: FFText.footnote.copyWith(color: c.secondaryLabel),
              ),
            ),
        ],
      ),
    );
  }
}

/// One row in a group.
///
/// Everything optional so a single class covers a link, a value, a toggle and
/// a plain statement — which is what keeps forty screens looking like one app.
class FFRow extends StatelessWidget {
  const FFRow({
    super.key,
    required this.title,
    this.subtitle,
    this.value,
    this.icon,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.chevron,
    this.destructive = false,
    this.tinted = false,
    this.centered = false,
    this.minHeight = 44,
  });

  final String title;
  final String? subtitle;

  /// The grey answer on the right — "INR", "Connected".
  final String? value;

  final IconData? icon;

  /// Filled rounded glyph behind the icon, iOS Settings style.
  final Color? iconColor;

  final VoidCallback? onTap;
  final Widget? trailing;

  /// Defaults to showing when [onTap] is set and nothing else is trailing.
  final bool? chevron;

  final bool destructive;

  /// Tint the title, for an action that is not destructive.
  final bool tinted;

  /// Centre the title, for a lone action in its own card.
  final bool centered;

  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final showChevron = chevron ?? (onTap != null && trailing == null);
    final color = destructive
        ? c.red
        : tinted
        ? c.tint
        : c.label;

    final label = Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: FFText.body.copyWith(color: color)),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: FFText.footnote.copyWith(color: c.secondaryLabel),
          ),
        ],
      ],
    );

    return FFPressable(
      onTap: onTap,
      highlight: true,
      button: onTap != null,
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.fromLTRB(FFSpace.lg, 11, FFSpace.lg, 11),
        child: Row(
          children: [
            if (icon != null) ...[
              _Glyph(icon: icon!, color: iconColor ?? c.tint),
              const SizedBox(width: FFSpace.md),
            ],
            centered ? Expanded(child: Center(child: label)) : Expanded(child: label),
            if (value != null) ...[
              const SizedBox(width: FFSpace.md),
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: FFText.body.copyWith(color: c.secondaryLabel),
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: FFSpace.md),
              trailing!,
            ],
            if (showChevron) ...[
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: c.tertiaryLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  const _Glyph({required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 29,
    height: 29,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Icon(icon, size: 17, color: Colors.white),
  );
}

/// A heading between groups, for pages with more than one idea on them.
class FFHeading extends StatelessWidget {
  const FFHeading(this.text, {super.key, this.trailing, this.onTrailing});

  final String text;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FFSpace.gutter,
      FFSpace.sm,
      FFSpace.gutter,
      FFSpace.md,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(text, style: FFText.title3)),
        if (trailing != null)
          FFPressable(
            onTap: onTrailing,
            child: Text(
              trailing!,
              style: FFText.subhead.copyWith(color: context.ff.tint),
            ),
          ),
      ],
    ),
  );
}
