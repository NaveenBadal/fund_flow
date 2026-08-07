import 'package:flutter/material.dart'
    show Icons, InputBorder, InputDecoration, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// A labelled text field.
class FluxField extends StatelessWidget {
  const FluxField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.maxLines = 1,
    this.prefix,
    this.suffix,
    this.textAlign = TextAlign.start,
    this.style,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final int maxLines;
  final Widget? prefix;
  final Widget? suffix;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: FluxType.label.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: FluxSpace.x2),
        ],
        _FieldShell(
          error: error != null,
          child: Row(
            children: [
              if (prefix != null) ...[
                prefix!,
                const SizedBox(width: FluxSpace.x2),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  autofocus: autofocus,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  maxLines: maxLines,
                  minLines: 1,
                  textAlign: textAlign,
                  cursorColor: palette.iris,
                  style: (style ?? FluxType.body).copyWith(color: palette.text),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: hint,
                    hintStyle: (style ?? FluxType.body).copyWith(
                      color: palette.textFaint,
                    ),
                  ),
                ),
              ),
              if (suffix != null) ...[
                const SizedBox(width: FluxSpace.x2),
                suffix!,
              ],
            ],
          ),
        ),
        if (error != null || helper != null) ...[
          const SizedBox(height: FluxSpace.x2),
          Text(
            error ?? helper!,
            style: FluxType.caption.copyWith(
              color: error != null ? palette.danger : palette.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// The container every input shares: a filled surface that gains an iris edge
/// on focus, so which field is live is never in doubt.
class _FieldShell extends StatefulWidget {
  const _FieldShell({required this.child, this.error = false});
  final Widget child;
  final bool error;

  @override
  State<_FieldShell> createState() => _FieldShellState();
}

class _FieldShellState extends State<_FieldShell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final edge = widget.error
        ? palette.danger
        : (_focused ? palette.iris : palette.line);
    return Focus(
      onFocusChange: (value) => setState(() => _focused = value),
      canRequestFocus: false,
      child: AnimatedContainer(
        duration: FluxMotion.duration(context, FluxMotion.quick),
        curve: FluxMotion.emphasized,
        padding: const EdgeInsets.symmetric(
          horizontal: FluxSpace.x4,
          vertical: 13,
        ),
        decoration: ShapeDecoration(
          color: palette.isDark ? palette.surface : palette.surfaceHighest,
          shape: FluxRadius.shape(
            FluxRadius.sm,
            side: BorderSide(color: edge, width: _focused ? 1.5 : 1),
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// The ledger's search field.
class FluxSearchField extends StatelessWidget {
  const FluxSearchField({
    super.key,
    required this.controller,
    this.hint = 'Search',
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => FluxField(
        controller: controller,
        hint: hint,
        onChanged: onChanged,
        prefix: Icon(Icons.search_rounded, size: 18, color: palette.textFaint),
        suffix: value.text.isEmpty
            ? null
            : FluxPressableClear(
                onTap: () {
                  controller.clear();
                  onChanged?.call('');
                },
              ),
      ),
    );
  }
}

/// The clear affordance inside a field.
///
/// Deliberately not [FluxIconButton]: that is sized to the 44px minimum target
/// and would make the field it sits in 70px tall. The gesture box is widened
/// past the glyph instead, which keeps the field its own height while staying
/// comfortably hittable.
class FluxPressableClear extends StatelessWidget {
  const FluxPressableClear({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: 26,
      height: 26,
      child: Center(
        child: Icon(
          Icons.cancel_rounded,
          size: 17,
          color: context.flux.textFaint,
        ),
      ),
    ),
  );
}
