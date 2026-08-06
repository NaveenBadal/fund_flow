import 'package:flutter/material.dart';

import '../theme/ff_theme.dart';
import 'ff_controls.dart';
import 'ff_pressable.dart';

enum FFNoticeTone { neutral, attention, positive, problem }

/// A single thing worth saying, on its own card.
///
/// Notices are rare on purpose. Every one of them spends attention, so if two
/// want the same screen at once, one of them is not important enough.
class FFNotice extends StatelessWidget {
  const FFNotice({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.tone = FFNoticeTone.neutral,
    this.onTap,
    this.action,
    this.onAction,
    this.busy = false,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final FFNoticeTone tone;
  final VoidCallback? onTap;
  final String? action;
  final VoidCallback? onAction;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    // The glyph is a shape, so it takes the saturated fill rather than the
    // darkened text value, which reads as brown against a white card.
    final accent = switch (tone) {
      FFNoticeTone.neutral => c.tint,
      FFNoticeTone.attention => c.orangeFill,
      FFNoticeTone.positive => c.greenFill,
      FFNoticeTone.problem => c.redFill,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FFSpace.gutter,
        0,
        FFSpace.gutter,
        FFSpace.xl,
      ),
      child: FFPressable(
        onTap: onTap,
        highlight: true,
        radius: FFRadius.group,
        button: onTap != null,
        child: Container(
          padding: const EdgeInsets.all(FFSpace.lg),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(FFRadius.group),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: FFSpinner(size: 19),
                    )
                  else if (icon != null)
                    Icon(icon, size: 21, color: accent),
                  if (busy || icon != null) const SizedBox(width: FFSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: FFText.headline),
                        if (message != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            message!,
                            style: FFText.footnote.copyWith(
                              color: c.secondaryLabel,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onTap != null && action == null) ...[
                    const SizedBox(width: FFSpace.sm),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: c.tertiaryLabel,
                    ),
                  ],
                ],
              ),
              if (action != null) ...[
                const SizedBox(height: FFSpace.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FFButton(
                    action!,
                    onTap: onAction,
                    style: FFButtonStyle.tinted,
                    expand: false,
                    compact: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What a screen says when there is genuinely nothing on it.
///
/// Never an apology, and never a dead end: an empty state that cannot be acted
/// on is a bug report addressed to the wrong person.
class FFEmpty extends StatelessWidget {
  const FFEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.onAction,
    this.secondaryAction,
    this.onSecondaryAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;
  final String? secondaryAction;
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FFSpace.xxl,
        vertical: FFSpace.huge,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: c.quaternaryLabel),
          const SizedBox(height: FFSpace.lg),
          Text(title, textAlign: TextAlign.center, style: FFText.title3),
          if (message != null) ...[
            const SizedBox(height: FFSpace.sm),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: FFText.subhead.copyWith(color: c.secondaryLabel),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: FFSpace.xl),
            FFButton(action!, onTap: onAction, expand: false),
          ],
          if (secondaryAction != null) ...[
            const SizedBox(height: FFSpace.xs),
            FFButton(
              secondaryAction!,
              onTap: onSecondaryAction,
              style: FFButtonStyle.plain,
              expand: false,
            ),
          ],
        ],
      ),
    );
  }
}
