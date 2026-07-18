import 'package:flutter/material.dart';

import '../../flow_os/foundation/flow_color.dart';
import '../../flow_os/primitives/coordinate_label.dart';
import '../../flow_os/primitives/cut_surface.dart';
import '../../flow_os/primitives/loom_mark.dart';
import '../../theme/app_tokens.dart';

/// Adaptive frame for secondary evidence and control workspaces. It shares the
/// Quiet Current composition for secondary local tools.
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
    body: ColoredBox(
      color: FlowColor.canvas(context),
      child: SafeArea(
        bottom: false,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LoomMark(size: 38),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CoordinateLabel('Auxiliary / local tool'),
                              const SizedBox(height: 6),
                              Text(
                                title.toUpperCase(),
                                maxLines: 2,
                                overflow: TextOverflow.fade,
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: FlowColor.content(context),
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: .3,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        ...actions,
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(width: 74, height: 3, color: FlowColor.proof),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: FlowColor.rule(context),
                          ),
                        ),
                      ],
                    ),
                    if (eyebrow != null) ...[
                      const SizedBox(height: 15),
                      Text(
                        eyebrow!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: FlowColor.quiet(context),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ...slivers,
            const SliverToBoxAdapter(
              child: SizedBox(height: AppSpacing.narrative),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Empty, loading, restricted, and error states use one proof report rather
/// than spinner/card conventions. The Loom Mark is static and schedules no
/// idle frames.
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
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppBreakpoint.contentMax),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.region),
        child: CutSurface(
          accent: FlowColor.amber,
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const LoomMark(size: 42, state: LoomState.review),
                  const SizedBox(width: 12),
                  Icon(icon, color: FlowColor.amber, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: CoordinateLabel(
                      'Field state / attention',
                      color: FlowColor.amber,
                      line: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: FlowColor.content(context),
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _friendlyMessage(message),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: FlowColor.quiet(context),
                  height: 1.45,
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
    ),
  );

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
