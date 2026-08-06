import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../update/app_updater.dart';
import '../../ff_format.dart';
import '../../theme/ff_theme.dart';
import '../../widgets/ff_controls.dart';
import '../../widgets/ff_group.dart';
import '../../widgets/ff_notice.dart';
import '../../widgets/ff_screen.dart';

/// Verified development updates.
///
/// One decision at a time: check, download, install. Verification is not a
/// setting and not a step someone can skip — an APK that fails its SHA-256 is
/// deleted before Android is ever offered it.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key, this.updater});

  final AppUpdater? updater;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late final AppUpdater _updater;
  AppUpdate? _update;
  File? _verified;
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
        _verified = null;
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
      if (mounted) setState(() => _verified = apk);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _install() async {
    final apk = _verified;
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
  Widget build(BuildContext context) => FFScreen(
    title: 'App updates',
    large: false,
    slivers: _body(context),
  );

  List<Widget> _body(BuildContext context) {
    final c = context.ff;

    if (_checking) {
      return const [
        SliverToBoxAdapter(
          child: FFNotice(
            busy: true,
            title: 'Checking the release channel',
            message: 'Looking for a newer verified development build.',
          ),
        ),
      ];
    }

    if (_error != null) {
      final permission = _error is InstallPermissionRequired;
      return [
        SliverToBoxAdapter(
          child: FFNotice(
            icon: permission
                ? Icons.admin_panel_settings_rounded
                : Icons.cloud_off_rounded,
            tone: permission ? FFNoticeTone.attention : FFNoticeTone.problem,
            title: permission
                ? 'Allow installs from Fund Flow'
                : 'The check could not finish',
            message: '$_error',
          ),
        ),
        SliverToBoxAdapter(
          child: _Actions(
            children: [
              FFButton(
                permission ? 'I allowed it — install' : 'Try again',
                icon: permission
                    ? Icons.system_update_alt_rounded
                    : Icons.refresh_rounded,
                onTap: permission ? _install : _check,
              ),
            ],
          ),
        ),
      ];
    }

    final update = _update;
    if (update == null) return const [];

    if (update.availability == UpdateAvailability.unsupported) {
      return const [
        SliverToBoxAdapter(
          child: FFNotice(
            icon: Icons.info_rounded,
            title: 'Managed by your release channel',
            message:
                'In-app GitHub updates exist only in Fund Flow development '
                'builds.',
          ),
        ),
      ];
    }

    if (update.availability == UpdateAvailability.current) {
      return [
        SliverToBoxAdapter(
          child: FFNotice(
            icon: Icons.check_circle_rounded,
            tone: FFNoticeTone.positive,
            title: 'Fund Flow is up to date',
            message:
                'Build ${update.installedBuildNumber} is the newest verified '
                'development release.',
          ),
        ),
        SliverToBoxAdapter(
          child: _Actions(
            children: [
              FFButton(
                'Check again',
                style: FFButtonStyle.tinted,
                onTap: _check,
              ),
            ],
          ),
        ),
      ];
    }

    final known = _total > 0;
    final progress = known ? (_received / _total).clamp(0.0, 1.0) : null;

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FFSpace.gutter,
            FFSpace.sm,
            FFSpace.gutter,
            FFSpace.xl,
          ),
          child: Column(
            children: [
              Icon(Icons.system_update_alt_rounded, size: 40, color: c.tint),
              const SizedBox(height: FFSpace.md),
              Text(update.versionName, style: FFText.title2),
              const SizedBox(height: 2),
              Text(
                'Build ${update.buildNumber} · '
                '${update.downloadSize > 0 ? byteSize(update.downloadSize) : 'new build'} · '
                '${DateFormat('d MMM').format(update.publishedAt)}',
                style: FFText.footnote.copyWith(color: c.secondaryLabel),
              ),
              if (update.mandatory) ...[
                const SizedBox(height: FFSpace.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.orange.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(FFRadius.pill),
                  ),
                  child: Text(
                    'Required',
                    style: FFText.caption2.copyWith(
                      color: c.orange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: FFGroup(
          header: 'What’s new',
          children: [
            Padding(
              padding: const EdgeInsets.all(FFSpace.lg),
              child: Text(
                update.releaseNotes.trim().isEmpty
                    ? 'A newer development build is ready.'
                    : update.releaseNotes.trim(),
                style: FFText.footnote.copyWith(color: c.secondaryLabel),
              ),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: _Actions(
          children: _downloading
              ? [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: FFSpace.md),
                  Text(
                    known
                        ? 'Downloading · ${(progress! * 100).round()}%'
                        : _received > 0
                        ? 'Downloading · ${byteSize(_received)}'
                        : 'Starting a secure download…',
                    style: FFText.footnote.copyWith(color: c.secondaryLabel),
                  ),
                ]
              : [
                  FFButton(
                    _verified == null
                        ? 'Download and verify'
                        : _installing
                        ? 'Opening the installer…'
                        : 'Install verified update',
                    icon: _verified == null
                        ? Icons.download_rounded
                        : Icons.verified_rounded,
                    busy: _installing,
                    onTap: _installing
                        ? null
                        : _verified == null
                        ? _download
                        : _install,
                  ),
                  if (_verified != null) ...[
                    const SizedBox(height: FFSpace.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          size: 15,
                          color: c.green,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'SHA-256 verified',
                          style: FFText.footnote.copyWith(color: c.green),
                        ),
                      ],
                    ),
                  ],
                ],
        ),
      ),
    ];
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FFSpace.gutter,
      0,
      FFSpace.gutter,
      FFSpace.xl,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}
