import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  static const _steps = [
    _Step(
      number: '01',
      title: 'Know where you stand.',
      body:
          'A calm daily view of what came in, what went out, and what is safe to spend.',
      icon: Icons.radar_rounded,
    ),
    _Step(
      number: '02',
      title: 'Your ledger, built for you.',
      body:
          'Bank messages become organized movements. You stay in control of every category and correction.',
      icon: Icons.receipt_long_rounded,
    ),
    _Step(
      number: '03',
      title: 'Patterns become decisions.',
      body:
          'Plans, commitments, anomalies, and financial health are explained without spreadsheet noise.',
      icon: Icons.auto_graph_rounded,
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _steps.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: scheme.inverseSurface,
                      borderRadius: AppRadius.all(14),
                    ),
                    child: Icon(Icons.bolt_rounded, color: scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'FUND FLOW',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  TextButton(onPressed: _finish, child: const Text('Skip')),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) => _StepView(step: _steps[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Row(
                children: [
                  for (var index = 0; index < _steps.length; index++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: index == _page ? 34 : 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 7),
                      decoration: BoxDecoration(
                        color: index == _page
                            ? scheme.primary
                            : scheme.outlineVariant,
                        borderRadius: AppRadius.all(99),
                      ),
                    ),
                  const Spacer(),
                  FloatingActionButton.extended(
                    onPressed: last ? _finish : _next,
                    icon: Icon(
                      last ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    ),
                    label: Text(last ? 'Allow & begin' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _next() => _controller.nextPage(
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
  );

  Future<void> _finish() async {
    if (_page == _steps.length - 1) {
      await Permission.sms.request();
    }
    await markOnboardingDone(ref.read(secureStorageProvider));
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AppShell()),
      );
    }
  }
}

class _Step {
  const _Step({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });
  final String number;
  final String title;
  final String body;
  final IconData icon;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});
  final _Step step;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.number,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          const Spacer(),
          Container(
            height: 250,
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.inverseSurface,
              borderRadius: AppRadius.all(36),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.primary.withValues(alpha: .18),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: AppRadius.all(34),
                    ),
                    child: Icon(step.icon, size: 52, color: scheme.onPrimary),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            step.title,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1.4,
              height: .98,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            step.body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
