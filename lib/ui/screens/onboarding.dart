import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_controls.dart';
import '../widgets/ff_pressable.dart';
import 'settings/intelligence.dart';

/// First run.
///
/// Three screens, each answering a question someone actually has: what is
/// this, what does it read, and what happens now. No account, no tour, and
/// nothing that has to be agreed to before the app will open.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next(AppState app) {
    if (_page < 2) {
      _pages.animateToPage(
        _page + 1,
        duration: Duration(milliseconds: context.ffStill ? 0 : 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    ref
        .read(appControllerProvider.notifier)
        .updatePreferences(app.preferences.copyWith(onboardingComplete: true));
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final c = context.ff;
    final importing = app.importStatus.working;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (value) => setState(() => _page = value),
                children: [
                  const _Page(
                    glyph: Icons.waves_rounded,
                    title: 'Welcome to\nFund Flow',
                    features: [
                      (
                        Icons.sms_rounded,
                        'It reads the messages you already get',
                        'Bank and wallet alerts become a record without you '
                            'typing anything.',
                      ),
                      (
                        Icons.insights_rounded,
                        'It tells you what changed',
                        'Duplicates, unusual charges and a month running ahead '
                            'of the last one.',
                      ),
                      (
                        Icons.auto_awesome_rounded,
                        'It answers in plain words',
                        'Ask about your money and get an answer built from '
                            'your own transactions.',
                      ),
                    ],
                  ),
                  const _Page(
                    glyph: Icons.lock_rounded,
                    title: 'What stays\non this device',
                    features: [
                      (
                        Icons.storage_rounded,
                        'Every transaction',
                        'The ledger is a local database. It is never uploaded '
                            'and there is no account.',
                      ),
                      (
                        Icons.visibility_off_rounded,
                        'Personal conversations',
                        'Only messages that look like payments are ever '
                            'looked at.',
                      ),
                      (
                        Icons.north_east_rounded,
                        'What does leave',
                        'Your questions, and the text of payment messages, go '
                            'to the provider you choose — nothing else.',
                      ),
                    ],
                  ),
                  _Page(
                    glyph: Icons.bolt_rounded,
                    title: 'Ready when\nyou are',
                    features: const [
                      (
                        Icons.link_rounded,
                        'Connect a model',
                        'Needed to read messages and answer questions. You '
                            'bring your own provider and key.',
                      ),
                      (
                        Icons.tune_rounded,
                        'Change anything later',
                        'Every choice here lives in Settings and can be undone.',
                      ),
                    ],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FFButton(
                          app.aiConnection == AiConnection.connected
                              ? 'Provider connected'
                              : 'Connect a provider',
                          icon: app.aiConnection == AiConnection.connected
                              ? Icons.check_rounded
                              : Icons.link_rounded,
                          style: FFButtonStyle.tinted,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const IntelligenceScreen(),
                            ),
                          ),
                        ),
                        const SizedBox(height: FFSpace.sm),
                        FFButton(
                          importing
                              ? 'Reading messages…'
                              : 'Check my messages now',
                          icon: Icons.search_rounded,
                          busy: importing,
                          style: FFButtonStyle.tinted,
                          onTap:
                              app.aiConnection == AiConnection.connected &&
                                  !importing
                              ? ref
                                    .read(appControllerProvider.notifier)
                                    .importMessages
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFSpace.xl,
                FFSpace.lg,
                FFSpace.xl,
                FFSpace.lg,
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < 3; i++)
                        AnimatedContainer(
                          duration: Duration(
                            milliseconds: context.ffStill ? 0 : 220,
                          ),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _page ? 18 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? c.tint : c.quaternaryLabel,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: FFSpace.lg),
                  FFButton(
                    _page == 2 ? 'Start using Fund Flow' : 'Continue',
                    onTap: () => _next(app),
                  ),
                  SizedBox(
                    height: 44,
                    child: _page == 2
                        ? null
                        : Center(
                            child: FFPressable(
                              onTap: () => ref
                                  .read(appControllerProvider.notifier)
                                  .updatePreferences(
                                    app.preferences.copyWith(
                                      onboardingComplete: true,
                                    ),
                                  ),
                              child: Text(
                                'Skip',
                                style: FFText.subhead.copyWith(color: c.tint),
                              ),
                            ),
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

class _Page extends StatelessWidget {
  const _Page({
    required this.glyph,
    required this.title,
    required this.features,
    this.child,
  });

  final IconData glyph;
  final String title;
  final List<(IconData, String, String)> features;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        FFSpace.xl,
        FFSpace.huge,
        FFSpace.xl,
        FFSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(glyph, size: 44, color: c.tint),
          const SizedBox(height: FFSpace.xl),
          Text(title, style: FFText.largeTitle),
          const SizedBox(height: FFSpace.xxl),
          for (final (icon, heading, detail) in features)
            Padding(
              padding: const EdgeInsets.only(bottom: FFSpace.xl),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 34,
                    child: Icon(icon, size: 23, color: c.tint),
                  ),
                  const SizedBox(width: FFSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(heading, style: FFText.headline),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: FFText.subhead.copyWith(
                            color: c.secondaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ?child,
        ],
      ),
    );
  }
}
