import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../flow_os/primitives/loom_mark.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
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
  late final TextEditingController _amount = TextEditingController(
    text: widget.initialExpense == null
        ? ''
        : widget.initialExpense!.amount.toStringAsFixed(2),
  );
  late final TextEditingController _merchant = TextEditingController(
    text: widget.initialExpense?.merchant ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.initialExpense?.tags ?? '',
  );
  final _amountFocus = FocusNode();
  final _merchantFocus = FocusNode();
  late String _type = widget.initialExpense?.type ?? 'expense';
  late String _category = widget.initialExpense?.category ?? 'Others';
  late String _currency =
      widget.initialExpense?.currency ?? ref.read(preferredCurrencyProvider);
  late DateTime _date = widget.initialExpense?.date ?? DateTime.now();
  bool _saving = false;
  String? _amountError;
  String? _merchantError;

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
    final editing = widget.initialExpense != null;
    return ColoredBox(
      color: FlowColor.canvas(context),
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
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LoomMark(size: 42),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoordinateLabel(
                            editing
                                ? 'Proof / amend record'
                                : 'Fallback / evidence correction',
                            line: true,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            editing
                                ? 'Correct the evidence.'
                                : 'Record what AI could not see.',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  color: FlowColor.content(context),
                                  fontWeight: FontWeight.w800,
                                  height: 1.05,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            editing
                                ? 'Your correction becomes the trusted ledger value. Original evidence remains visible below.'
                                : 'Optional manual input. Flow normally builds this record from connected evidence.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: FlowColor.quiet(context),
                                  height: 1.4,
                                ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.onDelete != null)
                      IconButton(
                        onPressed: _confirmDelete,
                        tooltip: 'Delete record',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: FlowColor.coral,
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
                  const CoordinateLabel('01 / direction', line: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _FormPort(
                          label: 'MONEY OUT',
                          detail: 'DEBIT',
                          selected: _type == 'expense',
                          color: FlowColor.coral,
                          onTap: () => setState(() => _type = 'expense'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FormPort(
                          label: 'MONEY IN',
                          detail: 'CREDIT',
                          selected: _type == 'income',
                          color: FlowColor.mint,
                          onTap: () => setState(() => _type = 'income'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const CoordinateLabel('02 / value', line: true),
                  const SizedBox(height: 10),
                  CutSurface(
                    accent: _amountError == null
                        ? FlowColor.loom
                        : FlowColor.coral,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DECLARED AMOUNT',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: FlowColor.quiet(context),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                              ),
                        ),
                        Row(
                          children: [
                            DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _currency,
                                dropdownColor: FlowColor.raised(context),
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
                                          (v) => DropdownMenuItem(
                                            value: v,
                                            child: Text(v),
                                          ),
                                        )
                                        .toList(),
                                onChanged: (v) =>
                                    setState(() => _currency = v!),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: _amount,
                                focusNode: _amountFocus,
                                autofocus: !editing,
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
                                    color: FlowColor.content(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                decoration: const InputDecoration.collapsed(
                                  hintText: '0.00',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_amountError != null) _ErrorLine(_amountError!),
                  const SizedBox(height: 22),
                  const CoordinateLabel('03 / identity', line: true),
                  const SizedBox(height: 10),
                  _EvidenceField(
                    label: 'SOURCE OR DESTINATION',
                    error: _merchantError,
                    child: TextField(
                      controller: _merchant,
                      focusNode: _merchantFocus,
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) {
                        if (_merchantError != null) {
                          setState(() => _merchantError = null);
                        }
                      },
                      decoration: const InputDecoration.collapsed(
                        hintText: 'Person, business, account, or bank',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _EvidenceField(
                    label: 'CLASSIFICATION',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: categories.contains(_category)
                            ? _category
                            : null,
                        isExpanded: true,
                        dropdownColor: FlowColor.raised(context),
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
                        onChanged: (v) => setState(() => _category = v!),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FormPort(
                    label: DateFormat(
                      'EEEE, d MMMM yyyy',
                    ).format(_date).toUpperCase(),
                    detail:
                        '${DateFormat('h:mm a').format(_date)} · CHANGE TIME',
                    selected: false,
                    color: FlowColor.proof,
                    onTap: _pickDate,
                  ),
                  const SizedBox(height: 10),
                  _EvidenceField(
                    label: 'OPTIONAL CONTEXT',
                    child: TextField(
                      controller: _tags,
                      decoration: const InputDecoration.collapsed(
                        hintText: 'travel, work, shared',
                      ),
                    ),
                  ),
                  if (editing) ...[
                    const SizedBox(height: 20),
                    _SourcePanel(expense: widget.initialExpense!),
                  ],
                  const SizedBox(height: 28),
                  _FormCommit(
                    label: editing
                        ? 'COMMIT CORRECTION'
                        : 'COMMIT MANUAL EVIDENCE',
                    saving: _saving,
                    onTap: _saving ? null : _save,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: 'Choose transaction time',
    );
    if (!mounted) return;
    final time = picked ?? TimeOfDay.fromDateTime(_date);
    setState(
      () => _date = DateTime(
        day.year,
        day.month,
        day.day,
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
      (amountError != null ? _amountFocus : _merchantFocus).requestFocus();
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
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: CutSurface(
              accent: FlowColor.coral,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CoordinateLabel(
                    'Destructive / ledger record',
                    color: FlowColor.coral,
                    line: true,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Remove this evidence?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This permanently removes it from Activity.',
                    style: TextStyle(color: FlowColor.quiet(context)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _FormPort(
                          label: 'KEEP',
                          detail: 'RETURN',
                          selected: false,
                          color: FlowColor.proof,
                          onTap: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _FormPort(
                          label: 'REMOVE',
                          detail: 'PERMANENT',
                          selected: true,
                          color: FlowColor.coral,
                          onTap: () => Navigator.pop(context, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
    if (yes) widget.onDelete?.call();
  }
}

class _EvidenceField extends StatelessWidget {
  const _EvidenceField({required this.label, required this.child, this.error});
  final String label;
  final Widget child;
  final String? error;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CutSurface(
        accent: error == null ? FlowColor.rule(context) : FlowColor.coral,
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: FlowColor.quiet(context),
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
      if (error != null) _ErrorLine(error!),
    ],
  );
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 7, 0, 0),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: FlowColor.coral),
    ),
  );
}

class _FormPort extends StatelessWidget {
  const _FormPort({
    required this.label,
    required this.detail,
    required this.selected,
    required this.color,
    required this.onTap,
  });
  final String label, detail;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: InkWell(
      onTap: onTap,
      child: CutSurface(
        color: selected
            ? color.withValues(alpha: .14)
            : FlowColor.raised(context),
        accent: selected ? color : FlowColor.rule(context),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 30,
              color: selected ? color : FlowColor.rule(context),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: .5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? color : FlowColor.quiet(context),
                      fontSize: 9,
                      letterSpacing: 1,
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

class _FormCommit extends StatelessWidget {
  const _FormCommit({
    required this.label,
    required this.saving,
    required this.onTap,
  });
  final String label;
  final bool saving;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: CutSurface(
        color: FlowColor.loom,
        accent: FlowColor.proof,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
        child: Row(
          children: [
            LoomMark(
              size: 28,
              state: saving ? LoomState.checking : LoomState.ready,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                saving ? 'WRITING TO LEDGER…' : label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ),
            const Icon(Icons.arrow_forward, color: FlowColor.proof),
          ],
        ),
      ),
    ),
  );
}

class _SourcePanel extends StatelessWidget {
  const _SourcePanel({required this.expense});
  final Expense expense;
  @override
  Widget build(BuildContext context) {
    final message = expense.originalSms.trim();
    return CutSurface(
      accent: message.isEmpty ? FlowColor.amber : FlowColor.proof,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CoordinateLabel(
            message.isEmpty ? 'Origin / manual' : 'Origin / bank SMS',
            color: message.isEmpty ? FlowColor.amber : FlowColor.proof,
            line: true,
          ),
          const SizedBox(height: 12),
          Text(
            message.isEmpty
                ? 'No external evidence is attached to this record.'
                : message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.5,
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: message));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Original SMS copied.')),
                    );
                  }
                },
                child: const CoordinateLabel('Copy raw evidence'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
