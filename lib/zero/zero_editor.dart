import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/app_controller.dart';
import '../domain/transaction.dart';
import '../ui2/flow_categories.dart';
import 'zero_theme.dart';

Future<void> showZeroTransactionEditor(
  BuildContext context, {
  MoneyTransaction? transaction,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _ZeroEditor(transaction: transaction),
);

class _ZeroEditor extends ConsumerStatefulWidget {
  const _ZeroEditor({this.transaction});
  final MoneyTransaction? transaction;

  @override
  ConsumerState<_ZeroEditor> createState() => _ZeroEditorState();
}

class _ZeroEditorState extends ConsumerState<_ZeroEditor> {
  late final amount = TextEditingController(
    text: widget.transaction == null
        ? ''
        : (widget.transaction!.amountMinor / 100).toStringAsFixed(2),
  );
  late final merchant = TextEditingController(
    text: widget.transaction?.merchant,
  );
  late final note = TextEditingController(text: widget.transaction?.note);
  late var direction =
      widget.transaction?.direction ?? TransactionDirection.outgoing;
  late var category = widget.transaction?.category ?? 'Other';
  late var occurredAt = widget.transaction?.occurredAt ?? DateTime.now();
  String? error;
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    merchant.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    final editing = widget.transaction != null;
    final vocabulary = categoriesFor(direction);
    final choices = [
      if (!vocabulary.contains(category)) category,
      ...vocabulary,
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 3,
                  decoration: BoxDecoration(
                    color: z.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                editing ? 'Edit the record' : 'Add a record',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Text(
                editing
                    ? 'Only the fields you save will change.'
                    : 'A manual record stays entirely on this device.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: z.muted),
              ),
              const SizedBox(height: 26),
              _TwoChoice(
                value: direction,
                onChanged: (value) => setState(() {
                  direction = value;
                  if (!categoriesFor(value).contains(category)) {
                    category = defaultCategoryFor(value);
                  }
                }),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: amount,
                autofocus: !editing,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                style: Theme.of(context).textTheme.headlineLarge,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText:
                      '${widget.transaction?.currency ?? ref.read(appControllerProvider).requireValue.preferences.currency} ',
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: merchant,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Merchant or person',
                  hintText: 'Who was this with?',
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 58),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: z.subtle,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Date',
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(color: z.muted),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              DateFormat(
                                'EEEE, d MMMM yyyy',
                              ).format(occurredAt),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.calendar_today_outlined, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Category',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: z.muted),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final choice in choices)
                    ChoiceChip(
                      label: Text(choice),
                      selected: category == choice,
                      onSelected: (_) => setState(() => category = choice),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Optional context',
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: saving ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                child: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(editing ? 'Save changes' : 'Add transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: occurredAt,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
    );
    if (picked == null) return;
    setState(
      () => occurredAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        occurredAt.hour,
        occurredAt.minute,
      ),
    );
  }

  Future<void> _save() async {
    final parsed = double.tryParse(amount.text.replaceAll(',', '').trim());
    if (parsed == null || parsed <= 0) {
      setState(() => error = 'Enter an amount above zero');
      return;
    }
    if (merchant.text.trim().isEmpty) {
      setState(() => error = 'Add a merchant or person');
      return;
    }
    setState(() => saving = true);
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
            direction: direction,
            merchant: merchant.text.trim(),
            category: category,
            occurredAt: occurredAt,
            source: widget.transaction?.source ?? TransactionSource.manual,
            reviewState:
                widget.transaction?.reviewState ?? ReviewState.confirmed,
            confidence: widget.transaction?.confidence ?? 1,
            sourceText: widget.transaction?.sourceText,
            account: widget.transaction?.account,
            note: note.text.trim(),
          ),
        );
    if (mounted) Navigator.pop(context);
  }
}

class _TwoChoice extends StatelessWidget {
  const _TwoChoice({required this.value, required this.onChanged});
  final TransactionDirection value;
  final ValueChanged<TransactionDirection> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final option in const [
        (TransactionDirection.outgoing, 'Money out'),
        (TransactionDirection.incoming, 'Money in'),
      ])
        Expanded(
          child: Semantics(
            selected: value == option.$1,
            button: true,
            child: InkWell(
              onTap: () => onChanged(option.$1),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: EdgeInsets.only(
                  right: option.$1 == TransactionDirection.outgoing ? 5 : 0,
                  left: option.$1 == TransactionDirection.incoming ? 5 : 0,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: value == option.$1
                      ? context.zero.accent
                      : context.zero.subtle,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  option.$2,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: value == option.$1
                        ? context.zero.onAccent
                        : context.zero.text,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
