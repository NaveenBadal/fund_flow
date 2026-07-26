import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../zero/zero_home.dart';
import '../zero/zero_onboarding.dart';
import '../zero/zero_theme.dart';
import 'app_controller.dart';

class AppExperience extends ConsumerStatefulWidget {
  const AppExperience({super.key});
  @override
  ConsumerState<AppExperience> createState() => _State();
}

class _State extends ConsumerState<AppExperience> with WidgetsBindingObserver {
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
      loading: () => const Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(
            'Fund Flow could not open.\n$e',
            textAlign: TextAlign.center,
          ),
        ),
      ),
      data: (app) {
        if (!app.preferences.onboardingComplete) {
          return const ZeroOnboarding();
        }
        if (app.locked) {
          if (!_unlockScheduled) {
            _unlockScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await ref.read(appControllerProvider.notifier).unlock();
              _unlockScheduled = false;
            });
          }
          return _LockedView(
            onUnlock: () => ref.read(appControllerProvider.notifier).unlock(),
          );
        }
        return const ZeroHome();
      },
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('F', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              Icon(Icons.lock_outline_rounded, size: 34, color: z.accent),
              const SizedBox(height: 24),
              Text(
                'Your money is locked.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Authenticate with this device to open Fund Flow.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: z.muted),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onUnlock,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: z.accent,
                  foregroundColor: z.onAccent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                child: const Text('Unlock Fund Flow'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
