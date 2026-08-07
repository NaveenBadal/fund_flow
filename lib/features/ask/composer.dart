import 'package:flutter/material.dart'
    show Icons, InputBorder, InputDecoration, TextField;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, LogicalKeyboardKey, TextInputAction;
import 'package:flutter/widgets.dart';

import '../../agent/agent_presentation.dart';
import '../../design/flux.dart';
import 'answer_parts.dart';

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
    this.safeArea = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final bool busy;

  /// Whether to pad past the gesture inset. False while the keyboard is up,
  /// which occupies that space itself.
  final bool safeArea;

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
    // Enter sends, shift-enter breaks the line. The soft keyboard's return key
    // stays a newline — `TextInputAction.newline` below — so this only changes
    // behaviour for a real keyboard, where having no way to send without
    // reaching for the screen is the kind of thing that gets noticed once and
    // then resented. Handled on the field's own node so it runs ahead of the
    // default text-editing shortcuts rather than after them.
    _focus.onKeyEvent = (node, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey != LogicalKeyboardKey.enter &&
          event.logicalKey != LogicalKeyboardKey.numpadEnter) {
        return KeyEventResult.ignored;
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      if (widget.controller.text.trim().isEmpty || widget.busy) {
        return KeyEventResult.ignored;
      }
      // Off the key handler, which must return synchronously — the input
      // dispatcher gives it a few seconds before declaring the app dead, and
      // sending kicks off a database write and a scroll animation.
      Future.microtask(() => _send(keepFocus: true));
      return KeyEventResult.handled;
    };
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Sends what is typed.
  ///
  /// [keepFocus] is set when the send came from a keyboard: dropping focus
  /// there would make someone click back into the field for every question,
  /// whereas after a tap on the button dismissing the soft keyboard is exactly
  /// what is wanted — it is covering the answer.
  void _send({bool keepFocus = false}) {
    final text = widget.controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    widget.controller.clear();
    if (!keepFocus) _focus.unfocus();
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
        bottom: widget.safeArea,
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
/// sweeping along the top edge, and the answer appearing beneath it as it is
/// written.
///
/// The stage text comes from the agent's own tool loop rather than a generic
/// "Thinking…", because a person waiting eight seconds deserves to know whether
/// it is reading their ledger or composing an answer.
class WorkingIndicator extends StatelessWidget {
  const WorkingIndicator({
    super.key,
    required this.stage,
    this.draft,
    this.parts = const [],
  });
  final String stage;
  final String? draft;

  /// Parts of the answer that have finished arriving.
  final List<AgentPart> parts;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    // Once the answer starts arriving it is the thing to look at, and the
    // sweeping bar above a real conclusion reads as the app still deciding
    // when it has already decided. The stage line stays as the marker that
    // there is more to come.
    if (parts.isEmpty) {
      return _Sweep(stage: stage, draft: draft);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < parts.length; index++) ...[
          if (index > 0) const SizedBox(height: FluxSpace.x4),
          // Follow-ups cannot be tapped until the answer is delivered and the
          // real message takes over a frame later; the wiring belongs to that
          // message, not to this preview of it.
          AnswerPartView(part: parts[index], onFollowUp: (_) {}),
        ],
        const SizedBox(height: FluxSpace.x4),
        Row(
          children: [
            _Dot(palette: palette),
            const SizedBox(width: FluxSpace.x2),
            Text(
              stage,
              style: FluxType.caption.copyWith(color: palette.textFaint),
            ),
          ],
        ),
      ],
    );
  }
}

/// The pulsing mark that says the answer is still being written.
class _Dot extends StatefulWidget {
  const _Dot({required this.palette});
  final FluxPalette palette;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, _) => Opacity(
      opacity: 0.35 + 0.65 * _controller.value,
      child: Container(
        width: 6,
        height: 6,
        decoration: ShapeDecoration(
          gradient: FluxPalette.ai,
          shape: const CircleBorder(),
        ),
      ),
    ),
  );
}

class _Sweep extends StatefulWidget {
  const _Sweep({required this.stage, this.draft});
  final String stage;
  final String? draft;

  @override
  State<_Sweep> createState() => _WorkingIndicatorState();
}

class _WorkingIndicatorState extends State<_Sweep>
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
