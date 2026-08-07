import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../design/flux.dart';
import '../../domain/ai_provider.dart';
import '../../domain/preferences.dart';
import 'about_page.dart';
import 'appearance_page.dart';
import 'intelligence_page.dart';
import 'memory_page.dart';
import 'privacy_page.dart';
import 'sources_page.dart';

/// The settings hub.
///
/// A pushed hierarchy, not a stack of sheets. The old app nested settings sheets
/// inside sheets, which loses any sense of where you are and gives the back
/// gesture two meanings.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final prefs = app?.preferences;
    final connected = app?.aiConnection == AiConnection.connected;

    return FluxDetailPage(
      title: 'Settings',
      slivers: [
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Intelligence',
            footer:
                'Fund Flow reads your messages and answers questions through a '
                'provider you choose and pay for directly.',
            children: [
              FluxRow(
                title: 'Provider',
                value: prefs == null
                    ? '—'
                    : providerInfo(prefs.aiProvider).label,
                icon: Icons.auto_awesome_outlined,
                iconColor: connected ? palette.iris : palette.attention,
                subtitle: connected ? null : 'Not connected',
                chevron: true,
                onTap: () =>
                    fluxPush(context, (context) => const IntelligencePage()),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Your money',
            children: [
              FluxRow(
                title: 'Message capture',
                subtitle: 'SMS history and live notifications',
                value: prefs == null
                    ? null
                    : '${prefs.messageLookbackDays} days',
                icon: Icons.sms_outlined,
                chevron: true,
                onTap: () =>
                    fluxPush(context, (context) => const SourcesPage()),
              ),
              FluxRow(
                title: 'What the agent remembers',
                icon: Icons.psychology_outlined,
                chevron: true,
                onTap: () => fluxPush(context, (context) => const MemoryPage()),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'App',
            children: [
              FluxRow(
                title: 'Privacy and data',
                subtitle: 'What leaves the device, lock, export, erase',
                icon: Icons.shield_outlined,
                chevron: true,
                onTap: () =>
                    fluxPush(context, (context) => const PrivacyPage()),
              ),
              FluxRow(
                title: 'Appearance',
                value: switch (prefs?.appearance) {
                  null => '—',
                  AppearancePreference.system => 'Match device',
                  AppearancePreference.light => 'Light',
                  AppearancePreference.dark => 'Dark',
                },
                icon: Icons.contrast_rounded,
                chevron: true,
                onTap: () =>
                    fluxPush(context, (context) => const AppearancePage()),
              ),
              FluxRow(
                title: 'About and updates',
                icon: Icons.info_outline_rounded,
                chevron: true,
                onTap: () => fluxPush(context, (context) => const AboutPage()),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FluxSpace.page,
              FluxSpace.x8,
              FluxSpace.page,
              0,
            ),
            child: Text(
              'Every transaction, conversation and limit lives in one database '
              'on this phone. There is no Fund Flow account and no server of '
              'ours to sign in to.',
              style: FluxType.caption.copyWith(color: palette.textFaint),
            ),
          ),
        ),
      ],
    );
  }
}
