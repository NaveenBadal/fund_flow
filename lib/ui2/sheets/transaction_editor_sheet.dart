import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../components/flow_field.dart';
import '../flow_categories.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// Opens the editor over the current screen. Pass a [transaction] to edit it;
/// omit it to record something by hand.
Future<void> showTransactionEditor(
  BuildContext context, {
  MoneyTransaction? transaction,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheet) => _EditorSheet(transaction: transaction),
);

/// Editing is the correction of last resort — Review and the detail screen
/// handle the common case with one tap — so this sheet optimises for the rare
/// full rewrite. The category is chips, not a text field: free-typing
/// categories is how a vocabulary drifts into "food", "Food " and "Zomato".
class _EditorSheet extends ConsumerStatefulWidget {
  const _EditorSheet({this.transaction});
  final MoneyTransaction? transaction;

  @override
  ConsumerState<_EditorSheet> createState() => _EditorSheetState();
}

class _EditorSheetState extends ConsumerState<_EditorSheet> {
  late final _amount = TextEditingController(
    text: widget.transaction == null
        ? ''
        : (widget.transaction!.amountMinor / 100).toStringAsFixed(2),
  );
  late final _merchant = TextEditingController(
    text: widget.transaction?.merchant,
  );
  late final _note = TextEditingController(text: widget.transaction?.note);
  late TransactionDirection _direction =
      widget.transaction?.direction ?? TransactionDirection.outgoing;
  late String _category = widget.transaction?.category ?? 'Other';
  late DateTime _occurredAt = widget.transaction?.occurredAt ?? DateTime.now();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    final editing = widget.transaction != null;

    // The vocabulary follows the direction — a refund or salary is offered for
    // money in, never "Food". The record's own category still leads when it
    // sits outside the standard set, so an unusual reading stays selectable.
    final vocabulary = categoriesFor(_direction);
    final categories = [
      if (!vocabulary.any(
        (value) => value.toLowerCase() == _category.toLowerCase(),
      ))
        _category,
      ...vocabulary,
    ];

    return Padding(
      // Rides above the keyboard instead of being covered by it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(FlowSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              editing ? 'Edit transaction' : 'Add transaction',
              style: text.titleLarge,
            ),
            const SizedBox(height: FlowSpace.lg),
            _DirectionToggle(
              direction: _direction,
              onChanged: (value) => setState(() {
                _direction = value;
                // Carry the category across only when it belongs to both sides
                // (Transfer, Other); otherwise fall back to the new side's
                // default so a stale "Food" never rides onto money in.
                if (!categoriesFor(
                  value,
                ).any((c) => c.toLowerCase() == _category.toLowerCase())) {
                  _category = defaultCategoryFor(value);
                }
              }),
            ),
            const SizedBox(height: FlowSpace.lg),
            FlowField(
              controller: _amount,
              label: 'Amount',
              hint: '0.00',
              prefixText: '₹ ',
              error: _error,
              autofocus: !editing,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: FlowSpace.md),
            FlowField(
              controller: _merchant,
              label: 'Merchant or person',
              hint: 'Who was this with?',
            ),
            const SizedBox(height: FlowSpace.md),
            Text('When', style: text.labelSmall?.copyWith(color: flow.inkSoft)),
            const SizedBox(height: FlowSpace.sm),
            _DateField(value: _occurredAt, onTap: _pickDate),
            const SizedBox(height: FlowSpace.md),
            Text(
              'Category',
              style: text.labelSmall?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.sm),
            Wrap(
              spacing: FlowSpace.sm,
              runSpacing: FlowSpace.sm,
              children: [
                for (final category in categories)
                  _CategoryChip(
                    label: category,
                    selected: category.toLowerCase() == _category.toLowerCase(),
                    onTap: () => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: FlowSpace.md),
            FlowField(
              controller: _note,
              label: 'Note',
              hint: 'Optional',
              maxLines: 3,
            ),
            const SizedBox(height: FlowSpace.xl),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(FlowDensity.minimumTarget),
                backgroundColor: flow.accent,
                foregroundColor: flow.onAccent,
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadius.sm,
                ),
              ),
              child: Text(editing ? 'Save changes' : 'Add transaction'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(now.year - 5),
      // A transaction cannot have happened in the future.
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      // Keep the original time-of-day so an edited record's ordering within a
      // day is preserved; a fresh entry keeps the current time.
      _occurredAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _occurredAt.hour,
        _occurredAt.minute,
      );
    });
  }

  Future<void> _save() async {
    final value = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    if (_merchant.text.trim().isEmpty) {
      setState(() => _error = 'Enter who this was with.');
      return;
    }
    final prefs = ref.read(appControllerProvider).requireValue.preferences;
    await ref
        .read(appControllerProvider.notifier)
        .saveTransaction(
          MoneyTransaction(
            id: widget.transaction?.id,
            amountMinor: (value * 100).round(),
            currency: widget.transaction?.currency ?? prefs.currency,
            direction: _direction,
            merchant: _merchant.text.trim(),
            category: _category,
            occurredAt: _occurredAt,
            source: widget.transaction?.source ?? TransactionSource.manual,
            reviewState:
                widget.transaction?.reviewState ?? ReviewState.confirmed,
            confidence: widget.transaction?.confidence ?? 1,
            sourceText: widget.transaction?.sourceText,
            note: _note.text.trim(),
          ),
        );
    if (mounted) Navigator.pop(context);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap});
  final DateTime value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final now = DateTime.now();
    final isToday =
        value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
    final label = isToday
        ? 'Today'
        : DateFormat('EEEE, d MMM yyyy').format(value);
    return Semantics(
      button: true,
      label: 'Date, $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.sm,
        child: Container(
          height: FlowDensity.minimumTarget,
          padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
          decoration: BoxDecoration(
            color: flow.sunken,
            borderRadius: FlowRadius.sm,
            border: Border.all(color: flow.line),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded, size: 18, color: flow.inkSoft),
              const SizedBox(width: FlowSpace.sm),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Icon(Icons.expand_more_rounded, size: 20, color: flow.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({required this.direction, required this.onChanged});
  final TransactionDirection direction;
  final ValueChanged<TransactionDirection> onChanged;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      decoration: BoxDecoration(
        color: flow.sunken,
        borderRadius: FlowRadius.sm,
      ),
      padding: const EdgeInsets.all(FlowSpace.xxs),
      child: Row(
        children: [
          for (final entry in const [
            (TransactionDirection.outgoing, 'Money out'),
            (TransactionDirection.incoming, 'Money in'),
          ])
            Expanded(
              child: _DirectionOption(
                label: entry.$2,
                selected: direction == entry.$1,
                onTap: () => onChanged(entry.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _DirectionOption extends StatelessWidget {
  const _DirectionOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.sm,
        child: AnimatedContainer(
          duration: FlowMotion.respecting(context, FlowMotion.quick),
          curve: FlowMotion.move,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? flow.raised : Colors.transparent,
            borderRadius: FlowRadius.sm,
            border: Border.all(
              color: selected ? flow.line : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? flow.ink : flow.inkSoft,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Semantics(
      button: true,
      selected: selected,
      label: selected ? '$label, current category' : 'Set category to $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpace.md,
            vertical: FlowSpace.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? flow.accent : flow.raised,
            borderRadius: FlowRadius.pill,
            border: Border.all(color: selected ? flow.accent : flow.line),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? flow.onAccent : flow.ink,
            ),
          ),
        ),
      ),
    );
  }
}
