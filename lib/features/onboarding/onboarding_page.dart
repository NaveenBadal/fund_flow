import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../design/flux.dart';
import '../../domain/ai_provider.dart';
import '../settings/intelligence_page.dart';

/// Four screens, in the order the app actually needs them.
///
/// The provider is connected *before* the import, and the import cannot be
/// reached until the connection has been validated against the live provider.
/// The old flow let someone paste a wrong key and discover it minutes later as a
/// failed import, with no way to tell whether the key, the model or their inbox
/// was the problem.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pages = PageController();
  int _index = 0;

  void _next() {
    if (_index >= 3) return;
    _pages.animateToPage(
      _index + 1,
      duration: FluxMotion.normal,
      curve: FluxMotion.emphasized,
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final controller = ref.read(appControllerProvider.notifier);
    final prefs = ref.read(appControllerProvider).value?.preferences;
    if (prefs == null) return;
    await controller.updatePreferences(
      prefs.copyWith(onboardingComplete: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final connected = app?.aiConnection == AiConnection.connected;
    final status = app?.importStatus ?? const ImportStatus();

    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FluxSpace.page,
                FluxSpace.x4,
                FluxSpace.page,
                FluxSpace.x2,
              ),
              child: Row(
                children: [
                  for (var slot = 0; slot < 4; slot++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: AnimatedContainer(
                          duration: FluxMotion.duration(
                            context,
                            FluxMotion.normal,
                          ),
                          height: 3,
                          decoration: ShapeDecoration(
                            color: slot <= _index
                                ? palette.iris
                                : palette.surfaceHighest,
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (value) => setState(() => _index = value),
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Step(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Your bank already tells you everything',
                    body:
                        'Every card tap, every transfer, every salary credit '
                        'arrives as a message. Fund Flow reads those messages '
                        'and turns them into a ledger you never have to type.',
                    footer:
                        'Nothing is uploaded to us. There is no account to '
                        'make.',
                    actionLabel: 'How it works',
                    onAction: _next,
                  ),
                  _Step(
                    icon: Icons.key_rounded,
                    title: 'Connect an AI provider',
                    body:
                        'Reading a message and answering a question both need a '
                        'model. You bring your own key, so you pay the provider '
                        'directly and nothing passes through anyone else.',
                    footer: connected
                        ? 'Connected and verified.'
                        : 'The key is checked against the provider before it is '
                              'saved.',
                    actionLabel: connected ? 'Continue' : 'Connect a provider',
                    onAction: connected
                        ? _next
                        : () => showConnectSheet(
                            context: context,
                            ref: ref,
                            initialProvider:
                                app?.preferences.aiProvider ??
                                AiProvider.ollama,
                          ),
                    secondaryLabel: connected ? null : 'Skip for now',
                    onSecondary: connected ? null : _next,
                    badge: connected ? 'Connected' : null,
                  ),
                  _Step(
                    icon: Icons.sms_outlined,
                    title: 'Read your messages',
                    body:
                        'Fund Flow looks only at messages that describe a '
                        'transaction, over the last 30 days. The text of those '
                        'goes to your provider to be read; the resulting records '
                        'stay on this phone.',
                    footer: status.working
                        ? '${status.checked} checked · ${status.imported} '
                              'transactions found'
                        : 'You can do this later from settings instead.',
                    actionLabel: status.working
                        ? 'Reading…'
                        : (status.imported > 0
                              ? 'Continue'
                              : 'Read my messages'),
                    busy: status.working,
                    onAction: status.working
                        ? null
                        : (status.imported > 0
                              ? _next
                              : () => ref
                                    .read(appControllerProvider.notifier)
                                    .importMessages()),
                    secondaryLabel: status.working ? null : 'Skip',
                    onSecondary: status.working ? null : _next,
                    badge: status.imported > 0
                        ? '${status.imported} found'
                        : null,
                  ),
                  _Step(
                    icon: Icons.lock_outline_rounded,
                    title: 'Keep it yours',
                    body:
                        'Turn on notification capture and new transactions '
                        'appear within seconds of the bank posting them. Turn on '
                        'app lock and your device unlock guards the app.',
                    footer:
                        'Both can be changed any time in Settings > Privacy.',
                    actionLabel: 'Start using Fund Flow',
                    onAction: _finish,
                    extra: Column(
                      children: [
                        FluxGroup(
                          margin: EdgeInsets.zero,
                          children: [
                            FluxRow.toggle(
                              title: 'Capture bank notifications',
                              icon: Icons.notifications_active_outlined,
                              value:
                                  app?.preferences.captureNotifications ??
                                  false,
                              onChanged: (value) => ref
                                  .read(appControllerProvider.notifier)
                                  .setNotificationCapture(value),
                            ),
                            FluxRow.toggle(
                              title: 'Require unlock to open',
                              icon: Icons.lock_outline_rounded,
                              value: app?.preferences.lockApp ?? false,
                              onChanged: (value) => ref
                                  .read(appControllerProvider.notifier)
                                  .setAppLock(value),
                            ),
                          ],
                        ),
                      ],
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

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    required this.footer,
    required this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.badge,
    this.busy = false,
    this.extra,
  });

  final IconData icon;
  final String title;
  final String body;
  final String footer;
  final String actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? badge;
  final bool busy;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpace.page,
        FluxSpace.x6,
        FluxSpace.page,
        FluxSpace.x6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  // Short steps sit centred; a long one scrolls. Pinning every
                  // step to the top left a screen's worth of void under the
                  // three-line ones.
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: FluxSpace.x6),
                      ShaderMask(
                        shaderCallback: (bounds) =>
                            FluxPalette.ai.createShader(bounds),
                        blendMode: BlendMode.srcIn,
                        child: Icon(
                          icon,
                          size: 34,
                          color: const Color(0xFFFFFFFF),
                        ),
                      ),
                      const SizedBox(height: FluxSpace.x6),
                      Text(
                        title,
                        style: FluxType.display.copyWith(
                          color: palette.text,
                          fontSize: 30,
                        ),
                      ),
                      const SizedBox(height: FluxSpace.x4),
                      Text(
                        body,
                        style: FluxType.bodyLarge.copyWith(
                          color: palette.textMuted,
                          height: 1.6,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(height: FluxSpace.x5),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FluxChip(
                            label: badge!,
                            icon: Icons.check_rounded,
                            selected: true,
                          ),
                        ),
                      ],
                      if (extra != null) ...[
                        const SizedBox(height: FluxSpace.x6),
                        extra!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Text(
            footer,
            style: FluxType.caption.copyWith(color: palette.textFaint),
          ),
          const SizedBox(height: FluxSpace.x4),
          FluxButton(label: actionLabel, busy: busy, onPressed: onAction),
          if (secondaryLabel != null) ...[
            const SizedBox(height: FluxSpace.x2),
            FluxButton(
              label: secondaryLabel!,
              kind: FluxButtonKind.ghost,
              onPressed: onSecondary,
            ),
          ],
        ],
      ),
    );
  }
}
