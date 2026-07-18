import 'package:flutter/material.dart';

import '../foundation/flow_color.dart';
import '../primitives/coordinate_label.dart';
import '../primitives/cut_surface.dart';
import '../primitives/loom_mark.dart';

class SystemMasthead extends StatelessWidget {
  const SystemMasthead({super.key, required this.aiOnline});

  final bool aiOnline;

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 15, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    CoordinateLabel('SYSTEM / LOCAL CONTROL'),
                    SizedBox(height: 3),
                    Text(
                      'CONTROL MAP',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                    ),
                  ],
                ),
              ),
              LoomMark(
                size: 42,
                state: aiOnline ? LoomState.ready : LoomState.offline,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: aiOnline ? 54 : 18,
                height: 2,
                color: aiOnline ? FlowColor.proof : FlowColor.amber,
              ),
              Expanded(
                child: SizedBox(
                  height: 1,
                  child: ColoredBox(color: FlowColor.rule(context)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class SystemSectionLabel extends StatelessWidget {
  const SystemSectionLabel(this.coordinate, {super.key});
  final String coordinate;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 22, 0, 8),
    child: CoordinateLabel(coordinate),
  );
}

class SystemNode extends StatelessWidget {
  const SystemNode({
    super.key,
    required this.code,
    required this.title,
    required this.detail,
    this.signal = NodeSignal.neutral,
    this.onTap,
    this.control,
  });

  final String code;
  final String title;
  final String detail;
  final NodeSignal signal;
  final VoidCallback? onTap;
  final Widget? control;

  @override
  Widget build(BuildContext context) {
    final color = switch (signal) {
      NodeSignal.live => FlowColor.mint,
      NodeSignal.attention => FlowColor.amber,
      NodeSignal.private => FlowColor.proof,
      NodeSignal.neutral => FlowColor.quiet(context),
    };
    final content = CutSurface(
      cut: 10,
      color: FlowColor.plane(context),
      accent: color.withValues(alpha: .55),
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 8, height: 8, color: color),
                const SizedBox(height: 7),
                Text(
                  code,
                  style: TextStyle(
                    color: FlowColor.quiet(context),
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: FlowColor.content(context),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FlowColor.quiet(context),
                  ),
                ),
              ],
            ),
          ),
          if (control != null) ...[const SizedBox(width: 10), control!],
          if (control == null && onTap != null)
            Text(
              'OPEN →',
              style: TextStyle(
                color: color,
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

enum NodeSignal { neutral, live, attention, private }

class BinaryRail extends StatelessWidget {
  const BinaryRail({
    super.key,
    required this.value,
    required this.onChanged,
    this.onLabel = 'ON',
    this.offLabel = 'OFF',
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String onLabel;
  final String offLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: '$onLabel / $offLabel',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _BinaryPort(
          label: offLabel,
          selected: !value,
          onTap: () => onChanged(false),
        ),
        _BinaryPort(
          label: onLabel,
          selected: value,
          onTap: () => onChanged(true),
        ),
      ],
    ),
  );
}

class _BinaryPort extends StatelessWidget {
  const _BinaryPort({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
      alignment: Alignment.center,
      color: selected ? FlowColor.loom : FlowColor.raised(context),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : FlowColor.quiet(context),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
      ),
    ),
  );
}

class StepRail extends StatelessWidget {
  const StepRail({
    super.key,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _StepPort(label: '−', onTap: onDecrease),
      Container(
        constraints: const BoxConstraints(minWidth: 58, minHeight: 42),
        alignment: Alignment.center,
        color: FlowColor.raised(context),
        child: Text(
          value,
          style: TextStyle(
            color: FlowColor.proof,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      _StepPort(label: '+', onTap: onIncrease),
    ],
  );
}

class _StepPort extends StatelessWidget {
  const _StepPort({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      color: FlowColor.plane(context),
      child: Text(
        label,
        style: TextStyle(
          color: FlowColor.content(context),
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}
