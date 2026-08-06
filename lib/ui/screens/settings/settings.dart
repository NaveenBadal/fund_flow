import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_state.dart';
import '../../../domain/ai_provider.dart';
import '../../../domain/preferences.dart';
import '../../theme/ff_theme.dart';
import '../../widgets/ff_controls.dart';
import '../../widgets/ff_group.dart';
import '../../widgets/ff_screen.dart';
import '../../widgets/ff_sheet.dart';
import 'automation.dart';
import 'intelligence.dart';
import 'updates.dart';

/// Settings.
///
/// Two things the app does on your behalf at the top — reading messages, and
/// answering questions — then the handful of preferences worth revisiting, and
/// then the app itself. Anything that only mattered once lives where it was
/// decided, not here.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    final preferences = app.preferences;
    final c = context.ff;

    return FFScreen(
      title: 'Settings',
      slivers: [
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'What Fund Flow does for you',
            separatorIndent: 57,
            children: [
              FFRow(
                title: 'Message capture',
                subtitle: preferences.captureNotifications
                    ? 'Messages and live notifications'
                    : 'Payment messages only',
                icon: Icons.bolt_rounded,
                iconColor: c.orange,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AutomationScreen(),
                  ),
                ),
              ),
              FFRow(
                title: 'Intelligence',
                subtitle: switch (app.aiConnection) {
                  AiConnection.connected =>
                    'Connected to ${providerInfo(preferences.aiProvider).label}',
                  AiConnection.checking => 'Checking the connection…',
                  AiConnection.rejected => 'Needs attention',
                  AiConnection.disconnected => 'Not connected',
                },
                icon: Icons.auto_awesome_rounded,
                iconColor: const Color(0xff5856d6),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const IntelligenceScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Preferences',
            children: [
              FFRow(
                title: 'Appearance',
                value: switch (preferences.appearance) {
                  AppearancePreference.system => 'Automatic',
                  AppearancePreference.light => 'Light',
                  AppearancePreference.dark => 'Dark',
                },
                onTap: () async {
                  final choice = await showFFPicker<AppearancePreference>(
                    context,
                    title: 'Appearance',
                    current: preferences.appearance,
                    options: const [
                      (AppearancePreference.system, 'Match this device'),
                      (AppearancePreference.light, 'Light'),
                      (AppearancePreference.dark, 'Dark'),
                    ],
                  );
                  if (choice == null) return;
                  await controller.updatePreferences(
                    preferences.copyWith(appearance: choice),
                  );
                },
              ),
              FFRow(
                title: 'Currency',
                value: preferences.currency,
                onTap: () async {
                  final choice = await showFFPicker<String>(
                    context,
                    title: 'Currency',
                    current: preferences.currency,
                    options: _currencies,
                    footer:
                        'Used for new manual records and for totals when the '
                        'ledger has no clear majority.',
                  );
                  if (choice == null) return;
                  await controller.updatePreferences(
                    preferences.copyWith(currency: choice),
                  );
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Privacy',
            footer:
                'Transactions never leave this device. Only your questions, '
                'and message text you choose to have read, are sent to your '
                'provider.',
            children: [
              FFRow(
                title: 'Hide amounts',
                chevron: false,
                trailing: FFSwitch(
                  value: preferences.hideAmounts,
                  onChanged: (value) => controller.updatePreferences(
                    preferences.copyWith(hideAmounts: value),
                  ),
                ),
              ),
              FFRow(
                title: 'Require unlock',
                subtitle: 'Ask for this device’s authentication on open',
                chevron: false,
                trailing: FFSwitch(
                  value: preferences.lockApp,
                  onChanged: controller.setAppLock,
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Fund Flow',
            children: [
              FFRow(
                title: 'App updates',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const UpdatesScreen(),
                  ),
                ),
              ),
              FFRow(
                title: 'About',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            footer:
                'Removes the questions and answers in the open conversation. '
                'Transactions are untouched.',
            children: [
              FFRow(
                title: 'Delete this conversation',
                destructive: true,
                centered: true,
                chevron: false,
                onTap: () async {
                  final approved = await ffConfirm(
                    context,
                    title: 'Delete this conversation?',
                    message:
                        'Its questions and answers go. Your transactions and '
                        'other conversations stay.',
                    confirm: 'Delete',
                  );
                  if (approved) await controller.clearConversation();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _currencies = <(String, String)>[
  ('INR', 'Indian rupee · INR'),
  ('USD', 'US dollar · USD'),
  ('EUR', 'Euro · EUR'),
  ('GBP', 'British pound · GBP'),
  ('AED', 'UAE dirham · AED'),
  ('SGD', 'Singapore dollar · SGD'),
  ('AUD', 'Australian dollar · AUD'),
  ('CAD', 'Canadian dollar · CAD'),
  ('JPY', 'Japanese yen · JPY'),
  ('CHF', 'Swiss franc · CHF'),
];

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return FFScreen(
      title: 'About',
      large: false,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              FFSpace.xl,
              FFSpace.gutter,
              FFSpace.xxl,
            ),
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(Icons.waves_rounded, size: 38, color: c.tint),
                ),
                const SizedBox(height: FFSpace.lg),
                Text('Fund Flow', style: FFText.title2),
                const SizedBox(height: 2),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? 'Version ${snapshot.data!.version} · build ${snapshot.data!.buildNumber}'
                        : ' ',
                    style: FFText.footnote.copyWith(color: c.secondaryLabel),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'How it works',
            children: [
              const _Note(
                icon: Icons.sms_rounded,
                title: 'Reads payment messages',
                detail:
                    'Bank and wallet messages become transactions. Personal '
                    'conversations are never touched.',
              ),
              const _Note(
                icon: Icons.lock_rounded,
                title: 'Keeps the ledger local',
                detail:
                    'Every transaction lives in a database on this device and '
                    'is never uploaded anywhere.',
              ),
              const _Note(
                icon: Icons.auto_awesome_rounded,
                title: 'Answers from your own records',
                detail:
                    'Questions go to the provider you connect. Answers are '
                    'checked back against the ledger before you see them.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Padding(
      padding: const EdgeInsets.all(FFSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: c.tint),
          const SizedBox(width: FFSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: FFText.headline),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: FFText.footnote.copyWith(color: c.secondaryLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
