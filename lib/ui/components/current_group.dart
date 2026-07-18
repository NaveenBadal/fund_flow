import 'package:flutter/material.dart';
import '../foundation/current_colors.dart';

class CurrentGroup extends StatelessWidget {
  const CurrentGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.current.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.current.rule),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1)
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: context.current.rule,
            ),
        ],
      ],
    ),
  );
}

class CurrentRow extends StatelessWidget {
  const CurrentRow({
    super.key,
    required this.title,
    this.detail,
    this.leading,
    this.trailing,
    this.onTap,
    this.signal,
  });
  final String title;
  final String? detail;
  final IconData? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? signal;
  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 68),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        child: Row(
          children: [
            if (signal != null) ...[
              Container(
                width: 3,
                height: 30,
                decoration: BoxDecoration(
                  color: signal,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (leading != null) ...[
              Icon(leading, size: 21, color: context.current.muted),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (detail != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.current.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ] else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: context.current.muted),
          ],
        ),
      ),
    );
    if (onTap == null) return content;
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class CurrentSectionTitle extends StatelessWidget {
  const CurrentSectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 26, 2, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?action,
      ],
    ),
  );
}
