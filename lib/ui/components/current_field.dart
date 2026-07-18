import 'package:flutter/material.dart';

import '../foundation/current_colors.dart';

class CurrentField extends StatefulWidget {
  const CurrentField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.prefixIcon,
    this.suffix,
    this.enabled = true,
    this.obscureText = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.onSubmitted,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool enabled;
  final bool obscureText;
  final int minLines;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  @override
  State<CurrentField> createState() => _CurrentFieldState();
}

class _CurrentFieldState extends State<CurrentField> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.current;
    final error = widget.error != null;
    final border = error
        ? p.expense
        : _focus.hasFocus
        ? p.intelligence
        : p.rule;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: widget.enabled ? 1 : .52,
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 10, 10, 9),
        decoration: BoxDecoration(
          color: widget.enabled ? p.surface : p.subtle,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: _focus.hasFocus ? 1.5 : 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.prefixIcon != null) ...[
              Icon(widget.prefixIcon, size: 21, color: p.muted),
              const SizedBox(width: 11),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.label != null)
                    Text(
                      widget.label!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: error ? p.expense : p.muted,
                      ),
                    ),
                  TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    enabled: widget.enabled,
                    obscureText: widget.obscureText,
                    minLines: widget.minLines,
                    maxLines: widget.maxLines,
                    keyboardType: widget.keyboardType,
                    onSubmitted: widget.onSubmitted,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration.collapsed(
                      hintText: widget.hint,
                      hintStyle: TextStyle(color: p.muted),
                    ),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (widget.error != null || widget.helper != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.error ?? widget.helper!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: error ? p.expense : p.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.suffix != null) ...[
              const SizedBox(width: 8),
              widget.suffix!,
            ],
          ],
        ),
      ),
    );
  }
}
