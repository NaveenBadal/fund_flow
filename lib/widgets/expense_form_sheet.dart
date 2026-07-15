import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';

class ExpenseFormSheet extends ConsumerStatefulWidget {
  const ExpenseFormSheet({
    super.key,
    this.initialExpense,
    required this.onSave,
    this.onDelete,
  });
  final Expense? initialExpense;
  final Future<void> Function(Expense) onSave;
  final VoidCallback? onDelete;
  @override
  ConsumerState<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<ExpenseFormSheet> {
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _tags;
  late String _type;
  late String _category;
  late String _currency;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialExpense;
    _amount = TextEditingController(
      text: item == null ? '' : item.amount.toStringAsFixed(2),
    );
    _merchant = TextEditingController(text: item?.merchant ?? '');
    _tags = TextEditingController(text: item?.tags ?? '');
    _type = item?.type ?? 'expense';
    _category = item?.category ?? 'Others';
    _currency = item?.currency ?? ref.read(preferredCurrencyProvider);
    _date = item?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(allCategoryNamesProvider);
    if (!categories.contains(_category) && categories.isNotEmpty) {
      _category = categories.first;
    }
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .65,
      maxChildSize: .98,
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.initialExpense == null
                              ? 'Create a money memory'
                              : 'Inspect this memory',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.initialExpense == null
                              ? 'Flow will include it in future reasoning'
                              : 'Correct the machine’s understanding',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      onPressed: _confirmDelete,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: scheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              20,
              24,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 28,
            ),
            sliver: SliverList.list(
              children: [
                SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 'expense',
                      icon: Icon(Icons.north_east_rounded),
                      label: Text('Energy out'),
                    ),
                    ButtonSegment(
                      value: 'income',
                      icon: Icon(Icons.south_west_rounded),
                      label: Text('Energy in'),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (value) =>
                      setState(() => _type = value.first),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface,
                    borderRadius: AppRadius.all(AppRadius.xxl),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MAGNITUDE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onInverseSurface.withValues(alpha: .6),
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _currency,
                              dropdownColor: scheme.inverseSurface,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    color: scheme.onInverseSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                              items:
                                  const [
                                        'INR',
                                        'USD',
                                        'EUR',
                                        'GBP',
                                        'SGD',
                                        'AED',
                                      ]
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(value),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (value) =>
                                  setState(() => _currency = value!),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _amount,
                              autofocus: widget.initialExpense == null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(
                                    color: scheme.onInverseSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                              decoration: InputDecoration.collapsed(
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: scheme.onInverseSurface.withValues(
                                    alpha: .35,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _merchant,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Where did the money meet the world?',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: categories.contains(_category)
                      ? _category
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Meaning',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: categories
                      .map(
                        (name) => DropdownMenuItem(
                          value: name,
                          child: Row(
                            children: [
                              Icon(
                                categoryIcon(name),
                                size: 18,
                                color: categoryColor(name),
                              ),
                              const SizedBox(width: 10),
                              Text(name),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _category = value!),
                ),
                const SizedBox(height: 14),
                Material(
                  color: scheme.surfaceContainerLow,
                  borderRadius: AppRadius.all(AppRadius.md),
                  child: ListTile(
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: Text(DateFormat('EEEE, d MMMM yyyy').format(_date)),
                    subtitle: Text(DateFormat('h:mm a').format(_date)),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickDate,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _tags,
                  decoration: const InputDecoration(
                    labelText: 'Personal memory cues (optional)',
                    hintText: 'travel, work, shared',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                ),
                if (widget.initialExpense != null) ...[
                  const SizedBox(height: 20),
                  _SourcePanel(expense: widget.initialExpense!),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(
                      widget.initialExpense == null
                          ? 'Commit to memory'
                          : 'Update memory',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount.text.trim());
    if (value == null || value <= 0 || _merchant.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount and description.')),
      );
      return;
    }
    setState(() => _saving = true);
    final old = widget.initialExpense;
    await widget.onSave(
      Expense(
        id: old?.id,
        amount: value,
        currency: _currency,
        merchant: _merchant.text.trim(),
        category: _category,
        date: _date,
        originalSms: old?.originalSms ?? '',
        type: _type,
        tags: _tags.text.trim(),
        splitShare: old?.splitShare,
        isRecurring: old?.isRecurring ?? false,
        normalizedMerchant: old?.normalizedMerchant,
      ),
    );
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _confirmDelete() async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete movement?'),
            content: const Text(
              'This will remove it from every report and budget.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (yes) widget.onDelete?.call();
  }
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final message = expense.originalSms.trim();
    final hasMessage = message.isNotEmpty;

    final identity = Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .1),
            borderRadius: AppRadius.all(12),
          ),
          child: Icon(
            hasMessage ? Icons.sms_outlined : Icons.edit_note_rounded,
            size: 19,
            color: scheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Source',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasMessage ? 'Imported from bank SMS' : 'Added manually',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: AppRadius.all(99),
          ),
          child: Text(
            hasMessage ? 'SMS' : 'MANUAL',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
            ),
          ),
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .45)),
      ),
      child: hasMessage
          ? Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 3,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                shape: const Border(),
                collapsedShape: const Border(),
                title: identity,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: .55,
                      ),
                      borderRadius: AppRadius.all(AppRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectionArea(
                          child: Text(
                            message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: message),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Original SMS copied.'),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy message'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : Padding(padding: const EdgeInsets.all(16), child: identity),
    );
  }
}
