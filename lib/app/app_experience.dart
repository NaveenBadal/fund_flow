import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui2/components/flow_mark.dart';
import '../ui2/screens/flow_home.dart';
import '../ui2/screens/onboarding_screen.dart';
import '../ui2/tokens/flow_metrics.dart';
import '../ui2/tokens/flow_palette.dart';
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
      loading: () => const Scaffold(body: Center(child: FlowMark(size: 48))),
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
        return const FlowHome();
      },
    );
  }
}

class _LockedView extends StatelessWidget {
  const _LockedView({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FlowMark(size: 38),
              const Spacer(),
              Icon(Icons.lock_outline_rounded, size: 34, color: flow.accent),
              const SizedBox(height: FlowSpace.xl),
              Text(
                'Your money is locked.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: FlowSpace.md),
              Text(
                'Authenticate with this device to open Fund Flow.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: flow.inkSoft),
              ),
              const SizedBox(height: FlowSpace.xl),
              FilledButton(
                onPressed: onUnlock,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(FlowDensity.minimumTarget),
                  backgroundColor: flow.accent,
                  foregroundColor: flow.onAccent,
                  shape: const RoundedRectangleBorder(
                    borderRadius: FlowRadius.sm,
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
