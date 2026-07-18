import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/activity/activity_screen.dart';
import '../features/ask/ask_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/you/you_screen.dart';
import '../ui/components/current_mark.dart';
import '../ui/components/current_button.dart';
import '../ui/foundation/current_colors.dart';
import '../ui/layout/current_shell.dart';
import 'app_controller.dart';

class AppExperience extends ConsumerStatefulWidget {
  const AppExperience({super.key});
  @override
  ConsumerState<AppExperience> createState() => _State();
}

class _State extends ConsumerState<AppExperience> with WidgetsBindingObserver {
  RootDestination _destination = RootDestination.ask;
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
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(appControllerProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appControllerProvider);
    return async.when(
      loading: () => const Scaffold(body: Center(child: CurrentMark(size: 48))),
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
          return _LockedView(
            onUnlock: () => ref.read(appControllerProvider.notifier).unlock(),
          );
        }
        final child = switch (_destination) {
          RootDestination.ask => const AskScreen(),
          RootDestination.activity => const ActivityScreen(),
          RootDestination.you => const YouScreen(),
        };
        return CurrentShell(
          destination: _destination,
          onDestinationChanged: (v) => setState(() => _destination = v),
          child: SafeArea(bottom: false, child: child),
        );
      },
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CurrentMark(size: 38),
            const Spacer(),
            Icon(
              Icons.lock_outline_rounded,
              size: 34,
              color: context.current.intelligence,
            ),
            const SizedBox(height: 22),
            Text(
              'Your money is locked.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'Authenticate with this device to open Fund Flow.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
            ),
            const SizedBox(height: 24),
            CurrentButton(label: 'Unlock Fund Flow', onPressed: onUnlock),
            const Spacer(),
          ],
        ),
      ),
    ),
  );
}
