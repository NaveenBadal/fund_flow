import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/category_catalog.dart';
import '../../domain/transaction.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_controls.dart';
import '../widgets/ff_group.dart';
import '../widgets/ff_pressable.dart';
import '../widgets/ff_sheet.dart';
import '../widgets/ff_transaction_row.dart';

Future<void> showTransactionEditor(
  BuildContext context, {
  MoneyTransaction? transaction,
}) => showFFSheet<void>(
  context,
  builder: (_) => _Editor(transaction: transaction),
);

/// Adding or correcting a record.
///
/// The amount is the first thing focused and the largest thing on screen,
/// because it is the only field that cannot be guessed later.
class _Editor extends ConsumerStatefulWidget {
  const _Editor({this.transaction});
  final MoneyTransaction? transaction;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final _amount = TextEditingController(
    text: widget.transaction == null
        ? ''
        : (widget.transaction!.amountMinor / 100).toStringAsFixed(2),
  );
  late final _merchant = TextEditingController(
    text: widget.transaction?.merchant,
  );
  late final _note = TextEditingController(text: widget.transaction?.note);

  late var _direction =
      widget.transaction?.direction ?? TransactionDirection.outgoing;
  late var _category = widget.transaction?.category ?? 'Other';
  late var _occurredAt = widget.transaction?.occurredAt ?? DateTime.now();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final editing = widget.transaction != null;
    final currency =
        widget.transaction?.currency ??
        ref.read(appControllerProvider).requireValue.preferences.currency;
    final vocabulary = categoriesFor(_direction);
    final choices = [
      if (!vocabulary.contains(_category)) _category,
      ...vocabulary,
    ];

    return FFSheetScaffold(
      title: editing ? 'Edit' : 'New transaction',
      trailing: FFSheetAction(
        label: editing ? 'Save' : 'Add',
        emphasis: true,
        onTap: _saving ? null : _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              FFSpace.xl,
              FFSpace.gutter,
              FFSpace.lg,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      currency,
                      style: FFText.title2.copyWith(color: c.tertiaryLabel),
                    ),
                    const SizedBox(width: FFSpace.sm),
                    IntrinsicWidth(
                      child: TextField(
                        controller: _amount,
                        autofocus: !editing,
                        textAlign: TextAlign.start,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                        ],
                        style: FFText.money.copyWith(
                          fontFeatures: FFText.tabular,
                          color: c.label,
                        ),
                        cursorColor: c.tint,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: '0',
                          hintStyle: FFText.money.copyWith(
                            color: c.quaternaryLabel,
                          ),
                        ),
                        onChanged: (_) {
                          if (_error != null) setState(() => _error = null);
                        },
                      ),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: FFSpace.sm),
                  Text(
                    _error!,
                    style: FFText.footnote.copyWith(color: c.red),
                  ),
                ],
                const SizedBox(height: FFSpace.xl),
                FFSegmented<TransactionDirection>(
                  value: _direction,
                  segments: const [
                    (TransactionDirection.outgoing, 'Money out'),
                    (TransactionDirection.incoming, 'Money in'),
                  ],
                  onChanged: (value) => setState(() {
                    _direction = value;
                    if (!categoriesFor(value).contains(_category)) {
                      _category = defaultCategoryFor(value);
                    }
                  }),
                ),
              ],
            ),
          ),
          FFGroup(
            header: 'Merchant or person',
            children: [
              _FieldRow(
                child: FFField(
                  controller: _merchant,
                  placeholder: 'Who was this with?',
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                ),
              ),
              FFRow(
                title: 'Date',
                value: DateFormat('d MMM yyyy').format(_occurredAt),
                onTap: _pickDate,
              ),
            ],
          ),
          FFGroup(
            header: 'Category',
            children: [
              Padding(
                padding: const EdgeInsets.all(FFSpace.md),
                child: Wrap(
                  spacing: FFSpace.sm,
                  runSpacing: FFSpace.sm,
                  children: [
                    for (final choice in choices)
                      _CategoryChip(
                        label: choice,
                        selected: _category == choice,
                        onTap: () => setState(() => _category = choice),
                      ),
                  ],
                ),
              ),
            ],
          ),
          FFGroup(
            header: 'Note',
            children: [
              _FieldRow(
                child: FFField(
                  controller: _note,
                  placeholder: 'Optional context',
                  minLines: 2,
                  maxLines: 4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    setState(
      () => _occurredAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _occurredAt.hour,
        _occurredAt.minute,
      ),
    );
  }

  Future<void> _save() async {
    final parsed = double.tryParse(_amount.text.replaceAll(',', '').trim());
    if (parsed == null || parsed <= 0) {
      setState(() => _error = 'Enter an amount above zero');
      return;
    }
    if (_merchant.text.trim().isEmpty) {
      setState(() => _error = 'Add a merchant or person');
      return;
    }
    setState(() => _saving = true);
    final preferences = ref
        .read(appControllerProvider)
        .requireValue
        .preferences;
    await ref
        .read(appControllerProvider.notifier)
        .saveTransaction(
          MoneyTransaction(
            id: widget.transaction?.id,
            amountMinor: (parsed * 100).round(),
            currency: widget.transaction?.currency ?? preferences.currency,
            direction: _direction,
            merchant: _merchant.text.trim(),
            category: _category,
            occurredAt: _occurredAt,
            source: widget.transaction?.source ?? TransactionSource.manual,
            reviewState:
                widget.transaction?.reviewState ?? ReviewState.confirmed,
            confidence: widget.transaction?.confidence ?? 1,
            sourceText: widget.transaction?.sourceText,
            account: widget.transaction?.account,
            note: _note.text.trim(),
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(FFSpace.md),
    child: child,
  );
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
    final c = context.ff;
    final tint = FFCategory.color(label);
    return FFPressable(
      onTap: onTap,
      selected: selected,
      child: AnimatedContainer(
        duration: Duration(milliseconds: context.ffStill ? 0 : 160),
        padding: const EdgeInsets.fromLTRB(9, 7, 13, 7),
        decoration: BoxDecoration(
          color: selected ? tint : c.secondaryFill,
          borderRadius: BorderRadius.circular(FFRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FFCategory.icon(label),
              size: 15,
              color: selected ? Colors.white : tint,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: FFText.footnote.copyWith(
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : c.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
