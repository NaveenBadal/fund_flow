import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../design/flux.dart';
import '../../update/app_updater.dart';
import '../gallery/design_gallery.dart';

/// Version, and the verified update flow.
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  PackageInfo? _package;
  AppUpdate? _update;
  bool _checking = false;
  bool _installing = false;
  String? _error;
  double? _progress;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((value) {
      if (mounted) setState(() => _package = value);
    });
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final updater = AppUpdater();
    try {
      final update = await updater.check();
      if (mounted) setState(() => _update = update);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'The check could not reach GitHub. This says nothing about '
              'whether an update exists.',
        );
      }
    } finally {
      updater.close();
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install(AppUpdate update) async {
    setState(() {
      _installing = true;
      _error = null;
      _progress = 0;
    });
    final updater = AppUpdater();
    try {
      final file = await updater.download(
        update,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
      await updater.install(file);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error =
              'The download failed its integrity check or was interrupted. '
              'Nothing was installed.',
        );
      }
    } finally {
      updater.close();
      if (mounted) {
        setState(() {
          _installing = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final update = _update;
    final available = update?.availability == UpdateAvailability.available;

    return FluxDetailPage(
      title: 'About',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: FluxCard(
            // Long-press the version block to reach the Flux gallery. Debug
            // builds only, and deliberately undiscoverable: it exists to be
            // screenshotted while working on the design system, not to be
            // found by someone using the app.
            onTap: kDebugMode
                ? () => fluxPush(context, (context) => const DesignGallery())
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fund Flow',
                  style: FluxType.title.copyWith(color: palette.text),
                ),
                const SizedBox(height: 2),
                Text(
                  _package == null
                      ? 'Reading version…'
                      : 'Version ${_package!.version} · build '
                            '${_package!.buildNumber}',
                  style: FluxType.body.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: FluxSpace.x4),
                Text(
                  'An AI-first money agent that reads the transaction messages '
                  'your bank already sends, keeps the results on your phone, and '
                  'answers questions about them.',
                  style: FluxType.caption.copyWith(
                    color: palette.textMuted,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Updates',
            footer:
                'Builds come from GitHub development releases. Each download is '
                'checked against the SHA-256 in its published manifest before '
                'Android is asked to install it.',
            children: [
              FluxRow(
                title: available ? 'Update available' : 'Check for updates',
                subtitle: switch (update?.availability) {
                  null => null,
                  UpdateAvailability.unsupported => 'This build has no updater',
                  UpdateAvailability.current => 'You are on the newest build',
                  UpdateAvailability.available =>
                    'Version ${update!.versionName} · build '
                        '${update.buildNumber}',
                },
                icon: available
                    ? Icons.system_update_rounded
                    : Icons.refresh_rounded,
                iconColor: available ? palette.iris : null,
                busy: _checking,
                onTap: _checking ? null : _check,
              ),
              if (available)
                FluxRow(
                  title: _installing ? 'Downloading…' : 'Download and install',
                  subtitle: _progress == null
                      ? '${(update!.downloadSize / 1048576).toStringAsFixed(1)} MB'
                      : '${(_progress! * 100).round()}%',
                  icon: Icons.download_rounded,
                  busy: _installing,
                  onTap: _installing ? null : () => _install(update!),
                ),
            ],
          ),
        ),
        if (_error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: FluxSpace.x6),
              child: FluxBanner(
                tone: FluxBannerTone.danger,
                message: _error!,
                icon: Icons.error_outline_rounded,
              ),
            ),
          ),
        if (available && update!.releaseNotes.trim().isNotEmpty)
          FluxSliverPadding(
            top: FluxSpace.x6,
            child: FluxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WHAT CHANGED',
                    style: FluxType.overline.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: FluxSpace.x3),
                  Text(
                    update.releaseNotes.trim(),
                    style: FluxType.caption.copyWith(
                      color: palette.textMuted,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ),
        FluxSliverPadding(
          top: FluxSpace.x6,
          child: Text(
            'Running on ${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion}.',
            style: FluxType.caption.copyWith(color: palette.textFaint),
          ),
        ),
      ],
    );
  }
}
