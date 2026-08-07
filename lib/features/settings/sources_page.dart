import 'package:flutter/material.dart' show Icons, Slider;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/preferences.dart';

/// Where transactions come from: SMS history, and live notifications.
class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  int? _pendingLookback;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final prefs = app?.preferences;
    if (prefs == null) {
      return const FluxDetailPage(title: 'Message capture', slivers: []);
    }
    final controller = ref.read(appControllerProvider.notifier);
    final status = app!.importStatus;
    final lookback = _pendingLookback ?? prefs.messageLookbackDays;

    final counts = <String, int>{};
    for (final item in app.transactions) {
      counts[item.source.name] = (counts[item.source.name] ?? 0) + 1;
    }

    return FluxDetailPage(
      title: 'Message capture',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: Text(
            'Your bank already texts you every transaction. Fund Flow reads '
            'those messages, and only those — the text goes to the provider you '
            'connected so it can be turned into a record, and the record stays '
            'here.',
            style: FluxType.body.copyWith(color: palette.textMuted),
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'History',
            footer:
                'A typical inbox holds around 250 transaction messages a month, '
                'so 30 days keeps the first import to a couple of minutes. '
                'Live capture handles everything after that.',
            children: [
              FluxRow(
                title: 'How far back to read',
                value: '$lookback days',
                icon: Icons.history_rounded,
                subtitle:
                    'Between $minimumLookbackDays and '
                    '$maximumLookbackDays days',
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FluxSpace.x4,
                  0,
                  FluxSpace.x4,
                  FluxSpace.x3,
                ),
                child: Slider(
                  value: lookback.toDouble(),
                  min: minimumLookbackDays.toDouble(),
                  max: maximumLookbackDays.toDouble(),
                  divisions: maximumLookbackDays - minimumLookbackDays,
                  onChanged: (value) =>
                      setState(() => _pendingLookback = value.round()),
                  onChangeEnd: (value) async {
                    await controller.updatePreferences(
                      prefs.copyWith(messageLookbackDays: value.round()),
                    );
                    if (mounted) setState(() => _pendingLookback = null);
                  },
                ),
              ),
              FluxRow(
                title: status.working
                    ? 'Reading messages…'
                    : 'Read messages now',
                subtitle: status.working
                    ? '${status.checked} checked · ${status.imported} found'
                    : 'Skips anything already imported',
                icon: Icons.sync_rounded,
                busy: status.working,
                onTap: status.working
                    ? controller.stopMessageImport
                    : controller.importMessages,
                trailing: status.working
                    ? Text(
                        'Stop',
                        style: FluxType.label.copyWith(color: palette.danger),
                      )
                    : null,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Live capture',
            footer:
                'With notification access on, a transaction appears within '
                'seconds of the bank posting it, without waiting for the next '
                'import. Android grants this in system settings.',
            children: [
              FluxRow.toggle(
                title: 'Capture bank notifications',
                subtitle: prefs.captureNotifications
                    ? 'On — new transactions arrive as they happen'
                    : 'Off — transactions arrive when you import',
                icon: Icons.notifications_active_outlined,
                value: prefs.captureNotifications,
                onChanged: (value) => controller.setNotificationCapture(value),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'What you have',
            children: [
              FluxRow(
                title: 'From messages',
                value: '${counts['message'] ?? 0}',
              ),
              FluxRow(
                title: 'From notifications',
                value: '${counts['notification'] ?? 0}',
              ),
              FluxRow(
                title: 'Added by hand',
                value: '${counts['manual'] ?? 0}',
              ),
            ],
          ),
        ),
        if (status.retryable && status.message != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: FluxSpace.x6),
              child: FluxBanner(
                tone: FluxBannerTone.attention,
                title: 'Last import stopped',
                message: status.message!,
                icon: Icons.sms_failed_outlined,
                actionLabel: 'Try again',
                onAction: controller.importMessages,
              ),
            ),
          ),
      ],
    );
  }
}
