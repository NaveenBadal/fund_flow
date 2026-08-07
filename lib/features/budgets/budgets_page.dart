import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/budgets_controller.dart';
import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../../domain/budget.dart';
import '../../domain/category_catalog.dart';
import '../../domain/transaction.dart';
import '../common/formatting.dart';

/// Monthly limits, and how this month is going against them.
///
/// A limit is what turns "you spent ₹12,000 on food" into "you spent ₹12,000 of
/// ₹10,000 on food" — the same figure, and only one of them is an answer.
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final snapshot = ref.watch(homeSnapshotProvider);
    final money = ref.watch(moneyProvider);
    final now = DateTime.now();

    final withLimits = snapshot.budgets;
    final used = withLimits.map((status) => status.category).toSet();
    final suggestions = snapshot.categories
        .where((row) => !used.contains(row.category))
        .take(4)
        .toList();

    return FluxDetailPage(
      title: 'Limits',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: Text(
            'One monthly ceiling per category, in ${snapshot.currency}. '
            'Nothing is blocked when a limit is passed — the app just stops '
            'being quiet about it.',
            style: FluxType.body.copyWith(color: palette.textMuted),
          ),
        ),
        if (withLimits.isEmpty)
          const SliverToBoxAdapter(
            child: FluxEmpty(
              icon: Icons.track_changes_rounded,
              title: 'No limits yet',
              message: 'Pick a category below to set your first one.',
              compact: true,
            ),
          )
        else
          SliverToBoxAdapter(
            child: FluxGroup(
              header: 'This month',
              children: [
                for (final status in withLimits)
                  _BudgetRow(
                    status: status,
                    money: money,
                    now: now,
                    onEdit: () => _editLimit(
                      context: context,
                      ref: ref,
                      category: status.category,
                      currency: status.currency,
                      existing: status.limitMinor,
                    ),
                  ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: suggestions.isEmpty
                ? 'Add a limit'
                : 'Where your money goes',
            footer: suggestions.isEmpty
                ? null
                : 'Suggested from what you actually spent this month, largest '
                      'first.',
            children: [
              for (final row in suggestions)
                FluxRow(
                  title: row.category,
                  subtitle:
                      '${money(row.amountMinor, snapshot.currency)} so far this '
                      'month',
                  icon: Icons.add_circle_outline_rounded,
                  iconColor: palette.forCategory(row.category),
                  chevron: true,
                  onTap: () => _editLimit(
                    context: context,
                    ref: ref,
                    category: row.category,
                    currency: snapshot.currency,
                    // Pre-filled with what they are on course to spend, rounded
                    // to something a person would actually type. A limit set at
                    // exactly last month's spend is not a limit.
                    existing: _roundedSuggestion(
                      row.amountMinor,
                      snapshot.elapsedFraction,
                    ),
                  ),
                ),
              FluxRow(
                title: 'Another category…',
                icon: Icons.more_horiz_rounded,
                chevron: true,
                onTap: () async {
                  final chosen = await showFluxPicker<String>(
                    context: context,
                    title: 'Category',
                    options: [
                      for (final category in categoriesFor(
                        TransactionDirection.outgoing,
                      ))
                        (category, category),
                    ],
                  );
                  if (chosen == null || !context.mounted) return;
                  await _editLimit(
                    context: context,
                    ref: ref,
                    category: chosen,
                    currency: snapshot.currency,
                    existing: null,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// A projection rounded to a number someone would choose themselves.
  static int _roundedSuggestion(int spentMinor, double elapsedFraction) {
    if (elapsedFraction <= 0.05) return spentMinor;
    final projected = spentMinor / elapsedFraction;
    // Round up to the nearest 500 major units — the granularity people actually
    // think in when setting a ceiling.
    const step = 50000;
    return ((projected / step).ceil() * step).round();
  }

  Future<void> _editLimit({
    required BuildContext context,
    required WidgetRef ref,
    required String category,
    required String currency,
    required int? existing,
  }) => showFluxSheet<void>(
    context: context,
    builder: (context) =>
        _LimitSheet(category: category, currency: currency, existing: existing),
  );
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.status,
    required this.money,
    required this.now,
    required this.onEdit,
  });

  final BudgetStatus status;
  final MoneyFormatter money;
  final DateTime now;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final projected = status.projectedMinor(now);
    final heading = status.over
        ? 'Over by ${money(-status.remainingMinor, status.currency)}'
        : '${money(status.remainingMinor, status.currency)} left';

    return FluxPressable(
      onTap: onEdit,
      feedback: PressFeedback.wash,
      haptic: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FluxSpace.x4,
          vertical: FluxSpace.x4,
        ),
        child: Row(
          children: [
            FluxRing(
              fraction: status.fraction,
              label: '',
              size: 54,
              thickness: 6,
            ),
            const SizedBox(width: FluxSpace.x4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          status.category,
                          style: FluxType.subtitle.copyWith(
                            color: palette.text,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: palette.textFaint,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${money(status.spentMinor, status.currency)} of '
                    '${money(status.limitMinor, status.currency)} · $heading',
                    style: FluxType.caption.copyWith(
                      color: status.over
                          ? palette.danger
                          : (status.close
                                ? palette.attention
                                : palette.textMuted),
                    ),
                  ),
                  if (!status.over && projected > status.limitMinor) ...[
                    const SizedBox(height: 3),
                    Text(
                      'On course for ${money(projected, status.currency)} by '
                      'month end',
                      style: FluxType.caption.copyWith(
                        color: palette.attention,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitSheet extends ConsumerStatefulWidget {
  const _LimitSheet({
    required this.category,
    required this.currency,
    required this.existing,
  });

  final String category;
  final String currency;
  final int? existing;

  @override
  ConsumerState<_LimitSheet> createState() => _LimitSheetState();
}

class _LimitSheetState extends ConsumerState<_LimitSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : minorToMajorInput(widget.existing!, widget.currency),
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minor = parseMajorToMinor(_amount.text, widget.currency);
    if (minor == null) {
      setState(() => _error = 'Enter a limit greater than zero.');
      return;
    }
    await ref
        .read(budgetsProvider.notifier)
        .setLimit(
          category: widget.category,
          limitMinor: minor,
          currency: widget.currency,
        );
    if (!mounted) return;
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return FluxSheetBody(
      title: '${widget.category} limit',
      subtitle: 'Per calendar month, in ${widget.currency}',
      actions: Column(
        children: [
          FluxButton(label: 'Save limit', onPressed: _save),
          if (widget.existing != null) ...[
            const SizedBox(height: FluxSpace.x2),
            FluxButton(
              label: 'Remove limit',
              kind: FluxButtonKind.ghost,
              onPressed: () async {
                await ref
                    .read(budgetsProvider.notifier)
                    .remove(widget.category);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
      child: FluxField(
        controller: _amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        style: FluxType.moneyLarge,
        error: _error,
        prefix: Text(
          widget.currency,
          style: FluxType.label.copyWith(color: palette.textMuted),
        ),
      ),
    );
  }
}
