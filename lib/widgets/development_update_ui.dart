import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/development_update_provider.dart';
import '../services/development_update_service.dart';
import '../theme/app_tokens.dart';

class DevelopmentUpdateBanner extends ConsumerWidget {
  const DevelopmentUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(developmentUpdateProvider);
    if (state.phase != DevelopmentUpdatePhase.available &&
        state.phase != DevelopmentUpdatePhase.downloading &&
        state.phase != DevelopmentUpdatePhase.ready &&
        state.phase != DevelopmentUpdatePhase.permissionRequired) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Material(
        color: scheme.primaryContainer,
        shape: ExpressiveShape.hero(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDevelopmentUpdateSheet(context),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.system_update_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.phase == DevelopmentUpdatePhase.ready ||
                                state.phase ==
                                    DevelopmentUpdatePhase.permissionRequired
                            ? 'Development update ready'
                            : state.phase == DevelopmentUpdatePhase.downloading
                            ? 'Downloading update…'
                            : '${state.update?.versionName} is available',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        state.update?.releaseNotes ??
                            'Tap to continue the update.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (state.phase ==
                          DevelopmentUpdatePhase.downloading) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: state.progress),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
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
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: ContinuousRectangleBorder(
        borderRadius: ExpressiveShape.playful(1),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const Icon(Icons.system_update_alt_rounded),
        title: const Text(
          'Development updates',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(_status(state)),
        trailing: busy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: busy
            ? null
            : () async {
                if (state.phase == DevelopmentUpdatePhase.idle ||
                    state.phase == DevelopmentUpdatePhase.upToDate ||
                    state.phase == DevelopmentUpdatePhase.error) {
                  await ref.read(developmentUpdateProvider.notifier).check();
                }
                if (context.mounted) await showDevelopmentUpdateSheet(context);
              },
      ),
    );
  }

  String _status(DevelopmentUpdateState state) => switch (state.phase) {
    DevelopmentUpdatePhase.idle => 'GitHub development channel',
    DevelopmentUpdatePhase.checking => 'Checking GitHub…',
    DevelopmentUpdatePhase.upToDate =>
      '${state.installedVersion ?? 'Installed build'} is current',
    DevelopmentUpdatePhase.available =>
      '${state.update?.versionName} is available',
    DevelopmentUpdatePhase.downloading =>
      'Downloading ${(state.progress * 100).round()}%',
    DevelopmentUpdatePhase.ready => 'Downloaded and verified',
    DevelopmentUpdatePhase.permissionRequired =>
      'Android install permission required',
    DevelopmentUpdatePhase.error => state.message ?? 'Update check failed',
    DevelopmentUpdatePhase.disabled => 'Disabled in this build',
  };
}

Future<void> showDevelopmentUpdateSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _DevelopmentUpdateSheet(),
    );

class _DevelopmentUpdateSheet extends ConsumerWidget {
  const _DevelopmentUpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(developmentUpdateProvider);
    final update = state.update;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: Material(
                color: scheme.primaryContainer,
                shape: ContinuousRectangleBorder(
                  borderRadius: ExpressiveShape.playful(0),
                ),
                child: Icon(Icons.system_update_rounded, color: scheme.primary),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              update == null
                  ? 'Development updates'
                  : 'Fund Flow ${update.versionName}',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _description(state),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            if (state.phase == DevelopmentUpdatePhase.downloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(value: state.progress),
              const SizedBox(height: 7),
              Text('${(state.progress * 100).round()}% downloaded'),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _action(ref, state),
                icon: Icon(_actionIcon(state)),
                label: Text(_actionLabel(state)),
              ),
            ),
            if (state.installedVersion != null) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  'Installed ${state.installedVersion} (${state.installedBuild})',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
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
    DevelopmentUpdatePhase.available => 'Download verified update',
    DevelopmentUpdatePhase.downloading => 'Downloading…',
    DevelopmentUpdatePhase.ready => 'Install update',
    DevelopmentUpdatePhase.permissionRequired => 'Allow and install',
    DevelopmentUpdatePhase.checking => 'Checking…',
    _ => 'Check again',
  };

  IconData _actionIcon(DevelopmentUpdateState state) => switch (state.phase) {
    DevelopmentUpdatePhase.available => Icons.download_rounded,
    DevelopmentUpdatePhase.ready ||
    DevelopmentUpdatePhase.permissionRequired => Icons.install_mobile_rounded,
    _ => Icons.refresh_rounded,
  };

  String _description(DevelopmentUpdateState state) {
    if (state.phase == DevelopmentUpdatePhase.permissionRequired) {
      return 'Android opened “Install unknown apps.” Allow Fund Flow Dev, return here, and tap Allow and install again.';
    }
    if (state.phase == DevelopmentUpdatePhase.ready) {
      return 'The APK checksum is valid. Android will ask you to approve replacing the current development build.';
    }
    if (state.phase == DevelopmentUpdatePhase.error) {
      return state.message ?? 'The update channel could not be reached.';
    }
    if (state.phase == DevelopmentUpdatePhase.upToDate) {
      return 'You already have the newest published GitHub development build.';
    }
    return state.update?.releaseNotes ??
        'Check GitHub Releases for a newer signed development build.';
  }
}
