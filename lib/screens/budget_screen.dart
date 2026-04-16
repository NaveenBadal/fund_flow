import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/budget.dart';
import '../providers/expense_provider.dart';
import '../utils/category_utils.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  void _openEditSheet({
    Map<String, dynamic>? progress,
    List<String>? usedCategories,
    required List<String> allCategories,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => _BudgetEditSheet(
        existing: progress,
        usedCategories: usedCategories ?? [],
        allCategories: allCategories,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progressAsync = ref.watch(budgetProgressProvider);
    final allCategories = ref.watch(allCategoryNamesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: progressAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Failed to load budgets: $err',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (progressList) {
          final usedCategories =
              progressList.map((e) => e['category'] as String).toList();

          if (progressList.isEmpty) {
            return const _EmptyBudgetState();
          }

          return CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(child: _BudgetHeader()),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                sliver: SliverList.separated(
                  itemCount: progressList.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = progressList[index];
                    return _BudgetProgressCard(
                      progress: item,
                      onTap: () => _openEditSheet(
                        progress: item,
                        usedCategories: usedCategories
                            .where((c) => c != item['category'])
                            .toList(),
                        allCategories: allCategories,
                      ),
                      onDismissed: () {
                        ref
                            .read(budgetListProvider.notifier)
                            .remove(item['category'] as String);
                      },
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final progressAsync = ref.read(budgetProgressProvider);
          final usedCategories = (progressAsync.asData?.value ?? [])
              .map((e) => e['category'] as String)
              .toList();
          final allCats = ref.read(allCategoryNamesProvider);
          if (usedCategories.length >= allCats.length) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('All categories already have a budget.'),
              ),
            );
            return;
          }
          _openEditSheet(
            usedCategories: usedCategories,
            allCategories: allCats,
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Budget'),
      ),
    );
  }
}

class _BudgetHeader extends StatelessWidget {
  const _BudgetHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        'Monthly Budgets',
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyBudgetState extends StatelessWidget {
  const _EmptyBudgetState();

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
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 40,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No budgets set.',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add one.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BudgetProgressCard extends StatelessWidget {
  const _BudgetProgressCard({
    required this.progress,
    required this.onTap,
    required this.onDismissed,
  });

  final Map<String, dynamic> progress;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final category = progress['category'] as String;
    final spent = (progress['spent'] as num).toDouble();
    final limit = (progress['limit_amount'] as num).toDouble();
    // currency available for future multi-currency support

    final ratio = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final isOver = spent > limit;
    final isWarning = !isOver && ratio >= 0.7;

    final Color progressColor;
    if (isOver) {
      progressColor = Colors.red;
    } else if (isWarning) {
      progressColor = Colors.amber.shade700;
    } else {
      progressColor = Colors.green;
    }

    final catColor = categoryColor(category);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    return Dismissible(
      key: ValueKey('budget_$category'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete budget?'),
            content: Text('Remove the $category budget limit?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDismissed(),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: catColor.withValues(alpha: 0.15),
                      child: Icon(
                        categoryIcon(category),
                        size: 20,
                        color: catColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isOver)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Over budget',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      '${fmt.format(spent)} / ${fmt.format(limit)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isOver
                            ? Colors.red
                            : scheme.onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${(ratio * 100).toStringAsFixed(0)}% used',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
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

class _BudgetEditSheet extends ConsumerStatefulWidget {
  const _BudgetEditSheet({
    this.existing,
    required this.usedCategories,
    required this.allCategories,
  });

  /// When non-null, we're editing an existing budget entry.
  final Map<String, dynamic>? existing;

  /// Categories already in use (excluding the current one when editing).
  final List<String> usedCategories;

  /// Full list of available category names.
  final List<String> allCategories;

  @override
  ConsumerState<_BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends ConsumerState<_BudgetEditSheet> {
  late String _selectedCategory;
  late TextEditingController _amountController;
  bool _saving = false;
  final _formKey = GlobalKey<FormState>();

  List<String> get _availableCategories {
    if (widget.existing != null) {
      return [widget.existing!['category'] as String];
    }
    return widget.allCategories
        .where((c) => !widget.usedCategories.contains(c))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _selectedCategory = widget.existing!['category'] as String;
      final limit = (widget.existing!['limit_amount'] as num).toDouble();
      _amountController = TextEditingController(
        text: limit.toStringAsFixed(2),
      );
    } else {
      final available = _availableCategories;
      _selectedCategory = available.isNotEmpty ? available.first : '';
      _amountController = TextEditingController();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final amount = double.tryParse(_amountController.text.trim()) ?? 0;
    final budget = Budget(
      category: _selectedCategory,
      limitAmount: amount,
      currency: widget.existing?['currency'] as String? ?? 'INR',
    );

    await ref.read(budgetListProvider.notifier).upsert(budget);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isEditing ? 'Edit Budget' : 'Add Budget',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory.isEmpty ? null : _selectedCategory,
              decoration: InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                prefixIcon: _selectedCategory.isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          categoryIcon(_selectedCategory),
                          color: categoryColor(_selectedCategory),
                        ),
                      )
                    : const Icon(Icons.category_rounded),
              ),
              items: _availableCategories.map((cat) {
                return DropdownMenuItem(
                  value: cat,
                  child: Row(
                    children: [
                      Icon(
                        categoryIcon(cat),
                        color: categoryColor(cat),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(cat),
                    ],
                  ),
                );
              }).toList(),
              onChanged: isEditing
                  ? null
                  : (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
              validator: (val) =>
                  (val == null || val.isEmpty) ? 'Select a category' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Monthly limit (₹)',
                prefixIcon: const Icon(Icons.currency_rupee_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              validator: (val) {
                if (val == null || val.trim().isEmpty) {
                  return 'Enter an amount';
                }
                final amount = double.tryParse(val.trim());
                if (amount == null || amount <= 0) {
                  return 'Enter a valid positive amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(isEditing ? 'Update Budget' : 'Save Budget'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
