import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

class CommandScaffold extends StatelessWidget {
  const CommandScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.eyebrow,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final List<Widget> slivers;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          Positioned(
            left: -100,
            top: -130,
            child: IgnorePointer(
              child: Container(
                width: 310,
                height: 310,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      scheme.primary.withValues(alpha: 0.12),
                      scheme.primary.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverAppBar.large(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                titleSpacing: 20,
                actions: actions,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (eyebrow != null)
                      Text(
                        eyebrow!.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                    Text(title),
                  ],
                ),
              ),
              ...slivers,
              const SliverToBoxAdapter(child: SizedBox(height: 130)),
            ],
          ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.caption,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent),
          const Spacer(),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class StatePanel extends StatelessWidget {
  const StatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(36),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}
