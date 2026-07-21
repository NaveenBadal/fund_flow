import 'package:flutter/material.dart';

import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// The text input of the design system: label above, a raised well below,
/// focus shown by the border taking the accent. Errors appear under the well
/// in the expense colour rather than repainting the input, so a mistake is
/// pointed at without shouting.
class FlowField extends StatefulWidget {
  const FlowField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.error,
    this.helper,
    this.keyboardType,
    this.maxLines = 1,
    this.autofocus = false,
    this.obscureText = false,
    this.prefixText,
    this.prefixIcon,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final String? error;

  /// Guidance under the well; replaced by [error] when one is set.
  final String? helper;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool autofocus;
  final bool obscureText;
  final String? prefixText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<FlowField> createState() => _FlowFieldState();
}

class _FlowFieldState extends State<FlowField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    final hasError = (widget.error ?? '').isNotEmpty;
    final borderColor = hasError
        ? flow.expense
        : _focus.hasFocus
        ? flow.accent
        : flow.line;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: text.labelSmall?.copyWith(color: flow.inkSoft),
        ),
        const SizedBox(height: FlowSpace.xs),
        AnimatedContainer(
          duration: FlowMotion.respecting(context, FlowMotion.instant),
          decoration: BoxDecoration(
            color: flow.raised,
            borderRadius: FlowRadius.sm,
            border: Border.all(color: borderColor),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            keyboardType: widget.keyboardType,
            maxLines: widget.obscureText ? 1 : widget.maxLines,
            obscureText: widget.obscureText,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: text.bodyLarge,
            cursorColor: flow.accent,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: text.bodyLarge?.copyWith(color: flow.inkFaint),
              prefixText: widget.prefixText,
              prefixStyle: text.bodyLarge?.copyWith(color: flow.inkSoft),
              prefixIcon: widget.prefixIcon == null
                  ? null
                  : Icon(widget.prefixIcon, size: 18, color: flow.inkSoft),
              suffixIcon: widget.suffix,
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: FlowSpace.md,
                vertical: FlowSpace.md,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: FlowSpace.xs),
          Text(
            widget.error!,
            style: text.bodySmall?.copyWith(color: flow.expense),
          ),
        ] else if ((widget.helper ?? '').isNotEmpty) ...[
          const SizedBox(height: FlowSpace.xs),
          Text(
            widget.helper!,
            style: text.bodySmall?.copyWith(color: flow.inkSoft),
          ),
        ],
      ],
    );
  }
}
