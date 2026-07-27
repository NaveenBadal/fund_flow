import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/app_controller.dart';
import '../app/app_state.dart';
import 'zero_intelligence.dart';
import 'zero_theme.dart';

class ZeroOnboarding extends ConsumerStatefulWidget {
  const ZeroOnboarding({super.key});

  @override
  ConsumerState<ZeroOnboarding> createState() => _ZeroOnboardingState();
}

class _ZeroOnboardingState extends ConsumerState<ZeroOnboarding> {
  int step = 0;

  static const pages = [
    (
      'Your money,\nquietly understood.',
      'Fund Flow turns payment messages into a private, useful record—without asking you to maintain another habit.',
      Icons.auto_awesome_outlined,
    ),
    (
      'Read only what\nmatters.',
      'Message analysis happens on this device. Personal conversations are ignored; financial messages become transactions you can verify.',
      Icons.shield_outlined,
    ),
    (
      'Intelligence is\nyour choice.',
      'Use the app entirely offline, or connect a model when you want natural-language answers about your spending.',
      Icons.blur_on_rounded,
    ),
    (
      'Begin with a\nclean slate.',
      'Import messages now, or skip it. You can always add transactions manually and change every preference later.',
      Icons.arrow_forward_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final page = pages[step];
    final z = context.zero;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: List.generate(
                  pages.length,
                  (index) => Expanded(
                    child: Container(
                      height: 2,
                      margin: EdgeInsets.only(
                        right: index == pages.length - 1 ? 0 : 6,
                      ),
                      color: index <= step ? z.accent : z.line,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Icon(page.$3, size: 32, color: z.accent),
              const SizedBox(height: 28),
              Text(page.$1, style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 18),
              Text(
                page.$2,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: z.muted),
              ),
              if (step == 2) ...[
                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () => showZeroIntelligence(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Connect intelligence'),
                ),
              ],
              if (step == 3) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: app.importStatus.working
                      ? null
                      : () => ref
                            .read(appControllerProvider.notifier)
                            .importMessages(),
                  icon: app.importStatus.working
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sms_outlined),
                  label: Text(
                    app.importStatus.working
                        ? 'Reading messages…'
                        : 'Import payment messages',
                  ),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  if (step > 0)
                    TextButton(
                      onPressed: () => setState(() => step--),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => _next(app),
                    child: Text(
                      step == pages.length - 1 ? 'Enter Fund Flow' : 'Continue',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _next(AppState app) async {
    if (step < pages.length - 1) {
      setState(() => step++);
      return;
    }
    await ref
        .read(appControllerProvider.notifier)
        .updatePreferences(app.preferences.copyWith(onboardingComplete: true));
  }
}
