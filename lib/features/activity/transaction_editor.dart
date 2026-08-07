import 'package:flutter/material.dart' show Icons, showDatePicker;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/category_catalog.dart';
import '../../domain/transaction.dart';
import '../common/formatting.dart';
import 'category_sheet.dart';

/// Add or edit one transaction.
///
/// The entry point for cash, which no SMS will ever report, and the repair tool
/// for anything the extraction got wrong. `TransactionSource.manual` existed in
/// the model from the start with nothing in the interface able to produce it.
Future<void> showTransactionEditor({
  required BuildContext context,
  required WidgetRef ref,
  MoneyTransaction? existing,
}) => showFluxSheet<void>(
  context: context,
  builder: (context) => _TransactionEditor(existing: existing),
);

class _TransactionEditor extends ConsumerStatefulWidget {
  const _TransactionEditor({this.existing});
  final MoneyTransaction? existing;

  @override
  ConsumerState<_TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends ConsumerState<_TransactionEditor> {
  late final TextEditingController _amount;
  late final TextEditingController _merchant;
  late final TextEditingController _note;
  late TransactionDirection _direction;
  late String _category;
  late DateTime _occurred;
  late String _currency;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final currency =
        existing?.currency ??
        ref.read(appControllerProvider).value?.preferences.currency ??
        'INR';
    _currency = currency;
    _direction = existing?.direction ?? TransactionDirection.outgoing;
    _category = existing?.category ?? defaultCategoryFor(_direction);
    _occurred = existing?.occurredAt ?? DateTime.now();
    _amount = TextEditingController(
      text: existing == null
          ? ''
          : minorToMajorInput(existing.amountMinor, currency),
    );
    _merchant = TextEditingController(text: existing?.merchant ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minor = parseMajorToMinor(_amount.text, _currency);
    if (minor == null) {
      setState(() => _error = 'Enter an amount greater than zero.');
      return;
    }
    if (_merchant.text.trim().isEmpty) {
      setState(() => _error = 'Say who it was, even roughly.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final existing = widget.existing;
    final value = MoneyTransaction(
      id: existing?.id,
      amountMinor: minor,
      currency: _currency,
      direction: _direction,
      merchant: _merchant.text.trim(),
      category: _category,
      occurredAt: _occurred,
      // An edited row keeps the source that produced it — it is still the SMS
      // that this record came from, corrected — while a new one is manual.
      source: existing?.source ?? TransactionSource.manual,
      // Anything a person typed or corrected by hand is confirmed by
      // definition: they are the authority the review queue was waiting for.
      reviewState: ReviewState.confirmed,
      confidence: 1,
      account: existing?.account,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      sourceText: existing?.sourceText,
    );
    await ref.read(appControllerProvider.notifier).saveTransaction(value);
    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final editing = widget.existing != null;

    return FluxSheetBody(
      title: editing ? 'Edit transaction' : 'Add a transaction',
      subtitle: editing
          ? 'Your change is the authority; this leaves the review queue.'
          : 'For cash, or anything no message reported',
      actions: FluxButton(
        label: editing ? 'Save changes' : 'Add transaction',
        busy: _saving,
        onPressed: _save,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FluxSegmented<TransactionDirection>(
            value: _direction,
            onChanged: (value) => setState(() {
              _direction = value;
              // The catalogs do not overlap, so a category carried across
              // directions would be one the new direction has no name for.
              if (!categoriesFor(value).contains(_category)) {
                _category = defaultCategoryFor(value);
              }
            }),
            options: const [
              (TransactionDirection.outgoing, 'Money out'),
              (TransactionDirection.incoming, 'Money in'),
            ],
          ),
          const SizedBox(height: FluxSpace.x5),
          FluxField(
            controller: _amount,
            label: 'Amount',
            hint: '0',
            autofocus: !editing,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: FluxType.moneyLarge,
            error: _error,
            prefix: Text(
              _currency,
              style: FluxType.label.copyWith(color: palette.textMuted),
            ),
          ),
          const SizedBox(height: FluxSpace.x4),
          FluxField(
            controller: _merchant,
            label: _direction == TransactionDirection.incoming
                ? 'From'
                : 'Merchant',
            hint: _direction == TransactionDirection.incoming
                ? 'Who paid you'
                : 'Where the money went',
          ),
          const SizedBox(height: FluxSpace.x4),
          Row(
            children: [
              Expanded(
                child: _PickerRow(
                  label: 'Category',
                  value: _category,
                  tint: palette.forCategory(_category),
                  onTap: () async {
                    final chosen = await showCategorySheet(
                      context: context,
                      direction: _direction,
                      selected: _category,
                    );
                    if (chosen != null) setState(() => _category = chosen);
                  },
                ),
              ),
              const SizedBox(width: FluxSpace.x3),
              Expanded(
                child: _PickerRow(
                  label: 'When',
                  value: dayLabel(_occurred),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _occurred,
                      firstDate: DateTime(_occurred.year - 3),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (picked != null) {
                      setState(
                        () => _occurred = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          _occurred.hour,
                          _occurred.minute,
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: FluxSpace.x4),
          FluxField(
            controller: _note,
            label: 'Note',
            hint: 'Optional',
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.tint,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FluxType.label.copyWith(color: palette.textMuted)),
        const SizedBox(height: FluxSpace.x2),
        FluxPressable(
          onTap: onTap,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: palette.isDark ? palette.surface : palette.surfaceHighest,
              shape: FluxRadius.shape(
                FluxRadius.sm,
                side: BorderSide(color: palette.line, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FluxSpace.x4,
                vertical: 14,
              ),
              child: Row(
                children: [
                  if (tint != null) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: ShapeDecoration(
                        color: tint,
                        shape: const CircleBorder(),
                      ),
                    ),
                    const SizedBox(width: FluxSpace.x2),
                  ],
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FluxType.body.copyWith(color: palette.text),
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: palette.textFaint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
