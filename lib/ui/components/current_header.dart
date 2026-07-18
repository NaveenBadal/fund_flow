import 'package:flutter/material.dart';
import '../foundation/current_colors.dart';

class CurrentHeader extends StatelessWidget {
  const CurrentHeader({
    super.key,
    required this.title,
    required this.contextLine,
    this.actions = const [],
  });
  final String title;
  final String contextLine;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contextLine,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.current.muted),
              ),
              const SizedBox(height: 3),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class CurrentIconAction extends StatelessWidget {
  const CurrentIconAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(
          icon,
          size: 22,
          color: onPressed == null
              ? context.current.rule
              : context.current.muted,
        ),
      ),
    ),
  );
}
