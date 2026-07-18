import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/finance_summary.dart';
import '../../domain/transaction.dart';
import '../../ui/components/current_button.dart';
import '../../ui/components/current_field.dart';
import '../../ui/components/current_header.dart';
import '../../ui/foundation/current_colors.dart';
import '../../ui/format/money_format.dart';
import 'transaction_editor_sheet.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _State();
}

class _State extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  String _query = '';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final values = app.transactions
        .where(
          (e) => '${e.merchant} ${e.category}'.toLowerCase().contains(_query),
        )
        .toList();
    return Column(
      children: [
        CurrentHeader(
          title: 'Activity',
          contextLine: 'Your money record',
          actions: [
            CurrentIconAction(
              icon: app.preferences.hideAmounts
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: app.preferences.hideAmounts
                  ? 'Show amounts'
                  : 'Hide amounts',
              onPressed: () => ref
                  .read(appControllerProvider.notifier)
                  .updatePreferences(
                    app.preferences.copyWith(
                      hideAmounts: !app.preferences.hideAmounts,
                    ),
                  ),
            ),
            CurrentIconAction(
              icon: Icons.add_rounded,
              label: 'Add transaction',
              onPressed: () => _editor(),
            ),
          ],
        ),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: values.isEmpty && _query.isEmpty
                ? _EmptyActivity(
                    onAdd: _editor,
                    onImport: () => ref
                        .read(appControllerProvider.notifier)
                        .importMessages(),
                    importing: app.importStatus.working,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 40),
                    children: [
                      _MonthSummary(
                        values: app.transactions,
                        hidden: app.preferences.hideAmounts,
                      ),
                      const SizedBox(height: 20),
                      CurrentField(
                        controller: _search,
                        hint: 'Search activity',
                        prefixIcon: Icons.search_rounded,
                        onSubmitted: (_) {},
                        suffix: IconButton(
                          tooltip: 'Clear search',
                          onPressed: _query.isEmpty
                              ? null
                              : () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                      ValueListenableBuilder(
                        valueListenable: _search,
                        builder: (_, value, child) {
                          if (value.text.toLowerCase() != _query) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(
                                  () => _query = value.text.toLowerCase(),
                                );
                              }
                            });
                          }
                          return const SizedBox(height: 20);
                        },
                      ),
                      if (values.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Text(
                            'No activity matches your search.',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        )
                      else
                        ..._groups(values, app.preferences.hideAmounts),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  List<Widget> _groups(List<MoneyTransaction> values, bool hidden) {
    final groups = <DateTime, List<MoneyTransaction>>{};
    for (final item in values) {
      groups
          .putIfAbsent(DateUtils.dateOnly(item.occurredAt), () => [])
          .add(item);
    }
    return [
      for (final entry in groups.entries) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
          child: Text(
            DateFormat('EEEE, d MMMM').format(entry.key),
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: context.current.muted),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.current.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.current.rule),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < entry.value.length; i++) ...[
                _TransactionRow(
                  item: entry.value[i],
                  hidden: hidden,
                  onTap: () => _inspect(entry.value[i]),
                ),
                if (i != entry.value.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: context.current.rule,
                  ),
              ],
            ],
          ),
        ),
      ],
    ];
  }

  Future<void> _editor([MoneyTransaction? item]) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TransactionEditorSheet(transaction: item),
  );
  Future<void> _inspect(MoneyTransaction item) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => _TransactionInspector(
      item: item,
      onEdit: () {
        Navigator.pop(sheet);
        _editor(item);
      },
    ),
  );
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.values, required this.hidden});
  final List<MoneyTransaction> values;
  final bool hidden;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = values.where(
      (e) => e.occurredAt.year == now.year && e.occurredAt.month == now.month,
    );
    final summary = FinanceEngine.summarize(month);
    final review = values
        .where((e) => e.reviewState == ReviewState.needsReview)
        .length;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This month',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.current.muted),
          ),
          const SizedBox(height: 7),
          if (summary.isEmpty)
            Text(
              'No activity yet',
              style: Theme.of(context).textTheme.headlineMedium,
            )
          else
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                for (final s in summary)
                  Text(
                    '${formatMoney(s.outgoingMinor, s.currency, hidden: hidden)} spent',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
              ],
            ),
          if (review > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$review ${review == 1 ? 'transaction needs' : 'transactions need'} review',
              style: TextStyle(color: context.current.review),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({
    required this.onAdd,
    required this.onImport,
    required this.importing,
  });
  final VoidCallback onAdd, onImport;
  final bool importing;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      const SizedBox(height: 40),
      Icon(
        Icons.receipt_long_outlined,
        size: 36,
        color: context.current.intelligence,
      ),
      const SizedBox(height: 24),
      Text(
        'Your money record starts here.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 14),
      Text(
        'Check transaction messages or add something manually. Every imported transaction can be reviewed and corrected.',
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
      ),
      const SizedBox(height: 26),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          CurrentButton(
            label: importing ? 'Checking messages…' : 'Check messages',
            icon: Icons.sms_outlined,
            onPressed: importing ? null : onImport,
          ),
          CurrentButton(
            label: 'Add transaction',
            icon: Icons.add_rounded,
            style: CurrentButtonStyle.outline,
            onPressed: onAdd,
          ),
        ],
      ),
    ],
  );
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.item,
    required this.hidden,
    required this.onTap,
  });
  final MoneyTransaction item;
  final bool hidden;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: item.reviewState == ReviewState.needsReview
                    ? context.current.review
                    : item.direction == TransactionDirection.incoming
                    ? context.current.income
                    : context.current.expense,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.merchant,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.reviewState == ReviewState.needsReview
                        ? 'Needs review · ${item.category}'
                        : item.category,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: item.reviewState == ReviewState.needsReview
                          ? context.current.review
                          : context.current.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${item.direction == TransactionDirection.incoming ? '+' : '−'}${formatMoney(item.amountMinor, item.currency, hidden: hidden)}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontFamily: 'Space Grotesk'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _TransactionInspector extends ConsumerWidget {
  const _TransactionInspector({required this.item, required this.onEdit});
  final MoneyTransaction item;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.current.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            item.merchant,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(item.amountMinor, item.currency),
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 20),
          Text(
            '${item.direction == TransactionDirection.incoming ? 'Money in' : 'Money out'} · ${item.category} · ${DateFormat('d MMM y, h:mm a').format(item.occurredAt)}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.current.muted),
          ),
          const SizedBox(height: 20),
          if (item.sourceText != null)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Original message'),
              children: [SelectableText(item.sourceText!)],
            ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: CurrentButton(
                  label: 'Edit',
                  style: CurrentButtonStyle.outline,
                  onPressed: onEdit,
                ),
              ),
              if (item.reviewState == ReviewState.needsReview) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: CurrentButton(
                    label: 'Confirm',
                    onPressed: () => ref
                        .read(appControllerProvider.notifier)
                        .confirmTransaction(item)
                        .then((_) {
                          if (context.mounted) Navigator.pop(context);
                        }),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          CurrentButton(
            label: 'Delete transaction',
            style: CurrentButtonStyle.text,
            onPressed: () => ref
                .read(appControllerProvider.notifier)
                .deleteTransaction(item.id!)
                .then((_) {
                  if (context.mounted) Navigator.pop(context);
                }),
          ),
        ],
      ),
    ),
  );
}
