import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/screens/onboarding.dart';
import '../ui/screens/shell.dart';
import '../ui/theme/ff_theme.dart';
import '../ui/widgets/ff_controls.dart';
import '../ui/widgets/ff_group.dart';
import '../ui/widgets/ff_notice.dart';
import 'app_controller.dart';

/// What is on screen before the app proper is.
///
/// Four states, and only four: opening, refusing to open, locked, and ready.
/// Each is a whole screen rather than a spinner over a half-built one, because
/// a half-built screen invites tapping things that are not there yet.
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
          return const OnboardingScreen();
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
        return const FFShell();
      },
    );
  }
}

class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.ff.background,
    body: Center(
      child: Semantics(
        label: 'Opening Fund Flow',
        child: Icon(Icons.waves_rounded, size: 42, color: context.ff.tint),
      ),
    ),
  );
}

class _Locked extends StatelessWidget {
  const _Locked({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFSpace.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(Icons.lock_rounded, size: 40, color: c.tint),
              const SizedBox(height: FFSpace.xl),
              Text('Fund Flow is locked', style: FFText.title2),
              const SizedBox(height: FFSpace.sm),
              Text(
                'Authenticate with this device to open your records.',
                textAlign: TextAlign.center,
                style: FFText.subhead.copyWith(color: c.secondaryLabel),
              ),
              const Spacer(),
              FFButton('Unlock', icon: Icons.lock_open_rounded, onTap: onUnlock),
              const SizedBox(height: FFSpace.xl),
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: context.ff.groupedBackground,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: FFSpace.huge),
        children: [
          FFEmpty(
            icon: Icons.error_rounded,
            title: 'Fund Flow could not open',
            message:
                'Your records have not been changed. Try opening the app '
                'again.',
            action: 'Try again',
            onAction: onRetry,
          ),
          FFGroup(
            header: 'Technical detail',
            children: [
              Padding(
                padding: const EdgeInsets.all(FFSpace.lg),
                child: SelectableText(
                  '$error',
                  style: FFText.footnote.copyWith(
                    color: context.ff.secondaryLabel,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
