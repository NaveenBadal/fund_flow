import 'dart:io';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/transaction.dart';

/// What leaves the device, and the controls over it.
class PrivacyPage extends ConsumerStatefulWidget {
  const PrivacyPage({super.key});

  @override
  ConsumerState<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends ConsumerState<PrivacyPage> {
  bool _exporting = false;

  Future<void> _export() async {
    final app = ref.read(appControllerProvider).value;
    if (app == null || app.transactions.isEmpty) return;
    setState(() => _exporting = true);
    try {
      // App-specific external storage: writable with no runtime permission, and
      // visible to a file manager or a USB cable, which is what "export" has to
      // mean without a share sheet.
      final directory =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File(path.join(directory.path, 'fund-flow-$stamp.csv'));
      await file.writeAsString(_csv(app.transactions));
      if (!mounted) return;
      await fluxConfirm(
        context: context,
        title: 'Exported',
        message:
            '${app.transactions.length} transactions written to '
            '${file.path}',
        confirmLabel: 'Done',
        destructive: false,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// RFC-4180 quoting throughout: a merchant name with a comma in it is common,
  /// and unquoted output would silently shift every column after it.
  static String _csv(List<MoneyTransaction> items) {
    String cell(Object? value) =>
        '"${value?.toString().replaceAll('"', '""') ?? ''}"';
    final rows = <String>[
      [
        'date',
        'merchant',
        'category',
        'direction',
        'amount_minor',
        'currency',
        'account',
        'source',
        'review_state',
        'confidence',
        'note',
      ].map(cell).join(','),
      for (final item in items)
        [
          item.occurredAt.toIso8601String(),
          item.merchant,
          item.category,
          item.direction.name,
          item.amountMinor,
          item.currency,
          item.account,
          item.source.name,
          item.reviewState.name,
          item.confidence,
          item.note,
        ].map(cell).join(','),
    ];
    return '${rows.join('\n')}\n';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final prefs = app?.preferences;
    if (prefs == null) {
      return const FluxDetailPage(title: 'Privacy and data', slivers: []);
    }
    final controller = ref.read(appControllerProvider.notifier);

    return FluxDetailPage(
      title: 'Privacy and data',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: FluxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WHERE YOUR DATA IS',
                  style: FluxType.overline.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: FluxSpace.x3),
                _Boundary(
                  icon: Icons.phone_android_rounded,
                  title: 'On this phone',
                  detail:
                      'Every transaction, conversation, limit and setting, in '
                      'one database. The provider key is in the Android '
                      'keystore.',
                  tone: palette.income,
                ),
                const SizedBox(height: FluxSpace.x4),
                _Boundary(
                  icon: Icons.cloud_outlined,
                  title: 'Sent to your AI provider',
                  detail:
                      'The text of bank messages while they are being read, and '
                      'the results of local calculations while a question is '
                      'being answered. Nothing else, and nothing to us.',
                  tone: palette.attention,
                ),
                const SizedBox(height: FluxSpace.x4),
                _Boundary(
                  icon: Icons.dns_outlined,
                  title: 'Sent to Fund Flow',
                  detail:
                      'Nothing. There is no account and no server of ours. '
                      'Update checks read a public GitHub release list.',
                  tone: palette.income,
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'On this device',
            footer:
                'App lock uses your device unlock. Hidden amounts still count '
                'in every total — long-press the figure on Home to peek.',
            children: [
              FluxRow.toggle(
                title: 'Hide amounts',
                subtitle: 'Masks money on screen',
                icon: Icons.visibility_off_outlined,
                value: prefs.hideAmounts,
                onChanged: (value) => controller.updatePreferences(
                  prefs.copyWith(hideAmounts: value),
                ),
              ),
              FluxRow.toggle(
                title: 'Require unlock to open',
                subtitle: 'Fingerprint, face or device PIN',
                icon: Icons.lock_outline_rounded,
                value: prefs.lockApp,
                onChanged: (value) => controller.setAppLock(value),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Your copy',
            footer:
                'A plain CSV of every transaction, openable in any '
                'spreadsheet.',
            children: [
              FluxRow(
                title: 'Export transactions',
                subtitle: app!.transactions.isEmpty
                    ? 'Nothing to export yet'
                    : '${app.transactions.length} records',
                icon: Icons.file_download_outlined,
                busy: _exporting,
                onTap: app.transactions.isEmpty ? null : _export,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            children: [
              FluxRow(
                title: 'Erase everything',
                subtitle: 'Transactions, chats, limits and memory',
                icon: Icons.delete_forever_outlined,
                danger: true,
                onTap: () async {
                  final confirmed = await fluxConfirm(
                    context: context,
                    title: 'Erase everything?',
                    message:
                        'All ${app.transactions.length} transactions, every '
                        'conversation, every limit and everything the agent '
                        'remembers. This cannot be undone, and the messages in '
                        'your inbox are not affected.',
                    confirmLabel: 'Erase everything',
                  );
                  if (!confirmed) return;
                  await controller.eraseAllData();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Boundary extends StatelessWidget {
  const _Boundary({
    required this.icon,
    required this.title,
    required this.detail,
    required this.tone,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: tone),
        const SizedBox(width: FluxSpace.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: FluxType.label.copyWith(color: palette.text)),
              const SizedBox(height: 2),
              Text(
                detail,
                style: FluxType.caption.copyWith(
                  color: palette.textMuted,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
