import 'dart:io';

import 'package:flutter/material.dart';

import '../update/app_updater.dart';
import 'zero_theme.dart';

Future<void> showZeroUpdates(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ZeroUpdateSheet(),
    );

/// The complete verified-development-update journey.
///
/// This surface deliberately exposes one decision at a time: check, download,
/// then install. Verification is not optional or presented as a setting.
class ZeroUpdateSheet extends StatefulWidget {
  const ZeroUpdateSheet({super.key, this.updater});
  final AppUpdater? updater;

  @override
  State<ZeroUpdateSheet> createState() => _ZeroUpdateSheetState();
}

class _ZeroUpdateSheetState extends State<ZeroUpdateSheet> {
  late final AppUpdater _updater;
  AppUpdate? _update;
  File? _verifiedApk;
  Object? _error;
  int _received = 0;
  int _total = 0;
  bool _checking = true;
  bool _downloading = false;
  bool _installing = false;

  @override
  void initState() {
    super.initState();
    _updater = widget.updater ?? AppUpdater();
    _check();
  }

  @override
  void dispose() {
    _updater.close();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final update = await _updater.check();
      if (!mounted) return;
      setState(() {
        _update = update;
        _verifiedApk = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _download() async {
    final update = _update;
    if (update == null) return;
    setState(() {
      _downloading = true;
      _error = null;
      _received = 0;
      _total = update.downloadSize;
    });
    try {
      final apk = await _updater.download(
        update,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total > 0 ? total : update.downloadSize;
          });
        },
      );
      if (mounted) setState(() => _verifiedApk = apk);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    final apk = _verifiedApk;
    if (apk == null) return;
    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      await _updater.install(apk);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .92,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.zero.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'App updates',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Development releases come directly from Fund Flow on GitHub. '
              'Every download is verified before Android opens the installer.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: context.zero.muted),
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              child: _content(context),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    if (_checking) {
      return const _UpdateState(
        key: ValueKey('checking'),
        icon: Icons.sync_rounded,
        title: 'Checking the release channel',
        detail: 'Looking for a newer verified development build…',
        busy: true,
      );
    }

    if (_error != null) {
      final permission = _error is InstallPermissionRequired;
      return Column(
        key: const ValueKey('error'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UpdateState(
            icon: permission
                ? Icons.admin_panel_settings_outlined
                : Icons.cloud_off_outlined,
            title: permission
                ? 'Allow installs from Fund Flow'
                : 'The update check could not finish',
            detail: _error.toString(),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: permission ? _install : _check,
            icon: Icon(
              permission ? Icons.system_update_alt_rounded : Icons.refresh,
            ),
            label: Text(permission ? 'I allowed it — install' : 'Try again'),
          ),
        ],
      );
    }

    final update = _update;
    if (update == null) return const SizedBox.shrink();

    if (update.availability == UpdateAvailability.unsupported) {
      return const _UpdateState(
        key: ValueKey('unsupported'),
        icon: Icons.info_outline_rounded,
        title: 'Managed by your release channel',
        detail:
            'In-app GitHub updates are available only in Fund Flow development builds.',
      );
    }

    if (update.availability == UpdateAvailability.current) {
      return Column(
        key: const ValueKey('current'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UpdateState(
            icon: Icons.check_circle_outline_rounded,
            title: 'Fund Flow is current',
            detail:
                'Build ${update.installedBuildNumber} is the newest verified development release.',
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: _check, child: const Text('Check again')),
        ],
      );
    }

    final knownTotal = _total > 0;
    final progress = knownTotal ? (_received / _total).clamp(0.0, 1.0) : null;
    return Column(
      key: const ValueKey('available'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${update.versionName} · build ${update.buildNumber}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    update.downloadSize > 0
                        ? '${_size(update.downloadSize)} download'
                        : 'New development build',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
                  ),
                ],
              ),
            ),
            if (update.mandatory) const _UpdateBadge(label: 'Required'),
          ],
        ),
        const SizedBox(height: 20),
        Text('What’s new', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 7),
        Text(
          update.releaseNotes.trim().isEmpty
              ? 'A newer development build is ready.'
              : update.releaseNotes.trim(),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.zero.muted),
        ),
        const SizedBox(height: 22),
        if (_downloading) ...[
          LinearProgressIndicator(value: progress, minHeight: 5),
          const SizedBox(height: 10),
          Text(
            knownTotal
                ? 'Downloading · ${(progress! * 100).round()}%'
                : _received > 0
                ? 'Downloading · ${_size(_received)}'
                : 'Starting secure download…',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: _installing
                ? null
                : _verifiedApk == null
                ? _download
                : _install,
            icon: Icon(
              _verifiedApk == null
                  ? Icons.download_rounded
                  : Icons.verified_outlined,
            ),
            label: Text(
              _verifiedApk == null
                  ? 'Download and verify'
                  : _installing
                  ? 'Opening Android installer…'
                  : 'Install verified update',
            ),
          ),
          if (_verifiedApk != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 17,
                  color: context.zero.positive,
                ),
                const SizedBox(width: 7),
                Text(
                  'SHA-256 verified',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.zero.positive),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

class _UpdateState extends StatelessWidget {
  const _UpdateState({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.busy = false,
  });
  final IconData icon;
  final String title;
  final String detail;
  final bool busy;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.zero.subtle,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (busy)
          const SizedBox.square(
            dimension: 21,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 21, color: context.zero.accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 5),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _UpdateBadge extends StatelessWidget {
  const _UpdateBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: context.zero.subtle,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(label, style: Theme.of(context).textTheme.labelSmall),
  );
}

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}
