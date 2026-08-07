import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';
import 'flux_button.dart';
import 'flux_surface.dart';

/// An empty state that says what is missing and offers the one action that
/// would fix it.
///
/// A bare "Nothing here" is a dead end; every empty state in Flux carries a
/// way out, because the state someone hits first is usually the empty one.
class FluxEmpty extends StatelessWidget {
  const FluxEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: FluxSpace.x8,
        vertical: compact ? FluxSpace.x8 : FluxSpace.x16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: ShapeDecoration(
              color: palette.surfaceHighest,
              shape: const CircleBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.all(FluxSpace.x4),
              child: Icon(icon, size: 24, color: palette.textFaint),
            ),
          ),
          const SizedBox(height: FluxSpace.x4),
          Text(
            title,
            textAlign: TextAlign.center,
            style: FluxType.subtitle.copyWith(color: palette.text),
          ),
          if (message != null) ...[
            const SizedBox(height: FluxSpace.x2),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: FluxType.body.copyWith(color: palette.textMuted),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: FluxSpace.x5),
            FluxButton(
              label: actionLabel!,
              onPressed: onAction,
              expand: false,
              compact: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// A shimmering placeholder block.
///
/// Skeletons rather than a spinner: a spinner tells someone to wait, a skeleton
/// tells them what is about to arrive and where, so the screen does not appear
/// to jump when it does.
class FluxSkeleton extends StatefulWidget {
  const FluxSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = FluxRadius.xs,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<FluxSkeleton> createState() => _FluxSkeletonState();
}

class _FluxSkeletonState extends State<FluxSkeleton>
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
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return DecoratedBox(
            decoration: ShapeDecoration(
              shape: FluxRadius.shape(widget.radius),
              gradient: LinearGradient(
                begin: Alignment(-1 - 2 * (1 - t), 0),
                end: Alignment(1 - 2 * (1 - t), 0),
                colors: [
                  palette.surfaceHighest,
                  palette.surfaceHighest.withValues(
                    alpha: palette.isDark ? 0.45 : 0.55,
                  ),
                  palette.surfaceHighest,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A row-shaped skeleton, used while the ledger loads.
class FluxRowSkeleton extends StatelessWidget {
  const FluxRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(
      horizontal: FluxSpace.page,
      vertical: FluxSpace.x3,
    ),
    child: Row(
      children: [
        FluxSkeleton(width: 40, height: 40, radius: FluxRadius.sm),
        SizedBox(width: FluxSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FluxSkeleton(width: 130, height: 15),
              SizedBox(height: FluxSpace.x2),
              FluxSkeleton(width: 80, height: 11),
            ],
          ),
        ),
        FluxSkeleton(width: 64, height: 16),
      ],
    ),
  );
}

enum FluxBannerTone { neutral, attention, danger, ai }

/// An inline message that carries a state and, usually, an action.
class FluxBanner extends StatelessWidget {
  const FluxBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = FluxBannerTone.neutral,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final String message;
  final String? title;
  final FluxBannerTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final (Color accent, Color fill) = switch (tone) {
      FluxBannerTone.neutral => (palette.textMuted, palette.surfaceHighest),
      FluxBannerTone.attention => (palette.attention, palette.attentionSoft),
      FluxBannerTone.danger => (palette.danger, palette.dangerSoft),
      FluxBannerTone.ai => (palette.iris, palette.irisSoft),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FluxSpace.page),
      child: FluxCard(
        color: fill,
        border: accent.withValues(alpha: 0.28),
        padding: const EdgeInsets.all(FluxSpace.x4),
        radius: FluxRadius.sm,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon ?? Icons.info_outline_rounded, size: 18, color: accent),
            const SizedBox(width: FluxSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null) ...[
                    Text(
                      title!,
                      style: FluxType.label.copyWith(color: palette.text),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message,
                    style: FluxType.caption.copyWith(color: palette.textMuted),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(height: FluxSpace.x3),
                    FluxButton(
                      label: actionLabel!,
                      onPressed: onAction,
                      kind: tone == FluxBannerTone.danger
                          ? FluxButtonKind.danger
                          : FluxButtonKind.secondary,
                      expand: false,
                      compact: true,
                    ),
                  ],
                ],
              ),
            ),
            if (onDismiss != null)
              FluxIconButton(
                icon: Icons.close_rounded,
                size: 16,
                onPressed: onDismiss,
                color: palette.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
