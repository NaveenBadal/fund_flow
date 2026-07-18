import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/preferences.dart';
import '../../ui/components/current_group.dart';
import '../../ui/components/current_header.dart';
import '../../ui/components/current_switch.dart';
import '../../ui/foundation/current_colors.dart';
import 'connect_intelligence_sheet.dart';

class YouScreen extends ConsumerWidget {
  const YouScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    return Column(
      children: [
        CurrentHeader(title: 'You', contextLine: 'Preferences and privacy'),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
              children: [
                const CurrentSectionTitle('Intelligence'),
                CurrentGroup(
                  children: [
                    CurrentRow(
                      title: 'AI connection',
                      detail: switch (app.aiConnection) {
                        AiConnection.connected =>
                          'Connected · ${app.preferences.aiModel}',
                        AiConnection.checking => 'Checking connection…',
                        AiConnection.rejected => 'Connection needs attention',
                        _ => 'Not connected',
                      },
                      leading: Icons.psychology_alt_outlined,
                      signal: app.aiConnection == AiConnection.connected
                          ? context.current.income
                          : context.current.review,
                      onTap: () => _connect(context),
                    ),
                  ],
                ),
                const CurrentSectionTitle('Money sources'),
                CurrentGroup(
                  children: [
                    CurrentRow(
                      title: 'Transaction messages',
                      detail: _importDetail(app),
                      leading: Icons.sms_outlined,
                      signal: context.current.intelligence,
                      onTap: app.importStatus.working
                          ? null
                          : () => controller.importMessages(),
                    ),
                    CurrentRow(
                      title: 'Message history',
                      detail:
                          'Check the last ${app.preferences.messageLookbackDays} days',
                      leading: Icons.history_rounded,
                      trailing: _Stepper(
                        value: app.preferences.messageLookbackDays,
                        onChanged: (v) => controller.updatePreferences(
                          app.preferences.copyWith(messageLookbackDays: v),
                        ),
                      ),
                    ),
                    CurrentRow(
                      title: 'Automatic notification capture',
                      detail: app.preferences.captureNotifications
                          ? 'On'
                          : 'Off',
                      leading: Icons.notifications_none_rounded,
                      trailing: CurrentSwitch(
                        value: app.preferences.captureNotifications,
                        label: 'Automatic notification capture',
                        onChanged: (v) => controller.updatePreferences(
                          app.preferences.copyWith(captureNotifications: v),
                        ),
                      ),
                    ),
                  ],
                ),
                const CurrentSectionTitle('Privacy'),
                CurrentGroup(
                  children: [
                    CurrentRow(
                      title: 'Hide amounts',
                      detail: app.preferences.hideAmounts
                          ? 'Amounts are hidden'
                          : 'Amounts are visible',
                      leading: Icons.visibility_off_outlined,
                      trailing: CurrentSwitch(
                        value: app.preferences.hideAmounts,
                        label: 'Hide amounts',
                        onChanged: (v) => controller.updatePreferences(
                          app.preferences.copyWith(hideAmounts: v),
                        ),
                      ),
                    ),
                    CurrentRow(
                      title: 'App lock',
                      detail: app.preferences.lockApp
                          ? 'Authentication required'
                          : 'Off',
                      leading: Icons.lock_outline_rounded,
                      trailing: CurrentSwitch(
                        value: app.preferences.lockApp,
                        label: 'App lock',
                        onChanged: controller.setAppLock,
                      ),
                    ),
                    CurrentRow(
                      title: 'Data boundary',
                      detail:
                          'Activity stays local; candidates and questions go to your provider',
                      leading: Icons.shield_outlined,
                      onTap: () => _privacy(context),
                    ),
                  ],
                ),
                const CurrentSectionTitle('Preferences'),
                CurrentGroup(
                  children: [
                    CurrentRow(
                      title: 'Appearance',
                      detail: _appearance(app.preferences.appearance),
                      leading: Icons.brightness_6_outlined,
                      onTap: () =>
                          _appearanceSheet(context, ref, app.preferences),
                    ),
                    CurrentRow(
                      title: 'Primary currency',
                      detail: app.preferences.currency,
                      leading: Icons.currency_rupee_rounded,
                      onTap: () =>
                          _currencySheet(context, ref, app.preferences),
                    ),
                  ],
                ),
                const CurrentSectionTitle('Advanced'),
                CurrentGroup(
                  children: [
                    CurrentRow(
                      title: 'Open Android permissions',
                      detail: 'Manage SMS and notification access',
                      leading: Icons.settings_outlined,
                      onTap: openAppSettings,
                    ),
                    CurrentRow(
                      title: 'Clear conversation',
                      detail: 'Transactions are not removed',
                      leading: Icons.delete_sweep_outlined,
                      onTap: controller.clearConversation,
                    ),
                    if (app.aiConnection == AiConnection.connected)
                      CurrentRow(
                        title: 'Disconnect intelligence',
                        detail: 'Removes the API key from secure storage',
                        leading: Icons.link_off_rounded,
                        onTap: controller.disconnectAi,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _importDetail(AppState app) => switch (app.importStatus.phase) {
    ImportPhase.idle => 'Tap to check recent messages',
    ImportPhase.requestingPermission => 'Requesting permission…',
    ImportPhase.reading => 'Reading recent messages…',
    ImportPhase.understanding =>
      'Understanding ${app.importStatus.checked} messages…',
    ImportPhase.complete =>
      '${app.importStatus.imported} added · ${app.importStatus.skipped} skipped',
    ImportPhase.error => app.importStatus.message ?? 'Could not check messages',
  };
  String _appearance(AppearancePreference v) => switch (v) {
    AppearancePreference.system => 'Follow device',
    AppearancePreference.light => 'Light',
    AppearancePreference.dark => 'Dark',
  };
  Future<void> _connect(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const ConnectIntelligenceSheet(),
  );
  Future<void> _privacy(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your data boundary',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            Text(
              'Transactions, normalized fields, categories, corrections, and conversation history stay in the app database on this device. Candidate transaction message text and questions are sent to the AI endpoint you configure.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    ),
  );
  Future<void> _appearanceSheet(
    BuildContext context,
    WidgetRef ref,
    AppPreferences prefs,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Appearance',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 18),
            CurrentGroup(
              children: [
                for (final value in AppearancePreference.values)
                  CurrentRow(
                    title: _appearance(value),
                    trailing: prefs.appearance == value
                        ? Icon(
                            Icons.check_rounded,
                            color: context.current.intelligence,
                          )
                        : null,
                    onTap: () {
                      ref
                          .read(appControllerProvider.notifier)
                          .updatePreferences(prefs.copyWith(appearance: value));
                      Navigator.pop(sheet);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Future<void> _currencySheet(
    BuildContext context,
    WidgetRef ref,
    AppPreferences prefs,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Primary currency',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 18),
            CurrentGroup(
              children: [
                for (final value in const ['INR', 'USD', 'EUR', 'GBP', 'AED'])
                  CurrentRow(
                    title: value,
                    trailing: prefs.currency == value
                        ? Icon(
                            Icons.check_rounded,
                            color: context.current.intelligence,
                          )
                        : null,
                    onTap: () {
                      ref
                          .read(appControllerProvider.notifier)
                          .updatePreferences(prefs.copyWith(currency: value));
                      Navigator.pop(sheet);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        tooltip: 'Decrease days',
        onPressed: () => onChanged((value - 7).clamp(7, 180)),
        icon: const Icon(Icons.remove_rounded),
      ),
      Text('${value}d', style: Theme.of(context).textTheme.labelLarge),
      IconButton(
        tooltip: 'Increase days',
        onPressed: () => onChanged((value + 7).clamp(7, 180)),
        icon: const Icon(Icons.add_rounded),
      ),
    ],
  );
}
