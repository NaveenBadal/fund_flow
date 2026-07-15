import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/expense_provider.dart';
import '../services/database_helper.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/command_ui.dart';

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
    return CommandScaffold(
      eyebrow: 'Nothing enters memory invisibly',
      title: 'Signal provenance',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Every message the importer has considered, including why non-transactions were skipped.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                SegmentedButton<_Filter>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: _Filter.all, label: Text('All')),
                    ButtonSegment(
                      value: _Filter.imported,
                      label: Text('Imported'),
                    ),
                    ButtonSegment(
                      value: _Filter.skipped,
                      label: Text('Skipped'),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (value) =>
                      setState(() => _filter = value.first),
                ),
              ],
            ),
          ),
        ),
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
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
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
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
    final color = imported
        ? context.finance.income
        : _reasonColor(context, reason);
    final rawTime = entry['parsed_at'] as String? ?? '';
    final time = DateTime.tryParse(rawTime)?.toLocal();
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: .66),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(6),
          topRight: Radius.circular(26),
          bottomLeft: Radius.circular(26),
          bottomRight: Radius.circular(6),
        ),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: AppRadius.all(13),
          ),
          child: Icon(
            imported ? Icons.receipt_long_rounded : Icons.sms_outlined,
            color: color,
            size: 19,
          ),
        ),
        title: Text(
          entry['body'] as String? ?? '',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          time == null ? rawTime : DateFormat('d MMM · h:mm a').format(time),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: AppRadius.all(99),
          ),
          child: Text(
            imported ? 'Imported' : _label(reason),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    imported
                        ? 'A transaction was created from this message.'
                        : 'Skipped because: ${_label(reason)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!imported)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Retry'),
                  ),
              ],
            ),
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
      ? context.finance.expense
      : context.finance.warning;
}
