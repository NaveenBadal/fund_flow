import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/preferences.dart';
import '../sheets/connect_intelligence_sheet.dart';
import '../sheets/message_intelligence_sheet.dart';
import '../sheets/update_sheet.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// Settings, grouped by what someone came to do.
///
/// The previous screen grouped by system component — intelligence, sources,
/// privacy, advanced — which is the builder's taxonomy, not the user's.
/// These groups each answer one intent: how the app reads money, what the
/// AI is, who can see what, how it looks, and the app itself. Opened as a
/// sheet: settings are visited a handful of times ever, and a permanent
/// destination would cost a quarter of the navigation bar.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    final flow = context.flow;
    final connected = app.aiConnection == AiConnection.connected;

    return Column(
      children: [
        const SizedBox(height: FlowSpace.sm),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: flow.line,
            borderRadius: FlowRadius.pill,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FlowSpace.xl,
            FlowSpace.sm,
            FlowSpace.xl,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                primary: true,
                padding: EdgeInsets.fromLTRB(
                  FlowSpace.xl,
                  FlowSpace.sm,
                  FlowSpace.xl,
                  FlowSpace.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  // ------------------------------------ reading your money
                  const _Section('Reading your money'),
                  _Group(
                    children: [
                      _SettingsRow(
                        icon: Icons.sms_outlined,
                        title: 'Transaction messages',
                        detail: _importDetail(app),
                        trailing: app.importStatus.working
                            ? _CompactAction(
                                label: 'Stop',
                                onTap: controller.stopMessageImport,
                              )
                            : _CompactAction(
                                label: 'Check',
                                onTap: controller.importMessages,
                              ),
                        onTap: () =>
                            _sheet(context, const MessageIntelligenceSheet()),
                      ),
                      _SettingsRow(
                        icon: Icons.history_rounded,
                        title: 'Message history',
                        detail:
                            'Check the last '
                            '${app.preferences.messageLookbackDays} days',
                        trailing: _Stepper(
                          value: app.preferences.messageLookbackDays,
                          onChanged: (value) => controller.updatePreferences(
                            app.preferences.copyWith(
                              messageLookbackDays: value,
                            ),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.notifications_none_rounded,
                        title: 'Notification capture',
                        detail: app.preferences.captureNotifications
                            ? 'Reading payment notifications'
                            : 'Off',
                        trailing: Switch(
                          value: app.preferences.captureNotifications,
                          onChanged: controller.setNotificationCapture,
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.settings_outlined,
                        title: 'Android permissions',
                        detail: 'Manage SMS and notification access',
                        onTap: openAppSettings,
                      ),
                    ],
                  ),

                  // ------------------------------------------ intelligence
                  const _Section('The intelligence behind it'),
                  _Group(
                    children: [
                      _SettingsRow(
                        icon: Icons.psychology_alt_outlined,
                        title: 'AI connection',
                        detail: switch (app.aiConnection) {
                          AiConnection.connected =>
                            'Connected · ${app.preferences.aiModel}',
                          AiConnection.checking => 'Checking connection…',
                          AiConnection.rejected => 'Connection needs attention',
                          _ => 'Not connected',
                        },
                        signal: connected ? flow.income : flow.attention,
                        onTap: () => _sheet(
                          context,
                          const ConnectIntelligenceSheet(),
                          scrollControlled: true,
                        ),
                      ),
                      if (connected)
                        _SettingsRow(
                          icon: Icons.link_off_rounded,
                          title: 'Disconnect intelligence',
                          detail: 'Removes the API key from secure storage',
                          onTap: () => _confirm(
                            context,
                            title: 'Disconnect intelligence?',
                            body:
                                'The API key is removed from secure storage. '
                                'Your transactions stay on this device.',
                            action: 'Disconnect',
                            onConfirmed: controller.disconnectAi,
                          ),
                        ),
                    ],
                  ),

                  // ----------------------------------------------- privacy
                  const _Section('Who sees what'),
                  _Group(
                    children: [
                      _SettingsRow(
                        icon: Icons.shield_outlined,
                        title: 'Data boundary',
                        detail:
                            'Activity stays local; questions and opted-in '
                            'message text go to your provider',
                        onTap: () => _dataBoundary(context),
                      ),
                      _SettingsRow(
                        icon: Icons.visibility_off_outlined,
                        title: 'Hide amounts',
                        detail: app.preferences.hideAmounts
                            ? 'Amounts are hidden'
                            : 'Amounts are visible',
                        trailing: Switch(
                          value: app.preferences.hideAmounts,
                          onChanged: (value) => controller.updatePreferences(
                            app.preferences.copyWith(hideAmounts: value),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'App lock',
                        detail: app.preferences.lockApp
                            ? 'Authentication required to open'
                            : 'Off',
                        trailing: Switch(
                          value: app.preferences.lockApp,
                          onChanged: controller.setAppLock,
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.delete_sweep_outlined,
                        title: 'Clear conversations',
                        detail: 'Transactions are not removed',
                        onTap: () => _confirm(
                          context,
                          title: 'Clear all conversations?',
                          body:
                              'Every chat thread is deleted. Transactions '
                              'and corrections are not touched.',
                          action: 'Clear',
                          onConfirmed: controller.clearConversation,
                        ),
                      ),
                    ],
                  ),

                  // ------------------------------------------- how it looks
                  const _Section('How it looks'),
                  _Group(
                    children: [
                      _SettingsRow(
                        icon: Icons.brightness_6_outlined,
                        title: 'Appearance',
                        detail: _appearance(app.preferences.appearance),
                        onTap: () => _choice<AppearancePreference>(
                          context,
                          title: 'Appearance',
                          values: AppearancePreference.values,
                          selected: app.preferences.appearance,
                          label: _appearance,
                          onChosen: (value) => controller.updatePreferences(
                            app.preferences.copyWith(appearance: value),
                          ),
                        ),
                      ),
                      _SettingsRow(
                        icon: Icons.currency_rupee_rounded,
                        title: 'Primary currency',
                        detail: app.preferences.currency,
                        onTap: () => _choice<String>(
                          context,
                          title: 'Primary currency',
                          values: const ['INR', 'USD', 'EUR', 'GBP', 'AED'],
                          selected: app.preferences.currency,
                          label: (value) => value,
                          onChosen: (value) => controller.updatePreferences(
                            app.preferences.copyWith(currency: value),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ---------------------------------------------- the app
                  const _Section('This app'),
                  _Group(
                    children: [
                      _SettingsRow(
                        icon: Icons.system_update_alt_rounded,
                        title: 'App updates',
                        detail: 'Verified development releases from GitHub',
                        onTap: () => _sheet(
                          context,
                          const UpdateSheet(),
                          scrollControlled: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _importDetail(AppState app) => switch (app.importStatus.phase) {
    ImportPhase.idle => 'Tap to see how messages are read',
    ImportPhase.requestingPermission => 'Requesting permission…',
    ImportPhase.reading => 'Reading recent messages…',
    ImportPhase.understanding =>
      'Understanding ${app.importStatus.checked} messages…',
    ImportPhase.paused => app.importStatus.message ?? 'Analysis paused safely',
    ImportPhase.stopped => app.importStatus.message ?? 'Import stopped',
    ImportPhase.rateLimited =>
      app.importStatus.message ?? 'Provider is rate limited · tap to retry',
    ImportPhase.providerDisconnected =>
      app.importStatus.message ?? 'Reconnect intelligence to continue',
    ImportPhase.invalidResponse =>
      app.importStatus.message ?? 'AI response was invalid · tap to retry',
    ImportPhase.complete =>
      '${app.importStatus.imported} added · ${app.importStatus.skipped} skipped',
    ImportPhase.error => app.importStatus.message ?? 'Could not check messages',
  };

  static String _appearance(AppearancePreference value) => switch (value) {
    AppearancePreference.system => 'Follow device',
    AppearancePreference.light => 'Light',
    AppearancePreference.dark => 'Dark',
  };

  static Future<void> _sheet(
    BuildContext context,
    Widget child, {
    bool scrollControlled = false,
  }) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: scrollControlled,
    builder: (sheet) => child,
  );

  /// One-tap destructive rows get a stop first: on a screen of rows, an
  /// accidental tap must never be able to delete anything.
  static Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
    required Future<void> Function() onConfirmed,
  }) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) {
      final flow = sheet.flow;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: FlowSpace.sm),
              Text(
                body,
                style: Theme.of(
                  sheet,
                ).textTheme.bodyMedium?.copyWith(color: flow.inkSoft),
              ),
              const SizedBox(height: FlowSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheet),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          FlowDensity.minimumTarget,
                        ),
                        side: BorderSide(color: flow.line),
                        foregroundColor: flow.ink,
                        shape: const RoundedRectangleBorder(
                          borderRadius: FlowRadius.sm,
                        ),
                      ),
                      child: const Text('Keep'),
                    ),
                  ),
                  const SizedBox(width: FlowSpace.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await onConfirmed();
                        if (sheet.mounted) Navigator.pop(sheet);
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          FlowDensity.minimumTarget,
                        ),
                        backgroundColor: flow.expense,
                        foregroundColor: Colors.white,
                        shape: const RoundedRectangleBorder(
                          borderRadius: FlowRadius.sm,
                        ),
                      ),
                      child: Text(action),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  static Future<void> _choice<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required void Function(T) onChosen,
  }) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) {
      final flow = sheet.flow;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FlowSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: FlowSpace.md),
              for (final value in values)
                InkWell(
                  onTap: () {
                    onChosen(value);
                    Navigator.pop(sheet);
                  },
                  borderRadius: FlowRadius.sm,
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: FlowDensity.minimumTarget,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FlowSpace.sm,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label(value),
                            style: Theme.of(sheet).textTheme.bodyLarge,
                          ),
                        ),
                        if (value == selected)
                          Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: flow.accent,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  static Future<void> _dataBoundary(BuildContext context) =>
      showModalBottomSheet<void>(
        context: context,
        builder: (sheet) {
          final flow = sheet.flow;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(FlowSpace.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your data boundary',
                    style: Theme.of(sheet).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: FlowSpace.md),
                  Text(
                    'Transactions, categories, corrections, conversation '
                    'history, approved financial memory, agent telemetry and '
                    'the import audit stay in the app database on this '
                    'device. Questions, and unseen message text you have '
                    'opted in, are sent to the AI endpoint you configure. '
                    'Telemetry never stores prompts or answers. Raw message '
                    'and exchange history can be cleared without touching '
                    'transactions.',
                    style: Theme.of(
                      sheet,
                    ).textTheme.bodyLarge?.copyWith(color: flow.inkSoft),
                  ),
                ],
              ),
            ),
          );
        },
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      FlowSpace.xxs,
      FlowSpace.lg,
      FlowSpace.xxs,
      FlowSpace.sm,
    ),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: context.flow.inkSoft),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      decoration: BoxDecoration(
        color: flow.raised,
        borderRadius: FlowRadius.lg,
        border: Border.all(
          color: flow.line,
          width: 1,
        ),
        boxShadow: FlowElevation.low(Theme.of(context).brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(
                height: 1,
                indent: FlowSpace.lg,
                endIndent: FlowSpace.lg,
                color: flow.line.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.detail,
    this.trailing,
    this.signal,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? trailing;

  /// Small status dot beside the icon, for rows whose state matters at a
  /// glance. Colour is reinforcement — the detail line states it in words.
  final Color? signal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: FlowDensity.comfortableRow,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FlowSpace.lg,
          vertical: FlowSpace.sm,
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: flow.inkSoft),
                if (signal != null)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: signal,
                        shape: BoxShape.circle,
                        border: Border.all(color: flow.raised, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: FlowSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 1),
                  Text(
                    detail,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: FlowSpace.sm),
              trailing!,
            ] else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: flow.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _CompactAction extends StatelessWidget {
  const _CompactAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return InkWell(
      onTap: onTap,
      borderRadius: FlowRadius.pill,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: 32,
          minWidth: FlowDensity.minimumTarget,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
        decoration: BoxDecoration(
          color: flow.sunken,
          borderRadius: FlowRadius.pill,
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: flow.accent),
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Fewer days',
          iconSize: 18,
          color: flow.inkSoft,
          onPressed: () => onChanged(
            (value - 7).clamp(minimumLookbackDays, maximumLookbackDays),
          ),
          icon: const Icon(Icons.remove_rounded),
        ),
        Text('${value}d', style: Theme.of(context).textTheme.labelLarge),
        IconButton(
          tooltip: 'More days',
          iconSize: 18,
          color: flow.inkSoft,
          onPressed: () => onChanged(
            (value + 7).clamp(minimumLookbackDays, maximumLookbackDays),
          ),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
