import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';

// ignore: unused_element
Color _categoryColor(String category) {
  switch (category.toLowerCase()) {
    case 'food':
      return Colors.orange;
    case 'transport':
      return Colors.blue;
    case 'utilities':
      return Colors.green;
    case 'entertainment':
      return Colors.deepPurple;
    case 'shopping':
      return Colors.pink;
    case 'health':
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

enum _SmsFilter { all, withTransaction, skipped }

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  _SmsFilter _filter = _SmsFilter.all;

  List<Map<String, dynamic>> _applyFilter(List<Map<String, dynamic>> items) {
    switch (_filter) {
      case _SmsFilter.all:
        return items;
      case _SmsFilter.withTransaction:
        return items.where((e) => e['has_expense'] == 1).toList();
      case _SmsFilter.skipped:
        return items.where((e) => e['has_expense'] == 0).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auditAsync = ref.watch(parsedSmsAuditProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: auditAsync.when(
          data: (items) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Parsed SMS Audit'),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${items.length}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          loading: () => const Text('Parsed SMS Audit'),
          error: (err, stack) => Text('Error: $err'),
        ),
      ),
      body: auditAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: scheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load audit data',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          final filtered = _applyFilter(items);
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _FilterChipRow(
                  current: _filter,
                  total: items.length,
                  withTransaction:
                      items.where((e) => e['has_expense'] == 1).length,
                  skipped: items.where((e) => e['has_expense'] == 0).length,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ),
              if (filtered.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyFilterState(filter: _filter),
                )
              else
                SliverPadding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  sliver: SliverList.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _AuditTile(entry: filtered[index]),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _FilterChipRow extends StatelessWidget {
  const _FilterChipRow({
    required this.current,
    required this.total,
    required this.withTransaction,
    required this.skipped,
    required this.onChanged,
  });

  final _SmsFilter current;
  final int total;
  final int withTransaction;
  final int skipped;
  final ValueChanged<_SmsFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: Text('All ($total)'),
            selected: current == _SmsFilter.all,
            onSelected: (_) => onChanged(_SmsFilter.all),
          ),
          FilterChip(
            label: Text('With transaction ($withTransaction)'),
            selected: current == _SmsFilter.withTransaction,
            onSelected: (_) => onChanged(_SmsFilter.withTransaction),
          ),
          FilterChip(
            label: Text('Skipped ($skipped)'),
            selected: current == _SmsFilter.skipped,
            onSelected: (_) => onChanged(_SmsFilter.skipped),
          ),
        ],
      ),
    );
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.filter});

  final _SmsFilter filter;

  String get _message {
    switch (filter) {
      case _SmsFilter.all:
        return 'No parsed SMS found.\nSync SMS from the dashboard to populate this list.';
      case _SmsFilter.withTransaction:
        return 'No SMS with detected transactions.';
      case _SmsFilter.skipped:
        return 'No skipped SMS entries.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sms_failed_outlined,
              size: 52,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 16),
            Text(
              _message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditTile extends StatefulWidget {
  const _AuditTile({required this.entry});

  final Map<String, dynamic> entry;

  @override
  State<_AuditTile> createState() => _AuditTileState();
}

class _AuditTileState extends State<_AuditTile> {
  bool _expanded = false;

  String _formatParsedAt(String raw) {
    try {
      final dt = DateTime.parse(raw).toLocal();
      return DateFormat('MMM d, yyyy • h:mm a').format(dt);
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final body = widget.entry['body'] as String? ?? '';
    final parsedAt = widget.entry['parsed_at'] as String? ?? '';
    final hasExpense = widget.entry['has_expense'] == 1;

    final badgeColor = hasExpense ? Colors.green : Colors.blueGrey;
    final badgeLabel = hasExpense ? 'Transaction' : 'Skipped';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: badgeColor.withValues(alpha: 0.12),
                    child: Icon(
                      hasExpense
                          ? Icons.receipt_rounded
                          : Icons.do_not_disturb_alt_rounded,
                      size: 18,
                      color: badgeColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState: _expanded
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: Text(
                            body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          secondChild: Text(
                            body,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.access_time_rounded,
                              size: 13,
                              color: scheme.onSurface.withValues(alpha: 0.45),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatParsedAt(parsedAt),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badgeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: badgeColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 18,
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
