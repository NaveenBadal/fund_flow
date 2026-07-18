import 'package:flutter/material.dart';

import '../../theme/app_tokens.dart';

/// Shared adaptive page frame for secondary Flow tasks.
class FlowScaffold extends StatelessWidget {
  const FlowScaffold({
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
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: floatingActionButton,
    body: CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverAppBar(
          pinned: true,
          title: Text(title),
          actions: actions,
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
        ),
        if (eyebrow != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.page,
                AppSpacing.sm,
                AppSpacing.page,
                AppSpacing.section,
              ),
              child: Text(
                eyebrow!,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.narrative)),
      ],
    ),
  );
}

/// Complete, non-technical loading/empty/restricted/error state.
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoint.contentMax),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.region),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: scheme.primaryContainer,
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _friendlyMessage(message),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.section),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _friendlyMessage(String raw) {
    final technical =
        raw.contains('Exception') ||
        raw.contains('DatabaseException') ||
        raw.contains('SocketException') ||
        raw.contains('StackTrace');
    return technical
        ? 'Something interrupted this view. Your data is safe; try again.'
        : raw;
  }
}
