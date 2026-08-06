import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ff_theme.dart';
import 'ff_pressable.dart';

enum FFButtonStyle {
  /// The one thing to do here.
  filled,

  /// Also worth doing, but not the point of the screen.
  tinted,

  /// A link that happens to be button-shaped.
  plain,

  /// Removes something.
  destructive,
}

class FFButton extends StatelessWidget {
  const FFButton(
    this.label, {
    super.key,
    required this.onTap,
    this.style = FFButtonStyle.filled,
    this.icon,
    this.busy = false,
    this.expand = true,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onTap;
  final FFButtonStyle style;
  final IconData? icon;
  final bool busy;
  final bool expand;

  /// Inline height, for buttons that sit beside text.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final enabled = onTap != null && !busy;

    final (Color background, Color foreground) = switch (style) {
      FFButtonStyle.filled => (c.tint, c.onTint),
      FFButtonStyle.tinted => (c.tint.withValues(alpha: .14), c.tint),
      FFButtonStyle.plain => (Colors.transparent, c.tint),
      FFButtonStyle.destructive => (c.red.withValues(alpha: .14), c.red),
    };

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (busy)
          SizedBox.square(
            dimension: 17,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        else if (icon != null)
          Icon(icon, size: 19, color: foreground),
        if (busy || icon != null) const SizedBox(width: FFSpace.sm),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FFText.headline.copyWith(
              color: enabled ? foreground : foreground.withValues(alpha: .4),
            ),
          ),
        ),
      ],
    );

    return FFPressable(
      onTap: enabled
          ? () {
              HapticFeedback.selectionClick();
              onTap!();
            }
          : null,
      semanticLabel: label,
      child: Container(
        height: compact ? 36 : 50,
        padding: EdgeInsets.symmetric(horizontal: compact ? 14 : FFSpace.lg),
        decoration: BoxDecoration(
          color: enabled ? background : background.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(
            compact ? FFRadius.pill : FFRadius.control,
          ),
        ),
        child: Center(child: content),
      ),
    );
  }
}

class FFSwitch extends StatelessWidget {
  const FFSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => CupertinoSwitch(
    value: value,
    // Green, not the app tint. A switch reports a state rather than offering
    // a destination, and the whole platform reads green as "on".
    activeTrackColor: context.ff.green,
    inactiveTrackColor: context.ff.fill,
    onChanged: onChanged,
  );
}

/// A segmented control: two to four peers, one of which is always chosen.
class FFSegmented<T> extends StatelessWidget {
  const FFSegmented({
    super.key,
    required this.value,
    required this.segments,
    required this.onChanged,
  });

  final T value;
  final List<(T, String)> segments;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final index = segments.indexWhere((s) => s.$1 == value);
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 4) / segments.length;
        return Container(
          height: 32,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: c.secondaryFill,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: Duration(milliseconds: context.ffStill ? 0 : 220),
                curve: Curves.easeOutCubic,
                left: width * (index < 0 ? 0 : index),
                top: 0,
                bottom: 0,
                width: width,
                child: Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: context.ffDark ? .4 : .12,
                        ),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final segment in segments)
                    Expanded(
                      child: FFPressable(
                        selected: segment.$1 == value,
                        onTap: () {
                          if (segment.$1 == value) return;
                          HapticFeedback.selectionClick();
                          onChanged(segment.$1);
                        },
                        child: Center(
                          child: Text(
                            segment.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FFText.footnote.copyWith(
                              fontWeight: segment.$1 == value
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: c.label,
                            ),
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
    );
  }
}

/// A field on a fill, with no border and no floating label.
///
/// The label lives above the field or in the row beside it, never inside it —
/// a label that leaps to the top-left on focus is motion spent explaining the
/// control instead of the content.
class FFField extends StatelessWidget {
  const FFField({
    super.key,
    required this.controller,
    this.placeholder,
    this.keyboardType,
    this.obscure = false,
    this.autofocus = false,
    this.minLines,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.style,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.focusNode,
  });

  final TextEditingController controller;
  final String? placeholder;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool autofocus;
  final int? minLines;
  final int? maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final TextStyle? style;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: FFSpace.md, vertical: 6),
      decoration: BoxDecoration(
        color: c.secondaryFill,
        borderRadius: BorderRadius.circular(FFRadius.control),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (prefix != null) ...[prefix!, const SizedBox(width: FFSpace.sm)],
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autofocus: autofocus,
              obscureText: obscure,
              autocorrect: !obscure,
              enableSuggestions: !obscure,
              keyboardType: keyboardType,
              minLines: minLines,
              maxLines: maxLines,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              inputFormatters: inputFormatters,
              textCapitalization: textCapitalization,
              textInputAction: textInputAction,
              cursorColor: c.tint,
              cursorRadius: const Radius.circular(1),
              cursorWidth: 2,
              style: (style ?? FFText.body).copyWith(color: c.label),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: placeholder,
                hintStyle: (style ?? FFText.body).copyWith(
                  color: c.tertiaryLabel,
                ),
              ),
            ),
          ),
          if (suffix != null) ...[const SizedBox(width: FFSpace.sm), suffix!],
        ],
      ),
    );
  }
}

class FFSearchField extends StatelessWidget {
  const FFSearchField({
    super.key,
    required this.controller,
    this.placeholder = 'Search',
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return FFField(
      controller: controller,
      placeholder: placeholder,
      autofocus: autofocus,
      onChanged: onChanged,
      style: FFText.callout,
      prefix: Icon(Icons.search_rounded, size: 19, color: c.tertiaryLabel),
      suffix: controller.text.isEmpty
          ? null
          : FFPressable(
              onTap: () {
                controller.clear();
                onChanged?.call('');
              },
              semanticLabel: 'Clear search',
              child: Icon(
                Icons.cancel_rounded,
                size: 17,
                color: c.tertiaryLabel,
              ),
            ),
    );
  }
}

/// A capsule filter. Selected means tinted, never merely darker.
class FFChip extends StatelessWidget {
  const FFChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return FFPressable(
      onTap: onTap,
      selected: selected,
      child: AnimatedContainer(
        duration: Duration(milliseconds: context.ffStill ? 0 : 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.tint : c.secondaryFill,
          borderRadius: BorderRadius.circular(FFRadius.pill),
        ),
        child: Text(
          label,
          style: FFText.footnote.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? c.onTint : c.label,
          ),
        ),
      ),
    );
  }
}

/// The spinner. Small, tinted grey, never a branded flourish.
class FFSpinner extends StatelessWidget {
  const FFSpinner({super.key, this.size = 20, this.color});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: size / 10,
      strokeCap: StrokeCap.round,
      color: color ?? context.ff.tertiaryLabel,
    ),
  );
}
