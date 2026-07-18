import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../theme/app_theme.dart';
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
  late final FocusNode _amountFocus;
  late final FocusNode _merchantFocus;
  late String _type;
  late String _category;
  late String _currency;
  late DateTime _date;
  bool _saving = false;
  String? _amountError;
  String? _merchantError;

  @override
  void initState() {
    super.initState();
    final item = widget.initialExpense;
    _amount = TextEditingController(
      text: item == null ? '' : item.amount.toStringAsFixed(2),
    );
    _merchant = TextEditingController(text: item?.merchant ?? '');
    _tags = TextEditingController(text: item?.tags ?? '');
    _amountFocus = FocusNode();
    _merchantFocus = FocusNode();
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
    _amountFocus.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(allCategoryNamesProvider);
    if (!categories.contains(_category) && categories.isNotEmpty) {
      _category = categories.first;
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
      ),
      child: Theme(
        data: Theme.of(context),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: .94,
          minChildSize: .72,
          maxChildSize: .99,
          builder: (context, controller) => CustomScrollView(
            controller: controller,
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.initialExpense == null
                                  ? 'Add transaction'
                                  : 'Edit transaction',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.initialExpense == null
                                  ? 'Enter the amount and where it came from or went to'
                                  : 'Update the transaction details',
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
                          label: Text('Money out'),
                        ),
                        ButtonSegment(
                          value: 'income',
                          icon: Icon(Icons.south_west_rounded),
                          label: Text('Money in'),
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
                        color: scheme.surfaceContainerHigh,
                        borderRadius: AppRadius.all(AppRadius.xxl),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Amount',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _BouncyPrefix(
                                controller: _amount,
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _currency,
                                    dropdownColor: scheme.surfaceContainer,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: scheme.onSurface,
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
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextField(
                                  controller: _amount,
                                  focusNode: _amountFocus,
                                  autofocus: widget.initialExpense == null,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _merchantFocus.requestFocus(),
                                  onChanged: (_) {
                                    if (_amountError != null) {
                                      setState(() => _amountError = null);
                                    }
                                  },
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                      RegExp(r'^\d*\.?\d{0,2}'),
                                    ),
                                  ],
                                  style: AppTheme.money(
                                    Theme.of(
                                      context,
                                    ).textTheme.displayMedium?.copyWith(
                                      color: scheme.onSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  decoration: InputDecoration.collapsed(
                                    hintText: '0.00',
                                    hintStyle: TextStyle(
                                      color: scheme.onSurface.withValues(
                                        alpha: .24,
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
                    if (_amountError != null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          _amountError!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: scheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextField(
                      controller: _merchant,
                      focusNode: _merchantFocus,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_merchantError != null) {
                          setState(() => _merchantError = null);
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Source or destination',
                        hintText: 'Person, business, account, or bank',
                        prefixIcon: const Icon(Icons.swap_horiz_rounded),
                        errorText: _merchantError,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: categories.contains(_category)
                          ? _category
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'Category',
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
                      borderRadius: AppRadius.all(AppRadius.xl),
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: Text(
                          DateFormat('EEEE, d MMMM yyyy').format(_date),
                        ),
                        subtitle: Text(DateFormat('h:mm a').format(_date)),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _tags,
                      decoration: const InputDecoration(
                        labelText: 'Tags (optional)',
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_rounded),
                        label: Text(
                          widget.initialExpense == null
                              ? 'Add transaction'
                              : 'Save changes',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Choose transaction time',
    );
    if (!mounted) return;
    final time = pickedTime ?? TimeOfDay.fromDateTime(_date);
    setState(
      () => _date = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount.text.trim());
    final amountError = value == null || value <= 0
        ? 'Enter an amount greater than zero'
        : null;
    final merchantError = _merchant.text.trim().isEmpty
        ? 'Enter where this money came from or went to'
        : null;
    if (amountError != null || merchantError != null) {
      setState(() {
        _amountError = amountError;
        _merchantError = merchantError;
      });
      if (amountError != null) {
        _amountFocus.requestFocus();
      } else {
        _merchantFocus.requestFocus();
      }
      await HapticFeedback.heavyImpact();
      return;
    }
    setState(() => _saving = true);
    final old = widget.initialExpense;
    await widget.onSave(
      Expense(
        id: old?.id,
        amount: value!,
        currency: _currency,
        merchant: _merchant.text.trim(),
        category: _category,
        date: _date,
        originalSms: old?.originalSms ?? '',
        type: _type,
        tags: _tags.text.trim(),
        normalizedMerchant: old?.normalizedMerchant,
        account: old?.account,
        counterpartyAccount: old?.counterpartyAccount,
        status: 'settled',
        source: old?.source ?? 'manual',
        confidence: 1,
        transferGroup: old?.transferGroup,
        notes: old?.notes ?? '',
      ),
    );
    await HapticFeedback.lightImpact();
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _confirmDelete() async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete transaction?'),
            content: const Text(
              'This permanently removes it from your activity.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
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
        borderRadius: AppRadius.all(AppRadius.xl),
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

class _BouncyPrefix extends StatefulWidget {
  const _BouncyPrefix({required this.child, required this.controller});
  final Widget child;
  final TextEditingController controller;

  @override
  State<_BouncyPrefix> createState() => _BouncyPrefixState();
}

class _BouncyPrefixState extends State<_BouncyPrefix>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    widget.controller.addListener(_triggerBounce);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_triggerBounce);
    _controller.dispose();
    super.dispose();
  }

  void _triggerBounce() {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    _controller.forward(from: 0.0);
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
