import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ExpenseFormSheet
//
// Unified add / edit / view sheet for expenses.
//   • initialExpense == null  →  Create mode ("Add expense")
//   • initialExpense != null  →  View mode initially; user taps edit icon to
//                                 switch into edit mode
// ─────────────────────────────────────────────────────────────────────────────

class ExpenseFormSheet extends ConsumerStatefulWidget {
  const ExpenseFormSheet({
    super.key,
    this.initialExpense,
    required this.onSave,
    this.onDelete,
  });

  /// Pass null to open in create mode.
  final Expense? initialExpense;
  final Future<void> Function(Expense) onSave;
  final VoidCallback? onDelete;

  @override
  ConsumerState<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends ConsumerState<ExpenseFormSheet> {
  late TextEditingController _merchantCtrl;
  late TextEditingController _amountCtrl;
  late TextEditingController _splitCtrl;
  late TextEditingController _tagInputCtrl;
  late String _category;
  late String _type; // 'expense' | 'income'
  late String _currency;
  late DateTime _date;
  late List<String> _tags;

  bool _editing = false;
  bool _saving = false;

  bool get _createMode => widget.initialExpense == null;

  @override
  void initState() {
    super.initState();
    final e = widget.initialExpense;
    _merchantCtrl = TextEditingController(text: e?.merchant ?? '');
    _amountCtrl = TextEditingController(
      text: e != null ? e.amount.toStringAsFixed(2) : '',
    );
    _splitCtrl = TextEditingController(
      text: e?.splitShare != null ? e!.splitShare!.toStringAsFixed(2) : '',
    );
    _tagInputCtrl = TextEditingController();
    _category = e?.category ?? 'Others';
    _type = e?.type ?? 'expense';
    _currency = e?.currency ?? 'INR';
    _date = e?.date ?? DateTime.now();
    _tags = e?.tagList.toList() ?? [];
    _editing = _createMode; // create mode starts in edit mode
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _amountCtrl.dispose();
    _splitCtrl.dispose();
    _tagInputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = ref.watch(allCategoryNamesProvider);

    // Ensure category is valid
    if (categories.isNotEmpty && !categories.contains(_category)) {
      _category = categories.first;
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(context).viewInsets.bottom + 28,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _createMode
                          ? 'Add expense'
                          : _editing
                          ? 'Edit expense'
                          : 'Expense detail',
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (!_createMode && !_editing)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () => setState(() => _editing = true),
                    ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      tooltip: 'Delete',
                      onPressed: widget.onDelete,
                    ),
                ],
              ),
              const SizedBox(height: 16),

              if (_editing) ...[
                // ── Type toggle ───────────────────────────────
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'expense',
                      label: Text('Expense'),
                      icon: Icon(Icons.arrow_upward_rounded),
                    ),
                    ButtonSegment(
                      value: 'income',
                      label: Text('Income'),
                      icon: Icon(Icons.arrow_downward_rounded),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) =>
                      setState(() => _type = s.first),
                  style: SegmentedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // ── Amount + currency row ─────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          prefixIcon: Icon(Icons.payments_outlined),
                          filled: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 90,
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        decoration: const InputDecoration(
                          labelText: 'Currency',
                          filled: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 16,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'INR', child: Text('INR')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                          DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                          DropdownMenuItem(value: 'SGD', child: Text('SGD')),
                          DropdownMenuItem(value: 'AED', child: Text('AED')),
                        ],
                        onChanged: (v) => setState(() => _currency = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ── Merchant ──────────────────────────────────
                TextField(
                  controller: _merchantCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Merchant / Description',
                    prefixIcon: Icon(Icons.store_outlined),
                    filled: true,
                  ),
                ),
                const SizedBox(height: 14),

