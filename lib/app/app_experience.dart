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
      loading: () => Scaffold(
        body: Center(
          child: Semantics(
            label: 'Opening Fund Flow',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('F', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 22,
                  child: LinearProgressIndicator(minHeight: 2),
                ),
              ],
            ),
          ),
        ),
      ),
      error: (e, _) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      color: context.zero.negative,
                      size: 32,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Fund Flow could not open',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Your local records have not been changed. Try opening the app again.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: context.zero.muted,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => ref.invalidate(appControllerProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Try again'),
                    ),
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Technical details'),
                      children: [
                        SelectableText(
                          '$e',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
