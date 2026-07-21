import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../components/flow_mark.dart';
import '../motion/flow_motion_widgets.dart';
import '../sheets/connect_intelligence_sheet.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// First run: what this is, connect the AI, let it read, done.
///
/// Four steps because each one asks for a different kind of consent —
/// attention, a key, a permission — and stacking them on one screen turns
/// three small yeses into one large hesitation. Everything is skippable:
/// the app is usable empty, and a person who explores first connects later
/// with more conviction.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _State();
}

class _State extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    final app = ref.watch(appControllerProvider).requireValue;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FlowSpace.xl,
                FlowSpace.lg,
                FlowSpace.xl,
                FlowSpace.sm,
              ),
              child: Row(
                children: [
                  const FlowMark(size: 32),
                  const SizedBox(width: FlowSpace.md),
                  Expanded(child: Text('Fund Flow', style: text.titleLarge)),
                  FlowAnimatedCount(
                    text: '${_step + 1} of 4',
                    style: text.labelMedium?.copyWith(color: flow.inkSoft),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: FlowSpace.xl),
              child: Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: AnimatedContainer(
                      duration: FlowMotion.respecting(
                        context,
                        FlowMotion.standard,
                      ),
                      curve: FlowMotion.move,
                      height: 2,
                      margin: EdgeInsets.only(right: i == 3 ? 0 : FlowSpace.xs),
                      color: i <= _step ? flow.accent : flow.line,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FlowCardAdvance(
                // Centre the step within the space between the header and the
                // button when it is short, but let it scroll when a connected
                // state or an error makes it tall. Without the min-height the
                // content shrink-wraps to the top and leaves a dead gap above
                // the primary button.
                child: LayoutBuilder(
                  key: ValueKey(_step),
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.all(FlowSpace.xl),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - FlowSpace.xl * 2,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: _content(app),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FlowSpace.xl,
                FlowSpace.sm,
                FlowSpace.xl,
                FlowSpace.xl,
              ),
              child: Row(
                children: [
                  if (_step > 0) ...[
                    TextButton.icon(
                      onPressed: () => setState(() => _step--),
                      style: TextButton.styleFrom(
                        foregroundColor: flow.inkSoft,
                        minimumSize: const Size(0, FlowDensity.minimumTarget),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('Back'),
                    ),
                    const SizedBox(width: FlowSpace.sm),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _next(app),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          FlowDensity.minimumTarget,
                        ),
                        backgroundColor: flow.accent,
                        foregroundColor: flow.onAccent,
                        shape: const RoundedRectangleBorder(
                          borderRadius: FlowRadius.sm,
                        ),
                      ),
                      child: Text(_primaryLabel(app)),
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

  String _primaryLabel(AppState app) => switch (_step) {
    0 => 'Get started',
    1 =>
      app.aiConnection == AiConnection.connected
          ? 'Continue'
          : 'Connect or continue later',
    2 => 'Check messages or skip',
    _ => 'Open Fund Flow',
  };

  Widget _content(AppState app) {
    final flow = context.flow;
    return switch (_step) {
      0 => const _Narrative(
        icon: Icons.waves_rounded,
        eyebrow: 'A quieter way to understand money',
        title: 'Your activity can answer back.',
        body:
            'Fund Flow turns transaction messages into a private money '
            'record, then helps you understand what changed in ordinary '
            'language.',
      ),
      1 => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Narrative(
            icon: Icons.link_rounded,
            eyebrow: 'Intelligence',
            title: 'Connect the AI you trust.',
            body:
                'Your questions and unseen message text you choose to '
                'analyze go to your configured provider. Normalized '
                'activity stays on this device.',
          ),
          const SizedBox(height: FlowSpace.xl),
          _StepAction(
            label: app.aiConnection == AiConnection.connected
                ? 'Intelligence connected'
                : 'Connect intelligence',
            icon: app.aiConnection == AiConnection.connected
                ? Icons.check_rounded
                : Icons.link_rounded,
            onPressed: _connect,
          ),
        ],
      ),
      2 => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Narrative(
            icon: Icons.sms_outlined,
            eyebrow: 'Transaction messages',
            title: 'Build activity without manual entry.',
            body:
                'Android asks before Fund Flow reads messages. Unseen text '
                'from the selected period is sent in protected batches to '
                'your configured AI, which decides what represents a '
                'transaction.',
          ),
          const SizedBox(height: FlowSpace.xl),
          _StepAction(
            label: app.importStatus.working
                ? 'Checking messages…'
                : 'Check messages',
            icon: Icons.sms_outlined,
            onPressed: app.importStatus.working
                ? null
                : () =>
                      ref.read(appControllerProvider.notifier).importMessages(),
          ),
          if (app.importStatus.message != null) ...[
            const SizedBox(height: FlowSpace.md),
            Text(
              app.importStatus.message!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: flow.attention),
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
            ? 'You can connect intelligence, check messages, or add a '
                  'transaction at any time.'
            : '${app.importStatus.imported} added and '
                  '${app.importStatus.skipped} skipped. Items needing '
                  'attention appear in Review.',
      ),
    };
  }

  Future<void> _connect() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const ConnectIntelligenceSheet(),
  );

  Future<void> _next(AppState app) async {
    if (_step < 3) {
      setState(() => _step++);
      return;
    }
    final prefs = app.preferences.copyWith(onboardingComplete: true);
    await ref.read(appControllerProvider.notifier).updatePreferences(prefs);
  }
}

class _StepAction extends StatelessWidget {
  const _StepAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, FlowDensity.minimumTarget),
        side: BorderSide(color: flow.line),
        foregroundColor: flow.ink,
        shape: const RoundedRectangleBorder(borderRadius: FlowRadius.sm),
      ),
      icon: Icon(icon, size: 18, color: flow.accent),
      label: Text(label),
    );
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
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 34, color: flow.accent),
        const SizedBox(height: FlowSpace.xl),
        Text(eyebrow, style: text.bodyMedium?.copyWith(color: flow.inkSoft)),
        const SizedBox(height: FlowSpace.sm),
        Text(title, style: text.headlineLarge),
        const SizedBox(height: FlowSpace.md),
        Text(body, style: text.bodyLarge?.copyWith(color: flow.inkSoft)),
      ],
    );
  }
}
