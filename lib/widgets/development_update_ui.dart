import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../flow_os/primitives/loom_mark.dart';
import '../providers/development_update_provider.dart';
import '../services/development_update_service.dart';

class DevelopmentUpdateBanner extends ConsumerWidget {
  const DevelopmentUpdateBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(developmentUpdateProvider);
    if (!const {
      DevelopmentUpdatePhase.available,
      DevelopmentUpdatePhase.downloading,
      DevelopmentUpdatePhase.ready,
      DevelopmentUpdatePhase.permissionRequired,
    }.contains(state.phase)) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: _UpdatePort(
        label:
            state.phase == DevelopmentUpdatePhase.ready ||
                state.phase == DevelopmentUpdatePhase.permissionRequired
            ? 'BUILD READY'
            : state.phase == DevelopmentUpdatePhase.downloading
            ? 'RECEIVING BUILD'
            : 'BUILD AVAILABLE',
        detail:
            state.update?.releaseNotes ?? 'Open verified development channel',
        progress: state.phase == DevelopmentUpdatePhase.downloading
            ? state.progress
            : null,
        onTap: () => showDevelopmentUpdateSheet(context),
      ),
    );
  }
}

class DevelopmentUpdateSettingsCard extends ConsumerWidget {
  const DevelopmentUpdateSettingsCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!githubDevelopmentUpdatesEnabled) return const SizedBox.shrink();
    final state = ref.watch(developmentUpdateProvider);
    final busy =
        state.phase == DevelopmentUpdatePhase.checking ||
        state.phase == DevelopmentUpdatePhase.downloading;
    return _UpdatePort(
      label: 'DEVELOPMENT CHANNEL',
      detail: _status(state),
      progress: state.phase == DevelopmentUpdatePhase.downloading
          ? state.progress
          : null,
      onTap: busy
          ? null
          : () async {
              if (state.phase == DevelopmentUpdatePhase.idle ||
                  state.phase == DevelopmentUpdatePhase.upToDate ||
                  state.phase == DevelopmentUpdatePhase.error) {
                await ref.read(developmentUpdateProvider.notifier).check();
              }
              if (context.mounted) {
                await showDevelopmentUpdateSheet(context);
              }
            },
    );
  }

  String _status(DevelopmentUpdateState state) => switch (state.phase) {
    DevelopmentUpdatePhase.idle => 'GitHub development channel',
    DevelopmentUpdatePhase.checking => 'Checking signed release…',
    DevelopmentUpdatePhase.upToDate =>
      '${state.installedVersion ?? 'Installed build'} is current',
    DevelopmentUpdatePhase.available =>
      '${state.update?.versionName} is available',
    DevelopmentUpdatePhase.downloading =>
      'Downloading ${(state.progress * 100).round()}%',
    DevelopmentUpdatePhase.ready => 'Downloaded and verified',
    DevelopmentUpdatePhase.permissionRequired => 'Android permission required',
    DevelopmentUpdatePhase.error => state.message ?? 'Update check failed',
    DevelopmentUpdatePhase.disabled => 'Disabled in this build',
  };
}

class _UpdatePort extends StatelessWidget {
  const _UpdatePort({
    required this.label,
    required this.detail,
    required this.onTap,
    this.progress,
  });
  final String label, detail;
  final VoidCallback? onTap;
  final double? progress;
  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    child: InkWell(
      onTap: onTap,
      child: CutSurface(
        color: FlowColor.loom.withValues(alpha: .12),
        accent: progress == null ? FlowColor.proof : FlowColor.amber,
        child: Row(
          children: [
            LoomMark(
              size: 34,
              state: progress == null ? LoomState.ready : LoomState.checking,
              progress: progress,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: FlowColor.quiet(context),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: FlowColor.proof, size: 18),
          ],
        ),
      ),
    ),
  );
}

Future<void> showDevelopmentUpdateSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (_) => const _DevelopmentUpdateSheet(),
    );

