import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/flux.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/shell/shell.dart';
import 'app_controller.dart';

class AppExperience extends ConsumerStatefulWidget {
  const AppExperience({super.key});

  @override
  ConsumerState<AppExperience> createState() => _AppExperienceState();
}

class _AppExperienceState extends ConsumerState<AppExperience>
    with WidgetsBindingObserver {
  bool _unlockScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(appControllerProvider.notifier);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      controller.pauseMessageImportForLifecycle();
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden) {
        controller.lock();
      }
    } else if (state == AppLifecycleState.resumed) {
      controller.resumeMessageImportForLifecycle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appControllerProvider);
    return async.when(
      loading: () => const _Opening(),
      error: (error, _) => _Failed(
        error: error,
        onRetry: () => ref.invalidate(appControllerProvider),
      ),
      data: (app) {
        if (!app.preferences.onboardingComplete) {
          return const OnboardingPage();
        }
        if (app.locked) {
          if (!_unlockScheduled) {
            _unlockScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await ref.read(appControllerProvider.notifier).unlock();
              _unlockScheduled = false;
            });
          }
          return _Locked(
            onUnlock: () => ref.read(appControllerProvider.notifier).unlock(),
          );
        }
        return const FluxShell();
      },
    );
  }
}

class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return ColoredBox(
      color: palette.background,
      child: Center(
        child: Semantics(
          label: 'Opening Fund Flow',
          // The wordmark rather than a spinner: the database opens in well under
          // a second on a warm start, and a spinner that flashes for 200ms reads
          // as a stutter.
          child: ShaderMask(
            shaderCallback: (bounds) => FluxPalette.ai.createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(
              'Fund Flow',
              style: FluxType.display.copyWith(color: const Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Locked extends StatelessWidget {
  const _Locked({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FluxSpace.page),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.lock_rounded, size: 30, color: palette.textMuted),
              const SizedBox(height: FluxSpace.x5),
              Text(
                'Locked',
                style: FluxType.display.copyWith(color: palette.text),
              ),
              const SizedBox(height: FluxSpace.x2),
              Text(
                'Your records are on this device and stay closed until you '
                'unlock them.',
                style: FluxType.body.copyWith(color: palette.textMuted),
              ),
              const Spacer(),
              FluxButton(
                label: 'Unlock',
                icon: Icons.fingerprint_rounded,
                onPressed: onUnlock,
              ),
              const SizedBox(height: FluxSpace.x6),
            ],
          ),
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FluxSpace.page),
          children: [
            const SizedBox(height: FluxSpace.x16),
            Text(
              'Could not open',
              style: FluxType.display.copyWith(color: palette.text),
            ),
            const SizedBox(height: FluxSpace.x2),
            Text(
              'Nothing has been changed. Opening the app again is safe.',
              style: FluxType.body.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: FluxSpace.x6),
            FluxButton(label: 'Try again', onPressed: onRetry),
            const SizedBox(height: FluxSpace.x8),
            FluxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TECHNICAL DETAIL',
                    style: FluxType.overline.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: FluxSpace.x3),
                  SelectableText(
                    '$error',
                    style: FluxType.caption.copyWith(
                      color: palette.textMuted,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