                // ── Category ─────────────────────────────────
                DropdownButtonFormField<String>(
                  initialValue: categories.contains(_category) ? _category : null,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.sell_outlined),
                    filled: true,
                  ),
                  items: categories.map((c) {
                    final color = categoryColor(c);
                    final icon = categoryIcon(c);
                    return DropdownMenuItem(
                      value: c,
                      child: Row(
                        children: [
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: 8),
                          Text(c),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _category = v!),
                ),
                const SizedBox(height: 14),

                // ── Date ─────────────────────────────────────
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(DateFormat('EEEE, MMMM d, yyyy').format(_date)),
                  subtitle: const Text('Tap to change date'),
                  onTap: _pickDate,
                ),

                // ── Split share ───────────────────────────────
                if (_type == 'expense') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _splitCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          'My share (${symbolFor(_currency)}) — optional',
                      prefixIcon: const Icon(Icons.group_outlined),
                      filled: true,
                      helperText:
                          'Leave empty if you paid the full amount',
                    ),
                  ),
                ],
                const SizedBox(height: 14),

                // ── Tags chip editor ──────────────────────────
                _TagsEditor(
                  tags: _tags,
                  onChanged: (updated) =>
                      setState(() => _tags = updated),
                ),
                const SizedBox(height: 20),

                // ── Action buttons ────────────────────────────
                Row(
                  children: [
                    if (!_createMode) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _editing = false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _createMode
                                    ? Icons.add
                                    : Icons.save_outlined,
                              ),
                        label: Text(_createMode ? 'Add expense' : 'Save'),
                        onPressed: _saving ? null : _save,
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // ── View mode ─────────────────────────────────
                _DetailRow(
                  icon: expense.isIncome
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  label: 'Type',
                  value:
                      expense.isIncome ? 'Income' : 'Expense',
                ),
                _DetailRow(
                  icon: Icons.payments_outlined,
                  label: 'Amount',
                  value: formatAmount(expense.amount, expense.currency),
                ),
                _DetailRow(
                  icon: Icons.store_outlined,
                  label: 'Merchant',
                  value: expense.displayMerchant,
                ),
                _DetailRow(
                  icon: Icons.sell_outlined,
                  label: 'Category',
                  value: expense.category,
                ),
                _DetailRow(
                  icon: Icons.event_outlined,
                  label: 'Date',
                  value: DateFormat('EEEE, MMMM d, yyyy').format(expense.date),
                ),
                if (expense.splitShare != null)
                  _DetailRow(
                    icon: Icons.group_outlined,
                    label: 'My share',
                    value: formatAmount(expense.splitShare!, expense.currency),
                  ),
                if (expense.tagList.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Icon(Icons.local_offer_outlined,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary),
                        ...expense.tagList.map(
                          (t) => Chip(
                            label: Text(t),
                            labelStyle:
                                Theme.of(context).textTheme.labelMedium,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Original SMS',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.primary),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SelectableText(
                    expense.originalSms,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Expense get expense => widget.initialExpense!;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final merchant = _merchantCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (merchant.isEmpty || amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid merchant and amount.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final splitShare = double.tryParse(_splitCtrl.text.trim());
      final updated = Expense(
        id: widget.initialExpense?.id,
        amount: amount,
        currency: _currency,
        merchant: merchant,
        category: _category,
        date: _date,
        originalSms: widget.initialExpense?.originalSms ?? 'Manual entry',
        type: _type,
        tags: _tags.join(','),
        splitShare: splitShare,
        isRecurring: widget.initialExpense?.isRecurring ?? false,
        normalizedMerchant: widget.initialExpense?.normalizedMerchant,
      );
      await widget.onSave(updated);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── Tags chip editor ─────────────────────────────────────────────────────────

class _TagsEditor extends StatefulWidget {
  const _TagsEditor({required this.tags, required this.onChanged});

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_TagsEditor> createState() => _TagsEditorState();
}

class _TagsEditorState extends State<_TagsEditor> {
  final _ctrl = TextEditingController();

  void _addTag(String raw) {
    final parts = raw.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty);
    final updated = [...widget.tags];
    for (final tag in parts) {
      if (!updated.contains(tag)) updated.add(tag);
    }
    widget.onChanged(updated);
    _ctrl.clear();
  }

  void _removeTag(String tag) {
    widget.onChanged(widget.tags.where((t) => t != tag).toList());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: widget.tags
                .map(
                  (t) => InputChip(
                    label: Text(t),
                    onDeleted: () => _removeTag(t),
                    visualDensity: VisualDensity.compact,
                  ),
                )
                .toList(),
          ),
        if (widget.tags.isNotEmpty) const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'Add tag…',
            hintText: 'e.g. business, reimbursable',
            prefixIcon: const Icon(Icons.local_offer_outlined),
            filled: true,
            suffixIcon: IconButton(
              icon: Icon(Icons.add_circle_outline, color: scheme.primary),
              onPressed: () {
                if (_ctrl.text.trim().isNotEmpty) _addTag(_ctrl.text);
              },
            ),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) _addTag(v);
          },
          onChanged: (v) {
            if (v.endsWith(',')) _addTag(v);
          },
        ),
      ],
    );
  }
}

// ─── Detail row (view mode) ──────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              Text(
                value,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
