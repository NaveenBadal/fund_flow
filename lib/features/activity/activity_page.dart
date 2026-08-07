import 'package:flutter/material.dart' show Icons, ScaffoldMessenger, SnackBar;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/category_catalog.dart';
import '../../domain/transaction.dart';
import '../common/formatting.dart';
import '../shell/shell.dart';
import 'activity_filter.dart';
import 'category_sheet.dart';
import 'transaction_editor.dart';
import 'transaction_page.dart';
import 'transaction_row.dart';

/// The ledger: everything, searchable, filterable, editable.
class ActivityPage extends ConsumerStatefulWidget {
  const ActivityPage({super.key});

  @override
  ConsumerState<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends ConsumerState<ActivityPage> {
  final _search = TextEditingController();

  /// Ids picked in multi-select mode. Ids rather than objects, so a row edited
  /// underneath the selection does not silently drop out of it.
  final _selected = <int>{};
  bool _selecting = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _bulkCategorise() async {
    final app = ref.read(appControllerProvider).value;
    if (app == null || _selected.isEmpty) return;
    final chosen = await showCategorySheet(
      context: context,
      direction: TransactionDirection.outgoing,
      selected: null,
    );
    if (chosen == null) return;
    final controller = ref.read(appControllerProvider.notifier);
    for (final id in _selected) {
      final item = app.transactions.firstWhere(
        (row) => row.id == id,
        orElse: () => app.transactions.first,
      );
      if (item.id != id) continue;
      await controller.saveTransaction(
        item.copyWith(category: chosen, reviewState: ReviewState.confirmed),
      );
    }
    if (!mounted) return;
    final count = _selected.length;
    _exitSelection();
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          '$count ${count == 1 ? 'transaction' : 'transactions'} moved to $chosen',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final filter = ref.watch(activityFilterProvider);
    final money = ref.watch(moneyProvider);

    // Kept in sync one way only: the field drives the filter, and an
    // externally-set filter (from a Home tap) does not fight what is typed.
    if (_search.text != filter.query && filter.query.isEmpty) {
      _search.clear();
    }

    final all = app?.transactions ?? const <MoneyTransaction>[];
    final matching = all.where(filter.matches).toList();
    final sections = groupByDay(matching);
    final total = matching
        .where((item) => item.direction == TransactionDirection.outgoing)
        .fold<int>(0, (sum, item) => sum + item.amountMinor);
    final currency = matching.isEmpty ? null : sections.first.currency;

    return FluxPage(
      title: _selecting ? '${_selected.length} selected' : 'Activity',
      bottomInset: shellBottomInset(context),
      headerBottomHeight: 106,
      onRefresh: () =>
          ref.read(appControllerProvider.notifier).refreshFromSources(),
      actions: [
        if (_selecting)
          FluxIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Cancel selection',
            onPressed: _exitSelection,
          )
        else
          FluxIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filters',
            onPressed: () => _openFilters(context, filter),
          ),
      ],
      headerBottom: _ActivityHeader(
        search: _search,
        filter: filter,
        onQuery: (value) => ref
            .read(activityFilterProvider.notifier)
            .update((state) => state.copyWith(query: value)),
      ),
      floatingAction: _selecting
          ? null
          : _AddButton(
              onTap: () => showTransactionEditor(context: context, ref: ref),
            ),
      slivers: [
        if (matching.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: FluxEmpty(
              icon: filter.isNarrowed
                  ? Icons.filter_alt_off_outlined
                  : Icons.receipt_long_outlined,
              title: filter.isNarrowed
                  ? 'Nothing matches'
                  : 'No transactions yet',
              message: filter.isNarrowed
                  ? 'There are ${all.length} records in total. Widen the '
                        'period or clear the filters.'
                  : 'Import your messages, or add one by hand.',
              actionLabel: filter.isNarrowed ? 'Clear filters' : 'Add manually',
              onAction: filter.isNarrowed
                  ? () => ref.read(activityFilterProvider.notifier).state =
                        const ActivityFilter()
                  : () => showTransactionEditor(context: context, ref: ref),
            ),
          )
        else ...[
          if (currency != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(
                  left: FluxSpace.page,
                  right: FluxSpace.page,
                  top: FluxSpace.x3,
                ),
                child: Text(
                  '${matching.length} '
                  '${matching.length == 1 ? 'record' : 'records'} · '
                  '${money(total, currency)} out',
                  style: FluxType.caption.copyWith(color: palette.textMuted),
                ),
              ),
            ),
          for (final section in sections) ...[
            SliverToBoxAdapter(
              child: DayHeader(
                label: dayLabel(section.day),
                netLabel:
                    '${section.netMinor >= 0 ? '+' : '−'}'
                    '${money(section.netMinor.abs(), section.currency)}',
                positive: section.netMinor > 0,
              ),
            ),
            SliverList.separated(
              itemCount: section.items.length,
              separatorBuilder: (context, index) =>
                  const FluxLine(indent: FluxSpace.x16),
              itemBuilder: (context, index) {
                final item = section.items[index];
                return _SwipeableRow(
                  transaction: item,
                  enabled: !_selecting,
                  child: TransactionRow(
                    transaction: item,
                    money: money,
                    selected: _selecting ? _selected.contains(item.id) : null,
                    onTap: () {
                      if (_selecting) {
                        setState(() {
                          if (item.id == null) return;
                          _selected.contains(item.id)
                              ? _selected.remove(item.id)
                              : _selected.add(item.id!);
                        });
                        return;
                      }
                      fluxPush(
                        context,
                        (context) => TransactionPage(id: item.id!),
                      );
                    },
                    onLongPress: item.id == null
                        ? null
                        : () => setState(() {
                            _selecting = true;
                            _selected.add(item.id!);
                          }),
                  ),
                );
              },
            ),
          ],
          if (_selecting)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(FluxSpace.page),
                child: FluxButton(
                  label: 'Change category',
                  icon: Icons.sell_outlined,
                  onPressed: _selected.isEmpty ? null : _bulkCategorise,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _openFilters(BuildContext context, ActivityFilter filter) async {
    await showFluxSheet<void>(
      context: context,
      builder: (context) => _FilterSheet(filter: filter),
    );
  }
}

class _ActivityHeader extends StatelessWidget {
  const _ActivityHeader({
    required this.search,
    required this.filter,
    required this.onQuery,
  });

  final TextEditingController search;
  final ActivityFilter filter;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) => Consumer(
    builder: (context, ref, _) {
      void update(ActivityFilter next) =>
          ref.read(activityFilterProvider.notifier).state = next;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluxSpace.page,
              0,
              FluxSpace.page,
              FluxSpace.x3,
            ),
            child: FluxSearchField(
              controller: search,
              hint: 'Search merchant, category, note',
              onChanged: onQuery,
            ),
          ),
          FluxChipBar(
            onClear: filter.isNarrowed
                ? () {
                    search.clear();
                    update(const ActivityFilter());
                  }
                : null,
            children: [
              FluxChip(
                label: filter.periodLabel,
                icon: Icons.calendar_today_rounded,
                selected: filter.period != ActivityPeriod.thisMonth,
                onTap: () async {
                  final chosen = await showFluxPicker<ActivityPeriod>(
                    context: context,
                    title: 'Period',
                    selected: filter.period,
                    options: const [
                      (ActivityPeriod.thisMonth, 'This month'),
                      (ActivityPeriod.lastMonth, 'Last month'),
                      (ActivityPeriod.last90, 'Last 90 days'),
                      (ActivityPeriod.all, 'All time'),
                    ],
                  );
                  if (chosen != null) update(filter.copyWith(period: chosen));
                },
              ),
              FluxChip(
                label: switch (filter.direction) {
                  TransactionDirection.outgoing => 'Spending',
                  TransactionDirection.incoming => 'Income',
                  null => 'All money',
                },
                selected: filter.direction != null,
                onTap: () {
                  update(switch (filter.direction) {
                    null => filter.copyWith(
                      direction: TransactionDirection.outgoing,
                    ),
                    TransactionDirection.outgoing => filter.copyWith(
                      direction: TransactionDirection.incoming,
                    ),
                    TransactionDirection.incoming => filter.copyWith(
                      clearDirection: true,
                    ),
                  });
                },
              ),
              FluxChip(
                label: filter.category ?? 'Category',
                selected: filter.category != null,
                tint: filter.category == null
                    ? null
                    : context.flux.forCategory(filter.category!),
                trailingIcon: filter.category == null
                    ? null
                    : Icons.close_rounded,
                onTap: () async {
                  if (filter.category != null) {
                    update(filter.copyWith(clearCategory: true));
                    return;
                  }
                  final chosen = await showCategorySheet(
                    context: context,
                    direction:
                        filter.direction ?? TransactionDirection.outgoing,
                    selected: filter.category,
                  );
                  if (chosen != null) {
                    update(filter.copyWith(category: chosen));
                  }
                },
              ),
              FluxChip(
                label: 'Needs review',
                icon: Icons.rule_rounded,
                selected: filter.review == ReviewOnly.needsReview,
                onTap: () => update(
                  filter.copyWith(
                    review: filter.review == ReviewOnly.needsReview
                        ? ReviewOnly.any
                        : ReviewOnly.needsReview,
                  ),
                ),
              ),
              if (filter.merchant != null)
                FluxChip(
                  label: filter.merchant!,
                  selected: true,
                  trailingIcon: Icons.close_rounded,
                  onTap: () => update(filter.copyWith(clearMerchant: true)),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// Swipe right to confirm, left to delete.
///
/// Confirm is the right-hand (leading) gesture because it is the safe one and
/// the one that will be used forty times in a row while clearing a review
/// backlog; delete is the harder direction and lands with an undo.
class _SwipeableRow extends ConsumerWidget {
  const _SwipeableRow({
    required this.transaction,
    required this.child,
    this.enabled = true,
  });

  final MoneyTransaction transaction;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    if (!enabled || transaction.id == null) return child;
    final needsReview = transaction.reviewState == ReviewState.needsReview;

    return Dismissible(
      key: ValueKey('tx-${transaction.id}'),
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: needsReview ? palette.income : palette.surfaceHighest,
        icon: needsReview ? Icons.check_rounded : Icons.sell_outlined,
        label: needsReview ? 'Confirm' : 'Category',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: palette.danger,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
      ),
      confirmDismiss: (direction) async {
        final controller = ref.read(appControllerProvider.notifier);
        if (direction == DismissDirection.startToEnd) {
          if (needsReview) {
            HapticFeedback.lightImpact();
            await controller.confirmTransaction(transaction);
          } else {
            final chosen = await showCategorySheet(
              context: context,
              direction: transaction.direction,
              selected: transaction.category,
            );
            if (chosen != null) {
              await controller.saveTransaction(
                transaction.copyWith(category: chosen),
              );
            }
          }
          // Never actually dismissed: the row stays, changed. Removing it would
          // suggest the transaction went somewhere.
          return false;
        }
        final confirmed = await fluxConfirm(
          context: context,
          title: 'Delete this transaction?',
          message:
              '${transaction.merchant} · '
              '${ref.read(moneyProvider).exact(transaction.amountMinor, transaction.currency)}. '
              'This removes it from every total.',
        );
        if (confirmed) await controller.deleteTransaction(transaction.id!);
        return false;
      },
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final onColor = color == palette.surfaceHighest
        ? palette.text
        : (palette.isDark ? palette.background : const Color(0xFFFFFFFF));
    return ColoredBox(
      color: color,
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FluxSpace.x5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: onColor),
              const SizedBox(width: FluxSpace.x2),
              Text(label, style: FluxType.label.copyWith(color: onColor)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return FluxPressable(
      onTap: onTap,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: palette.iris,
          shape: FluxRadius.shape(FluxRadius.md),
          shadows: FluxElevation.floating(palette),
        ),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Icon(Icons.add_rounded, size: 26, color: palette.onIris),
          ),
        ),
      ),
    );
  }
}

/// The full filter sheet, for the combinations the chip row cannot express.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet({required this.filter});
  final ActivityFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void update(ActivityFilter next) =>
        ref.read(activityFilterProvider.notifier).state = next;
    final live = ref.watch(activityFilterProvider);

    return FluxSheetBody(
      title: 'Filters',
      subtitle: 'Applies to the ledger, not to totals elsewhere',
      actions: FluxButton(
        label: 'Done',
        onPressed: () => Navigator.of(context).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Period',
            style: FluxType.label.copyWith(color: context.flux.textMuted),
          ),
          const SizedBox(height: FluxSpace.x2),
          FluxSegmented<ActivityPeriod>(
            value: live.period,
            onChanged: (value) => update(live.copyWith(period: value)),
            options: const [
              (ActivityPeriod.thisMonth, 'Month'),
              (ActivityPeriod.lastMonth, 'Last'),
              (ActivityPeriod.last90, '90 days'),
              (ActivityPeriod.all, 'All'),
            ],
          ),
          const SizedBox(height: FluxSpace.x5),
          Text(
            'Direction',
            style: FluxType.label.copyWith(color: context.flux.textMuted),
          ),
          const SizedBox(height: FluxSpace.x2),
          FluxSegmented<TransactionDirection?>(
            value: live.direction,
            onChanged: (value) => update(
              value == null
                  ? live.copyWith(clearDirection: true)
                  : live.copyWith(direction: value),
            ),
            options: const [
              (null, 'All'),
              (TransactionDirection.outgoing, 'Spending'),
              (TransactionDirection.incoming, 'Income'),
            ],
          ),
          const SizedBox(height: FluxSpace.x5),
          Text(
            'Category',
            style: FluxType.label.copyWith(color: context.flux.textMuted),
          ),
          const SizedBox(height: FluxSpace.x2),
          Wrap(
            spacing: FluxSpace.x2,
            runSpacing: FluxSpace.x2,
            children: [
              for (final category in categoriesFor(
                live.direction ?? TransactionDirection.outgoing,
              ))
                FluxChip(
                  label: category,
                  selected: live.category == category,
                  tint: context.flux.forCategory(category),
                  onTap: () => update(
                    live.category == category
                        ? live.copyWith(clearCategory: true)
                        : live.copyWith(category: category),
                  ),
                ),
            ],
          ),
          const SizedBox(height: FluxSpace.x5),
          FluxRow.toggle(
            title: 'Only what needs review',
            value: live.review == ReviewOnly.needsReview,
            onChanged: (value) => update(
              live.copyWith(
                review: value ? ReviewOnly.needsReview : ReviewOnly.any,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
