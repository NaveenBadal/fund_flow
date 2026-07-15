import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/budget.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(budgetProgressProvider);
    final hidden = ref.watch(privateModeProvider);
    final categories = ref.watch(allCategoryNamesProvider);
    return CommandScaffold(
      eyebrow: 'Soft constraints that adapt',
      title: 'Pressure boundaries',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, categories, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add limit'),
      ),
      slivers: [
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.track_changes_rounded,
              title: 'Limits unavailable',
              message: '$error',
            ),
          ),
          data: (items) {
            if (items.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: StatePanel(
                  icon: Icons.track_changes_rounded,
                  title: 'Set your first boundary',
                  message:
                      'Choose one category where a monthly limit would make decisions easier.',
                ),
              );
            }
            final totalLimit = items.fold<double>(
              0,
              (sum, b) => sum + (b['limit_amount'] as num).toDouble(),
            );
            final totalSpent = items.fold<double>(
              0,
              (sum, b) => sum + (b['spent'] as num).toDouble(),
            );
            final currency = items.first['currency'] as String? ?? 'INR';
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.inverseSurface,
                        borderRadius: AppRadius.all(AppRadius.xxl),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PLANNED SPENDING',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface
                                      .withValues(alpha: .6),
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            hidden
                                ? maskAmount(currency)
                                : formatAmount(totalLimit, currency),
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onInverseSurface,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: AppRadius.all(99),
                            child: LinearProgressIndicator(
                              value: totalLimit == 0
                                  ? 0
                                  : (totalSpent / totalLimit).clamp(0, 1),
                              minHeight: 10,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .onInverseSurface
                                  .withValues(alpha: .14),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            '${(totalLimit == 0 ? 0 : totalSpent / totalLimit * 100).round()}% used across ${items.length} categories',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface
                                      .withValues(alpha: .68),
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SectionLabel('Where pressure is accumulating'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final b = items[index];
                      return _LimitRow(
                        data: b,
                        hidden: hidden,
                        onTap: () => _edit(context, ref, categories, b),
                        onDelete: () => ref
                            .read(budgetListProvider.notifier)
                            .remove(b['category'] as String),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<String> categories,
    Map<String, dynamic>? existing,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LimitSheet(categories: categories, existing: existing),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.data,
    required this.hidden,
    required this.onTap,
    required this.onDelete,
  });
  final Map<String, dynamic> data;
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) {
    final category = data['category'] as String;
    final spent = (data['spent'] as num).toDouble();
    final limit = (data['limit_amount'] as num).toDouble();
    final currency = data['currency'] as String? ?? 'INR';
    final ratio = limit == 0 ? 0.0 : spent / limit;
    final color = ratio >= 1
        ? context.finance.expense
        : ratio >= .8
        ? context.finance.warning
        : categoryColor(category);
    return Dismissible(
      key: ValueKey(category),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Remove $category limit?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: AppRadius.all(AppRadius.lg),
        ),
        child: const Icon(Icons.delete_outline_rounded),
      ),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.all(AppRadius.lg),
        child: InkWell(
          borderRadius: AppRadius.all(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: .12),
                        borderRadius: AppRadius.all(14),
                      ),
                      child: Icon(
                        categoryIcon(category),
                        color: color,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      hidden
                          ? maskAmount(currency)
                          : '${formatAmount(spent, currency)} / ${formatAmount(limit, currency)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: AppRadius.all(99),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0, 1),
                    minHeight: 8,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LimitSheet extends ConsumerStatefulWidget {
  const _LimitSheet({required this.categories, this.existing});
  final List<String> categories;
  final Map<String, dynamic>? existing;
  @override
  ConsumerState<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends ConsumerState<_LimitSheet> {
  late String _category;
  late final TextEditingController _amount;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _category =
        widget.existing?['category'] as String? ?? widget.categories.first;
    _amount = TextEditingController(
      text: widget.existing == null
          ? ''
          : (widget.existing!['limit_amount'] as num).toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String currency =
        (widget.existing?['currency'] as String?) ??
        ref.watch(preferredCurrencyProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'New spending limit' : 'Adjust limit',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 22),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: widget.categories
                .map((name) => DropdownMenuItem(value: name, child: Text(name)))
                .toList(),
            onChanged: widget.existing == null
                ? (value) => setState(() => _category = value!)
                : null,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: 'Monthly limit',
              prefixText: '${symbolFor(currency)} ',
            ),
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save limit'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount.text);
    if (value == null || value <= 0) return;
    setState(() => _saving = true);
    await ref
        .read(budgetListProvider.notifier)
        .upsert(
          Budget(
            category: _category,
            limitAmount: value,
            currency:
                widget.existing?['currency'] as String? ??
                ref.read(preferredCurrencyProvider),
          ),
        );
    if (mounted) Navigator.pop(context);
  }
}
