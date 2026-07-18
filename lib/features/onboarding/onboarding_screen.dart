import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/preferences.dart';
import '../../ui/components/current_button.dart';
import '../../ui/components/current_mark.dart';
import '../../ui/foundation/current_colors.dart';
import '../you/connect_intelligence_sheet.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _State();
}

class _State extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
              child: Row(
                children: [
                  const CurrentMark(size: 34),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Fund Flow',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    '${_step + 1} of 4',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: context.current.muted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: Container(
                      height: 2,
                      margin: EdgeInsets.only(right: i == 3 ? 0 : 6),
                      color: i <= _step
                          ? context.current.intelligence
                          : context.current.rule,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: SingleChildScrollView(
                  key: ValueKey(_step),
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: _content(app),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    CurrentButton(
                      label: 'Back',
                      icon: Icons.arrow_back_rounded,
                      style: CurrentButtonStyle.text,
                      onPressed: () => setState(() => _step--),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: CurrentButton(
                      label: _primaryLabel(app),
                      expand: true,
                      onPressed: () => _next(app),
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

  String _primaryLabel(dynamic app) => switch (_step) {
    0 => 'Get started',
    1 =>
      app.aiConnection.name == 'connected'
          ? 'Continue'
          : 'Connect or continue later',
    2 => 'Check messages or skip',
    _ => 'Open Fund Flow',
  };

  Widget _content(dynamic app) => switch (_step) {
    0 => _Narrative(
      icon: Icons.auto_awesome_mosaic_outlined,
      eyebrow: 'A quieter way to understand money',
      title: 'Your activity can answer back.',
      body:
          'Fund Flow turns transaction messages into a private money record, then helps you understand what changed in ordinary language.',
    ),
    1 => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Narrative(
          icon: Icons.link_rounded,
          eyebrow: 'Intelligence',
          title: 'Connect the AI you trust.',
          body:
              'Only candidate transaction text and your questions go to your configured provider. Your normalized activity stays on this device.',
        ),
        const SizedBox(height: 22),
        CurrentButton(
          label: app.aiConnection.name == 'connected'
              ? 'Intelligence connected'
              : 'Connect intelligence',
          icon: app.aiConnection.name == 'connected'
              ? Icons.check_rounded
              : Icons.link_rounded,
          style: CurrentButtonStyle.outline,
          onPressed: () => _connect(),
        ),
      ],
    ),
    2 => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Narrative(
          icon: Icons.sms_outlined,
          eyebrow: 'Transaction messages',
          title: 'Build activity without manual entry.',
          body:
              'Android asks before Fund Flow reads messages. Unrelated conversations are ignored locally. Candidate transaction text is sent only to your configured provider.',
        ),
        const SizedBox(height: 22),
        CurrentButton(
          label: app.importStatus.working
              ? 'Checking messages…'
              : 'Check messages',
          icon: Icons.sms_outlined,
          style: CurrentButtonStyle.outline,
          onPressed: app.importStatus.working
              ? null
              : () => ref.read(appControllerProvider.notifier).importMessages(),
        ),
        if (app.importStatus.message != null) ...[
          const SizedBox(height: 12),
          Text(
            app.importStatus.message!,
            style: TextStyle(color: context.current.review),
          ),
        ],
      ],
    ),
    _ => _Narrative(
      icon: Icons.check_circle_outline_rounded,
      eyebrow: 'Ready',
      title: app.transactions.isEmpty
          ? 'Start with a question.'
          : '${app.transactions.length} transactions are ready.',
      body: app.transactions.isEmpty
          ? 'You can connect intelligence, check messages, or add a transaction at any time.'
          : '${app.importStatus.imported} added and ${app.importStatus.skipped} skipped. Items needing attention appear clearly in Activity.',
    ),
  };

  Future<void> _connect() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ConnectIntelligenceSheet(),
  );
  Future<void> _next(dynamic app) async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    final prefs = (app.preferences as AppPreferences).copyWith(
      onboardingComplete: true,
    );
    await ref.read(appControllerProvider.notifier).updatePreferences(prefs);
  }
}

class _Narrative extends StatelessWidget {
  const _Narrative({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String eyebrow;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: MediaQuery.sizeOf(context).height * .07),
      Icon(icon, size: 36, color: context.current.intelligence),
      const SizedBox(height: 26),
      Text(
        eyebrow,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: context.current.muted),
      ),
      const SizedBox(height: 8),
      Text(title, style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 14),
      Text(
        body,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
      ),
    ],
  );
}
