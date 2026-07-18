import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/activity/activity_screen.dart';
import '../features/ask/ask_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/you/you_screen.dart';
import '../ui/components/current_mark.dart';
import '../ui/layout/current_shell.dart';
import 'app_controller.dart';

class AppExperience extends ConsumerStatefulWidget {
  const AppExperience({super.key});
  @override
  ConsumerState<AppExperience> createState() => _State();
}

class _State extends ConsumerState<AppExperience> {
  RootDestination _destination = RootDestination.ask;
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