class _DevelopmentUpdateSheet extends ConsumerWidget {
  const _DevelopmentUpdateSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(developmentUpdateProvider);
    final update = state.update;
    return ColoredBox(
      color: FlowColor.canvas(context),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CoordinateLabel(
                'System / verified build channel',
                line: true,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const LoomMark(size: 48),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      update == null
                          ? 'Development build'
                          : 'Fund Flow ${update.versionName}',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              CutSurface(
                accent: state.phase == DevelopmentUpdatePhase.error
                    ? FlowColor.coral
                    : FlowColor.proof,
                child: Text(
                  _description(state),
                  style: TextStyle(
                    color: FlowColor.quiet(context),
                    height: 1.45,
                  ),
                ),
              ),
              if (state.phase == DevelopmentUpdatePhase.downloading) ...[
                const SizedBox(height: 14),
                _ThreadProgress(state.progress),
                const SizedBox(height: 6),
                CoordinateLabel(
                  '${(state.progress * 100).round()} / 100 received',
                  color: FlowColor.amber,
                ),
              ],
              const SizedBox(height: 20),
              _UpdateDecision(
                label: _actionLabel(state),
                enabled: _action(ref, state) != null,
                onTap: _action(ref, state),
              ),
              if (state.installedVersion != null) ...[
                const SizedBox(height: 12),
                CoordinateLabel(
                  'Installed ${state.installedVersion} / ${state.installedBuild}',
                  color: FlowColor.quiet(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  VoidCallback? _action(WidgetRef ref, DevelopmentUpdateState state) =>
      switch (state.phase) {
        DevelopmentUpdatePhase.available =>
          () => ref.read(developmentUpdateProvider.notifier).download(),
        DevelopmentUpdatePhase.ready ||
        DevelopmentUpdatePhase.permissionRequired =>
          () => ref.read(developmentUpdateProvider.notifier).install(),
        DevelopmentUpdatePhase.idle ||
        DevelopmentUpdatePhase.upToDate ||
        DevelopmentUpdatePhase.error =>
          () => ref.read(developmentUpdateProvider.notifier).check(),
        _ => null,
      };
  String _actionLabel(DevelopmentUpdateState state) => switch (state.phase) {
    DevelopmentUpdatePhase.available => 'RECEIVE VERIFIED BUILD',
    DevelopmentUpdatePhase.downloading => 'RECEIVING…',
    DevelopmentUpdatePhase.ready => 'INSTALL VERIFIED BUILD',
    DevelopmentUpdatePhase.permissionRequired => 'ALLOW AND INSTALL',
    DevelopmentUpdatePhase.checking => 'CHECKING…',
    _ => 'CHECK CHANNEL',
  };
  String _description(DevelopmentUpdateState state) {
    if (state.phase == DevelopmentUpdatePhase.permissionRequired) {
      return 'Android opened “Install unknown apps.” Allow Fund Flow Dev, return here, then install again.';
    }
    if (state.phase == DevelopmentUpdatePhase.ready) {
      return 'Checksum proven. Android will ask you to approve replacing the current development build.';
    }
    if (state.phase == DevelopmentUpdatePhase.error) {
      return state.message ?? 'The development channel could not be reached.';
    }
    if (state.phase == DevelopmentUpdatePhase.upToDate) {
      return 'This is the newest published GitHub development build.';
    }
    return state.update?.releaseNotes ??
        'Check GitHub Releases for a newer signed development build.';
  }
}

class _ThreadProgress extends StatelessWidget {
  const _ThreadProgress(this.value);
  final double value;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) => Stack(
      children: [
        Container(height: 4, color: FlowColor.rule(context)),
        Container(
          height: 4,
          width: c.maxWidth * value.clamp(0, 1),
          color: FlowColor.amber,
        ),
      ],
    ),
  );
}

class _UpdateDecision extends StatelessWidget {
  const _UpdateDecision({
    required this.label,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final bool enabled;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: CutSurface(
      color: enabled ? FlowColor.loom : FlowColor.plane(context),
      accent: enabled ? FlowColor.proof : FlowColor.rule(context),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white : FlowColor.quiet(context),
                fontWeight: FontWeight.w900,
                letterSpacing: .7,
              ),
            ),
          ),
          Icon(
            Icons.arrow_forward,
            color: enabled ? FlowColor.proof : FlowColor.quiet(context),
          ),
        ],
      ),
    ),
  );
}
