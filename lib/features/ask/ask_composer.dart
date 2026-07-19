import 'package:flutter/material.dart';

import '../../ui/foundation/current_colors.dart';

/// Where the question gets written.
///
/// Built separately from [CurrentField] because a composer is not a form
/// field. A form field carries a label, a helper and an error because it is
/// one of several inputs being filled in correctly. A composer is a single
/// destination on the screen and should read as an invitation to type.
///
/// The helper line in particular was wrong here: a privacy reassurance is
/// needed once, not on every frame for the life of the app, and it was
/// repeating a sentence the empty state already showed directly above it.
class AskComposer extends StatefulWidget {
  const AskComposer({
    super.key,
    required this.controller,
    required this.connected,
    required this.busy,
    required this.onSubmit,
    required this.onConnect,
  });

  final TextEditingController controller;
  final bool connected;

  /// True while an answer is being produced; sending again is refused until
  /// it finishes.
  final bool busy;

  final ValueChanged<String> onSubmit;
  final VoidCallback onConnect;

  @override
  State<AskComposer> createState() => _AskComposerState();
}

class _AskComposerState extends State<AskComposer> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
    widget.controller.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_refresh);
    widget.controller.removeListener(_refresh);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.current;

    // Disconnected, this is not an input at all. Rendering a dead text field
    // invites typing into something that cannot accept it; a button says what
    // the next step actually is.
    if (!widget.connected) {
      return Semantics(
        button: true,
        label: 'Connect intelligence to start asking',
        excludeSemantics: true,
        child: InkWell(
          onTap: widget.onConnect,
          borderRadius: BorderRadius.circular(26),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            decoration: BoxDecoration(
              color: palette.subtle,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: palette.rule),
            ),
            child: Row(
              children: [
                Icon(Icons.link_rounded, size: 19, color: palette.intelligence),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Connect intelligence to start asking',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: palette.intelligence,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final hasText = widget.controller.text.trim().isNotEmpty;
    final canSend = hasText && !widget.busy;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: _focus.hasFocus ? palette.intelligence : palette.rule,
          width: _focus.hasFocus ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: !widget.busy,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) {
                  if (canSend) widget.onSubmit(value);
                },
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration.collapsed(
                  hintText: widget.busy
                      ? 'Working on your answer…'
                      : 'Ask about your money',
                  hintStyle: TextStyle(color: palette.muted),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SendButton(
            enabled: canSend,
            onPressed: () => widget.onSubmit(widget.controller.text),
          ),
        ],
      ),
    );
  }
}

/// Fills once there is something to send.
///
/// The previous ghosted arrow looked identical whether or not it would do
/// anything, so the only way to learn it was inert was to press it.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.current;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send question',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: enabled ? palette.intelligence : palette.subtle,
          shape: BoxShape.circle,
        ),
        child: IconButton(
          onPressed: enabled ? onPressed : null,
          padding: EdgeInsets.zero,
          iconSize: 19,
          icon: Icon(
            Icons.arrow_upward_rounded,
            color: enabled ? Colors.white : palette.muted,
          ),
        ),
      ),
    );
  }
}
