import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/expense_provider.dart';
import '../services/database_helper.dart';
import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/flow_ui.dart';

enum _Filter { all, imported, skipped }

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  _Filter _filter = _Filter.all;
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(parsedSmsAuditProvider);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width > AppBreakpoint.contentMax + 40
        ? (width - AppBreakpoint.contentMax) / 2
        : AppSpacing.page;
    return FlowScaffold(
      eyebrow: 'See what happened during import',
      title: 'Import history',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Review messages that became transactions and understand why others were skipped.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                const CoordinateLabel('Show', line: true),
                const SizedBox(height: 10),
                Row(
                  children: _Filter.values
                      .map(
                        (value) => Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: value == _Filter.skipped ? 0 : 7,
                            ),
                            child: _AuditPort(
                              label: value.name,
                              selected: _filter == value,
                              onTap: () => setState(() => _filter = value),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: Icon(Icons.hourglass_top_rounded, size: 32)),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.sms_failed_outlined,
              title: 'Inbox unavailable',
              message: '$error',
            ),
          ),
          data: (all) {
            final items = all
                .where(
                  (item) =>
                      _filter == _Filter.all ||
                      (_filter == _Filter.imported
                          ? item['has_expense'] == 1
                          : item['has_expense'] == 0),
                )
                .toList();
            if (items.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: StatePanel(
                  icon: Icons.sms_outlined,
                  title: 'Nothing here',
                  message:
                      'Messages matching this filter will appear after sync.',
                ),
              );
            }
            return SliverPadding(
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 40),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _SmsEvent(
                  entry: items[index],
                  onRetry: () => _retry(items[index]['body'] as String? ?? ''),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _retry(String body) async {
    await DatabaseHelper.instance.unmarkSmsParsed([body]);
    ref.invalidate(parsedSmsAuditProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Queued for the next sync.')),
      );
    }
  }
}

class _SmsEvent extends StatelessWidget {
  const _SmsEvent({required this.entry, required this.onRetry});
  final Map<String, dynamic> entry;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final imported = entry['has_expense'] == 1;
    final reason = entry['skip_reason'] as String? ?? '';
    final color = imported ? FlowColor.mint : _reasonColor(context, reason);
    final rawTime = entry['parsed_at'] as String? ?? '';
    final time = DateTime.tryParse(rawTime)?.toLocal();
    return CutSurface(
      accent: color,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoordinateLabel(
            imported ? 'Added to activity' : 'Skipped · ${_label(reason)}',
            color: color,
            line: true,
          ),
          const SizedBox(height: 12),
          Text(
            entry['body'] as String? ?? '',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          const SizedBox(height: 10),
          Text(
            time == null ? rawTime : DateFormat('d MMM · h:mm a').format(time),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: FlowColor.quiet(context),
              letterSpacing: .7,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  imported
                      ? 'A transaction was created from this message.'
                      : 'Reason skipped: ${_label(reason)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: FlowColor.quiet(context),
                  ),
                ),
              ),
              if (!imported)
                InkWell(
                  onTap: onRetry,
                  child: const CoordinateLabel(
                    'Queue again',
                    color: FlowColor.amber,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _label(String reason) => switch (reason) {
    'otp' => 'OTP',
    'promotional' => 'Promotion',
    'balance_alert' => 'Balance',
    'statement' => 'Statement',
    'not_financial' => 'Not financial',
    'parse_error' => 'Parse error',
    'no_response' => 'No response',
    'zero_amount' => 'No amount',
    _ => reason.isEmpty ? 'Skipped' : reason.replaceAll('_', ' '),
  };
  Color _reasonColor(BuildContext context, String reason) =>
      reason == 'parse_error' || reason == 'no_response'
      ? FlowColor.coral
      : FlowColor.amber;
}

class _AuditPort extends StatelessWidget {
  const _AuditPort({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      child: CutSurface(
        color: selected
            ? FlowColor.loom.withValues(alpha: .18)
            : FlowColor.raised(context),
        accent: selected ? FlowColor.proof : FlowColor.rule(context),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Center(
          child: Text(
            label[0].toUpperCase() + label.substring(1),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? FlowColor.proof : FlowColor.quiet(context),
              fontWeight: FontWeight.w900,
              letterSpacing: .8,
            ),
          ),
        ),
      ),
    ),
  );
}
