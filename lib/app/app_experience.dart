import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/screens/onboarding.dart';
import '../ui/screens/shell.dart';
import '../ui/widgets/precision_components.dart';
import '../ui/tokens/precision_tokens.dart';
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
        return const PrecisionShell();
      },
    );
  }
}

class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? PrecisionTokens.backgroundDark : PrecisionTokens.backgroundLight,
      body: Center(
        child: Semantics(
          label: 'Opening Fund Flow',
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              isDark ? PrecisionTokens.textPrimaryDark : PrecisionTokens.textPrimaryLight,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? PrecisionTokens.backgroundDark : PrecisionTokens.backgroundLight,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PrecisionTokens.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const PrecisionHeader(
                title: 'Locked',
                subtitle: 'Authenticate with this device to open your records.',
              ),
              const Spacer(),
              PrecisionButton(
                label: 'Unlock',
                onPressed: onUnlock,
              ),
              const SizedBox(height: PrecisionTokens.space24),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? PrecisionTokens.surfaceDark : PrecisionTokens.surfaceLight,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PrecisionTokens.space24),
          children: [
            const SizedBox(height: PrecisionTokens.space64),
            const PrecisionHeader(
              title: 'Could not open',
              subtitle: 'Your records have not been changed. Try opening the app again.',
            ),
            const SizedBox(height: PrecisionTokens.space32),
            PrecisionButton(
              label: 'Try again',
              onPressed: onRetry,
            ),
            const SizedBox(height: PrecisionTokens.space48),
            PrecisionSurface(
              elevated: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Technical detail', style: theme.textTheme.labelMedium),
                  const SizedBox(height: PrecisionTokens.space12),
                  SelectableText(
                    '$error',
                    style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
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
