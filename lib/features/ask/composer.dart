import 'package:flutter/material.dart'
    show Icons, InputBorder, InputDecoration, TextField;
import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';

import '../../design/flux.dart';

/// The composer.
///
/// The one control in the app that carries the AI gradient, and only on focus:
/// it marks the single place where an answer is generated rather than looked up.
/// The send button morphs into stop while a run is in flight, so the same thumb
/// position both starts and cancels.
class AskComposer extends StatefulWidget {
  const AskComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onStop,
    required this.busy,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final bool busy;

  @override
  State<AskComposer> createState() => _AskComposerState();
}

class _AskComposerState extends State<AskComposer> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = widget.controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    widget.controller.clear();
    _focus.unfocus();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;

    return FluxGlass(
      opacity: 0.86,
      border: Border(top: BorderSide(color: palette.line, width: 1)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FluxSpace.x4,
            FluxSpace.x3,
            FluxSpace.x3,
            FluxSpace.x3,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: FluxMotion.duration(context, FluxMotion.quick),
                  curve: FluxMotion.emphasized,
                  padding: const EdgeInsets.symmetric(
                    horizontal: FluxSpace.x4,
                    vertical: 11,
                  ),
                  decoration: ShapeDecoration(
                    color: palette.isDark
                        ? palette.surface
                        : palette.surfaceHighest,
                    shape: StadiumBorder(
                      side: BorderSide(
                        // The gradient cannot be a border colour, so focus uses
                        // its opening hue — the same signal at a smaller cost
                        // than a shader-painted outline on every keystroke.
                        color: _focused ? palette.iris : palette.line,
                        width: _focused ? 1.5 : 1,
                      ),
                    ),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    cursorColor: palette.iris,
                    style: FluxType.body.copyWith(color: palette.text),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: 'Ask about your money',
                      hintStyle: FluxType.body.copyWith(
                        color: palette.textFaint,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: FluxSpace.x2),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) {
                  final ready = value.text.trim().isNotEmpty;
                  return FluxPressable(
                    onTap: widget.busy ? widget.onStop : (ready ? _send : null),
                    child: AnimatedContainer(
                      duration: FluxMotion.duration(context, FluxMotion.quick),
                      width: 44,
                      height: 44,
                      decoration: ShapeDecoration(
                        gradient: widget.busy || ready ? FluxPalette.ai : null,
                        color: widget.busy || ready
                            ? null
                            : palette.surfaceHighest,
                        shape: const CircleBorder(),
                      ),
                      child: Center(
                        child: Icon(
                          widget.busy
                              ? Icons.stop_rounded
                              : Icons.arrow_upward_rounded,
                          size: 20,
                          color: widget.busy || ready
                              ? const Color(0xFFFFFFFF)
                              : palette.textFaint,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The live "working" line: the stage the run is actually in, with a gradient
/// sweeping along the top edge.
///
/// The stage text comes from the agent's own tool loop rather than a generic
/// "Thinking…", because a person waiting eight seconds deserves to know whether
/// it is reading their ledger or composing an answer.
class WorkingIndicator extends StatefulWidget {
  const WorkingIndicator({super.key, required this.stage, this.draft});
  final String stage;
  final String? draft;

  @override
  State<WorkingIndicator> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<WorkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: SizedBox(
            height: 2,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: palette.line)),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => FractionallySizedBox(
                    widthFactor: 0.4,
                    alignment: Alignment(-1 + 2 * _controller.value * 1.5, 0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: FluxPalette.ai),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: FluxSpace.x3),
        Text(
          widget.stage,
          style: FluxType.label.copyWith(color: palette.textMuted),
        ),
        if (widget.draft != null && widget.draft!.trim().isNotEmpty) ...[
          const SizedBox(height: FluxSpace.x2),
          Text(
            widget.draft!.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: FluxType.body.copyWith(color: palette.textFaint),
          ),
        ],
      ],
    );
  }
}
