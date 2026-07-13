import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/expense_form_sheet.dart';
import '../widgets/ui/command_ui.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expenseListProvider);
    final hidden = ref.watch(privateModeProvider);
    return CommandScaffold(
      eyebrow: 'Your complete ledger',
      title: 'Activity',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SearchBar(
              controller: _search,
              elevation: const WidgetStatePropertyAll(0),
              leading: const Icon(Icons.search_rounded),
              hintText: 'Merchant, category, or tag',
              trailing: [
                if (_query.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'All', label: Text('All')),
                ButtonSegment(value: 'Expense', label: Text('Spent')),
                ButtonSegment(value: 'Income', label: Text('Received')),
              ],
              selected: {_filter},
              onSelectionChanged: (value) =>
                  setState(() => _filter = value.first),
            ),
          ),
        ),
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.error_outline_rounded,
              title: 'Activity unavailable',
              message: '$error',
            ),
          ),
          data: (all) {
            final filtered = all.where((e) {
              final matchesType =
                  _filter == 'All' ||
                  (_filter == 'Income' ? e.isIncome : !e.isIncome);
              final haystack = '${e.merchant} ${e.category} ${e.tags}'
                  .toLowerCase();
              return matchesType && haystack.contains(_query);
            }).toList();
            if (filtered.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: StatePanel(
                  icon: Icons.manage_search_rounded,
                  title: 'Nothing matches',
                  message: 'Try a different search or filter.',
                ),
              );
            }
            final groups = <DateTime, List<Expense>>{};
            for (final e in filtered) {
              groups.putIfAbsent(DateUtils.dateOnly(e.date), () => []).add(e);
            }
            final rows = <Object>[];
            for (final entry in groups.entries) {
              rows
                ..add(entry.key)
                ..addAll(entry.value);
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              sliver: SliverList.builder(
                itemCount: rows.length,
                itemBuilder: (context, index) {
                  final row = rows[index];
                  if (row is DateTime) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
                      child: Text(
                        _dayLabel(row),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    );
                  }
                  final e = row as Expense;
                  return _ActivityRow(
                    expense: e,
                    hidden: hidden,
                    onTap: () => _edit(e),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateUtils.dateOnly(DateTime.now());
    if (day == now) return 'TODAY';
    if (day == now.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('EEEE, d MMMM').format(day).toUpperCase();
  }

  Future<void> _edit(Expense expense) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ExpenseFormSheet(
        initialExpense: expense,
        onSave: (value) async {
          await ref.read(expenseListProvider.notifier).updateExpense(value);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
        onDelete: expense.id == null
            ? null
            : () async {
                await ref
                    .read(expenseListProvider.notifier)
                    .deleteExpense(expense.id!);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.expense,
    required this.hidden,
    required this.onTap,
  });
  final Expense expense;
  final bool hidden;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = expense.isIncome
        ? context.finance.income
        : categoryColor(expense.category);
    return InkWell(
      borderRadius: AppRadius.all(AppRadius.md),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.11),
                borderRadius: AppRadius.all(15),
              ),
              child: Icon(
                expense.isIncome
                    ? Icons.south_west_rounded
                    : categoryIcon(expense.category),
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${expense.category} · ${DateFormat('h:mm a').format(expense.date)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              hidden
                  ? maskAmount(expense.currency)
                  : '${expense.isIncome ? '+' : '−'}${formatAmount(expense.amount, expense.currency)}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: expense.isIncome ? context.finance.income : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
