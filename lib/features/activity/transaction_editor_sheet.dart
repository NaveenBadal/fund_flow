import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../../ui/components/current_button.dart';
import '../../ui/components/current_field.dart';
import '../../ui/foundation/current_colors.dart';

class TransactionEditorSheet extends ConsumerStatefulWidget {
  const TransactionEditorSheet({super.key, this.transaction});
  final MoneyTransaction? transaction;
  @override
  ConsumerState<TransactionEditorSheet> createState() => _State();
}

class _State extends ConsumerState<TransactionEditorSheet> {
  late final _amount = TextEditingController(
    text: widget.transaction == null
        ? ''
        : (widget.transaction!.amountMinor / 100).toStringAsFixed(2),
  );
  late final _merchant = TextEditingController(
    text: widget.transaction?.merchant,
  );
  late final _category = TextEditingController(
    text: widget.transaction?.category ?? 'Other',
  );
  late final _note = TextEditingController(text: widget.transaction?.note);
  late TransactionDirection _direction =
      widget.transaction?.direction ?? TransactionDirection.outgoing;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _merchant.dispose();
    _category.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.current.rule,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            widget.transaction == null ? 'Add transaction' : 'Edit transaction',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: CurrentButton(
                  label: 'Money out',
                  style: _direction == TransactionDirection.outgoing
                      ? CurrentButtonStyle.tonal
                      : CurrentButtonStyle.outline,
                  onPressed: () => setState(
                    () => _direction = TransactionDirection.outgoing,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CurrentButton(
                  label: 'Money in',
                  style: _direction == TransactionDirection.incoming
                      ? CurrentButtonStyle.tonal
                      : CurrentButtonStyle.outline,
                  onPressed: () => setState(
                    () => _direction = TransactionDirection.incoming,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CurrentField(
            controller: _amount,
            label: 'Amount',
            hint: '0.00',
            error: _error,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            prefixIcon: Icons.currency_rupee_rounded,
          ),
          const SizedBox(height: 12),
          CurrentField(
            controller: _merchant,
            label: 'Merchant or person',
            hint: 'Who was this with?',
          ),
          const SizedBox(height: 12),
          CurrentField(controller: _category, label: 'Category', hint: 'Other'),
          const SizedBox(height: 12),
          CurrentField(
            controller: _note,
            label: 'Note',
            hint: 'Optional',
            maxLines: 3,
          ),
          const SizedBox(height: 22),
          CurrentButton(
            label: 'Save transaction',
            expand: true,
            onPressed: _save,
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    final value = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (value == null || value <= 0 || _merchant.text.trim().isEmpty) {
      setState(() => _error = 'Enter a valid amount and merchant.');
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
            category: _category.text.trim().isEmpty
                ? 'Other'
                : _category.text.trim(),
            occurredAt: widget.transaction?.occurredAt ?? DateTime.now(),
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
