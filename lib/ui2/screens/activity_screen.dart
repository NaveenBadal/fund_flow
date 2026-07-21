import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../domain/transaction.dart';
import '../flow_category_icon.dart';
import '../sheets/transaction_editor_sheet.dart';
import '../../domain/money_format.dart';
import '../sheets/category_sheet.dart';
import '../sheets/confirm_delete_sheet.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';
import '../tokens/flow_type.dart';
import 'transaction_detail_screen.dart';

/// The ledger.
///
/// Activity is browsed in bulk: hundreds of records, scanned rather than
/// read. The previous screen showed about five rows per screen and offered
/// nothing but a text search, so any real question — what did I spend on
/// food, what happened last month, which of these are wrong — meant
/// scrolling and remembering. This one is built around dense rows and the
/// four verbs of a ledger: group, filter, sort, and correct in bulk.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

enum ActivityGrouping { day, category, merchant }

enum ActivitySort { newest, oldest, largest, smallest }

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  bool _searching = false;
  String _query = '';

  ActivityGrouping _grouping = ActivityGrouping.day;
  ActivitySort _sort = ActivitySort.newest;

  /// Active date window, [_from] inclusive and [_until] exclusive. Exclusive
  /// ends mean "last month" and a picked range never lose the final day to a
  /// midnight comparison.
  DateTime? _from;
  DateTime? _until;
  String _rangeLabel = 'All time';

  TransactionDirection? _direction;
  bool _reviewOnly = false;

  /// Ids picked for a bulk action. Selection is entered by long-press and
  /// exists only while something is selected.
  final _selected = <int>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final flow = context.flow;
    final hidden = app.preferences.hideAmounts;

    // A bulk delete elsewhere can orphan selected ids; drop them quietly so
    // the selected count never disagrees with what is on screen.
    final ids = {for (final item in app.transactions) item.id};
    _selected.removeWhere((id) => !ids.contains(id));

    final values = _filtered(app.transactions);
    final currency = _dominantCurrency(values);
    final totals = _Totals.of(values, currency);
    final groups = _grouped(values, currency);
    final selecting = _selected.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FlowSpace.xl,
            FlowSpace.lg,
            FlowSpace.md,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Activity',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _summaryLine(values.length, totals, currency, hidden),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _searching ? 'Close search' : 'Search',
                onPressed: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _search.clear();
                    _query = '';
                  }
                }),
                icon: Icon(
                  _searching ? Icons.search_off_rounded : Icons.search_rounded,
                ),
                color: _query.isEmpty ? flow.inkSoft : flow.accent,
              ),
              IconButton(
                tooltip: hidden ? 'Show amounts' : 'Hide amounts',
                onPressed: () => ref
                    .read(appControllerProvider.notifier)
                    .updatePreferences(
                      app.preferences.copyWith(hideAmounts: !hidden),
                    ),
                icon: Icon(
                  hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                color: flow.inkSoft,
              ),
              // Reading more messages without leaving the ledger. Only new
              // messages are parsed — the importer dedups against what it has
              // already seen — so this is cheap to tap repeatedly.
              if (app.aiConnection == AiConnection.connected)
                _SyncButton(
                  working: app.importStatus.working,
                  onSync: () =>
                      ref.read(appControllerProvider.notifier).importMessages(),
                ),
              IconButton(
                tooltip: 'Add transaction',
                onPressed: () => _edit(null),
                icon: const Icon(Icons.add_rounded),
                color: flow.inkSoft,
              ),
            ],
          ),
        ),

        if (_searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FlowSpace.xl,
              FlowSpace.sm,
              FlowSpace.xl,
              0,
            ),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              style: Theme.of(context).textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Merchant, category or note',
                hintStyle: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: flow.inkFaint),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: flow.inkFaint,
                ),
                isDense: true,
                filled: true,
                fillColor: flow.sunken,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: FlowSpace.md,
                  vertical: FlowSpace.sm + 2,
                ),
                border: const OutlineInputBorder(
                  borderRadius: FlowRadius.sm,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.only(top: FlowSpace.sm),
          child: selecting
              ? _SelectionBar(
                  count: _selected.length,
                  total: values.length,
                  anyPending: values.any(
                    (item) =>
                        _selected.contains(item.id) &&
                        item.reviewState == ReviewState.needsReview,
                  ),
                  onSelectAll: () => setState(
                    () => _selected.addAll([
                      for (final item in values)
                        if (item.id != null) item.id!,
                    ]),
                  ),
                  onCategory: () => _bulkCategory(values),
                  onConfirm: () => _bulkConfirm(values),
                  onDelete: () => _bulkDelete(values),
                  onClose: () => setState(_selected.clear),
                )
              : _FilterRow(
                  grouping: _grouping,
                  sort: _sort,
                  rangeLabel: _rangeLabel,
                  rangeActive: _from != null || _until != null,
                  direction: _direction,
                  reviewOnly: _reviewOnly,
                  onGrouping: (value) => setState(() => _grouping = value),
                  onSort: (value) => setState(() => _sort = value),
                  onRange: _pickRange,
                  onDirection: (value) => setState(
                    () => _direction = _direction == value ? null : value,
                  ),
                  onReviewOnly: () =>
                      setState(() => _reviewOnly = !_reviewOnly),
                ),
        ),
        const SizedBox(height: FlowSpace.xs),

        Expanded(
          child: app.transactions.isEmpty
              ? _EmptyLedger(
                  importing: app.importStatus.working,
                  onImport: () =>
                      ref.read(appControllerProvider.notifier).importMessages(),
                )
              : values.isEmpty
              ? _NoMatch(onClear: _clearFilters)
              : _LedgerList(
                  groups: groups,
                  grouping: _grouping,
                  currency: currency,
                  hidden: hidden,
                  selecting: selecting,
                  selected: _selected,
                  onTap: (item) {
                    if (selecting) {
                      _toggle(item);
                    } else if (item.id != null) {
                      TransactionDetailScreen.open(context, item.id!);
                    }
                  },
                  onLongPress: (item) {
                    unawaited(HapticFeedback.selectionClick());
                    _toggle(item);
                  },
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------- filtering

  List<MoneyTransaction> _filtered(List<MoneyTransaction> all) => [
    for (final item in all)
      if ((_query.isEmpty ||
              '${item.merchant} ${item.category} ${item.note ?? ''} '
                      '${item.account ?? ''}'
                  .toLowerCase()
                  .contains(_query)) &&
          (_direction == null || item.direction == _direction) &&
          (!_reviewOnly || item.reviewState == ReviewState.needsReview) &&
          (_from == null || !item.occurredAt.isBefore(_from!)) &&
          (_until == null || item.occurredAt.isBefore(_until!)))
        item,
  ];

  void _clearFilters() => setState(() {
    _search.clear();
    _query = '';
    _searching = false;
    _direction = null;
    _reviewOnly = false;
    _from = null;
    _until = null;
    _rangeLabel = 'All time';
  });

  /// Totals only make sense within one currency; the most frequent one in
  /// the filtered set stands for the rest rather than summing across rates.
  static String? _dominantCurrency(List<MoneyTransaction> values) {
    if (values.isEmpty) return null;
    final counts = <String, int>{};
    for (final item in values) {
      counts[item.currency] = (counts[item.currency] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  String _summaryLine(
    int count,
    _Totals totals,
    String? currency,
    bool hidden,
  ) {
    if (count == 0) return 'Nothing here';
    // U+2060 after the sign: line breaking treats +/− as breakable before a
    // currency symbol, which stranded a bare "+" at the end of a wrapped
    // line. A wrap may only fall between parts, never inside an amount.
    const joiner = '\u2060';
    final parts = [count == 1 ? '1 transaction' : '$count transactions'];
    if (currency != null && !hidden) {
      if (totals.outgoing > 0) {
        parts.add('−$joiner${formatMoney(totals.outgoing, currency)}');
      }
      if (totals.incoming > 0) {
        parts.add('+$joiner${formatMoney(totals.incoming, currency)}');
      }
    }
    return parts.join(' · ');
  }

  // -------------------------------------------------------------- grouping

  List<_Group> _grouped(List<MoneyTransaction> values, String? currency) {
    final byKey = <String, List<MoneyTransaction>>{};
    for (final item in values) {
      byKey.putIfAbsent(_groupKey(item), () => []).add(item);
    }

    final groups = [
      for (final entry in byKey.entries)
        _Group(
          label: _groupLabel(entry.value.first),
          sortKey: entry.key,
          items: entry.value..sort(_rowCompare),
          totals: _Totals.of(entry.value, currency),
        ),
    ];

    // Day groups stay chronological whatever the row sort — a ledger that
    // reorders its days by amount stops being a ledger. Category and
    // merchant groups rank by weight, which is what those views are for.
    if (_grouping == ActivityGrouping.day) {
      groups.sort(
        (a, b) => _sort == ActivitySort.oldest
            ? a.sortKey.compareTo(b.sortKey)
            : b.sortKey.compareTo(a.sortKey),
      );
    } else {
      groups.sort(
        (a, b) => (b.totals.incoming + b.totals.outgoing).compareTo(
          a.totals.incoming + a.totals.outgoing,
        ),
      );
    }
    return groups;
  }

  String _groupKey(MoneyTransaction item) => switch (_grouping) {
    ActivityGrouping.day => item.occurredAt.toIso8601String().substring(0, 10),
    ActivityGrouping.category => item.category.toLowerCase(),
    ActivityGrouping.merchant => item.merchant.toLowerCase(),
  };

  String _groupLabel(MoneyTransaction item) {
    switch (_grouping) {
      case ActivityGrouping.category:
        return item.category;
      case ActivityGrouping.merchant:
        return item.merchant;
      case ActivityGrouping.day:
        final day = DateUtils.dateOnly(item.occurredAt);
        final today = DateUtils.dateOnly(DateTime.now());
        if (day == today) return 'Today';
        if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
        return DateFormat(
          day.year == today.year ? 'EEEE, d MMM' : 'd MMM yyyy',
        ).format(day);
    }
  }

  int _rowCompare(MoneyTransaction a, MoneyTransaction b) => switch (_sort) {
    ActivitySort.newest => b.occurredAt.compareTo(a.occurredAt),
    ActivitySort.oldest => a.occurredAt.compareTo(b.occurredAt),
    ActivitySort.largest => b.amountMinor.compareTo(a.amountMinor),
    ActivitySort.smallest => a.amountMinor.compareTo(b.amountMinor),
  };

  // ------------------------------------------------------------ date range

  Future<void> _pickRange(_RangePreset preset) async {
    final now = DateTime.now();
    switch (preset) {
      case _RangePreset.all:
        setState(() {
          _from = null;
          _until = null;
          _rangeLabel = 'All time';
        });
      case _RangePreset.thisMonth:
        setState(() {
          _from = DateTime(now.year, now.month);
          _until = null;
          _rangeLabel = 'This month';
        });
      case _RangePreset.lastMonth:
        setState(() {
          _from = DateTime(now.year, now.month - 1);
          _until = DateTime(now.year, now.month);
          _rangeLabel = 'Last month';
        });
      case _RangePreset.threeMonths:
        setState(() {
          _from = DateTime(now.year, now.month - 2);
          _until = null;
          _rangeLabel = 'Last 3 months';
        });
      case _RangePreset.custom:
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2000),
          lastDate: now,
          initialDateRange: _from == null
              ? null
              : DateTimeRange(
                  start: _from!,
                  end: (_until ?? now).subtract(const Duration(days: 1)),
                ),
        );
        if (picked == null) return;
        setState(() {
          _from = picked.start;
          _until = picked.end.add(const Duration(days: 1));
          final format = DateFormat('d MMM');
          _rangeLabel =
              '${format.format(picked.start)} – ${format.format(picked.end)}';
        });
    }
  }

  // ------------------------------------------------------------- selection

  void _toggle(MoneyTransaction item) {
    final id = item.id;
    if (id == null) return;
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  List<MoneyTransaction> _selectedItems(List<MoneyTransaction> values) => [
    for (final item in values)
      if (_selected.contains(item.id)) item,
  ];

  Future<void> _bulkCategory(List<MoneyTransaction> values) async {
    final items = _selectedItems(values);
    final choice = await pickCategory(
      context,
      title: items.length == 1
          ? 'Category for 1 transaction'
          : 'Category for ${items.length} transactions',
    );
    if (choice == null || !mounted) return;
    final controller = ref.read(appControllerProvider.notifier);
    for (final item in items) {
      // A person stating the category is the strongest signal there is, so
      // the correction also settles any pending review.
      await controller.saveTransaction(
        item.copyWith(
          category: choice,
          reviewState: ReviewState.confirmed,
          confidence: 1,
        ),
      );
    }
    if (mounted) setState(_selected.clear);
  }

  Future<void> _bulkConfirm(List<MoneyTransaction> values) async {
    final controller = ref.read(appControllerProvider.notifier);
    for (final item in _selectedItems(values)) {
      if (item.reviewState == ReviewState.needsReview) {
        await controller.confirmTransaction(item);
      }
    }
    if (mounted) setState(_selected.clear);
  }

  Future<void> _bulkDelete(List<MoneyTransaction> values) async {
    final items = _selectedItems(values);
    final confirmed = await confirmDeleteTransactions(
      context,
      count: items.length,
    );
    if (!confirmed || !mounted) return;
    final controller = ref.read(appControllerProvider.notifier);
    for (final item in items) {
      if (item.id != null) await controller.deleteTransaction(item.id!);
    }
    if (mounted) setState(_selected.clear);
  }

  /// Manual entry only; existing rows open the detail route instead.
  Future<void> _edit(MoneyTransaction? item) =>
      showTransactionEditor(context, transaction: item);
}

// --------------------------------------------------------------- filter row

enum _RangePreset { all, thisMonth, lastMonth, threeMonths, custom }

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.grouping,
    required this.sort,
    required this.rangeLabel,
    required this.rangeActive,
    required this.direction,
    required this.reviewOnly,
    required this.onGrouping,
    required this.onSort,
    required this.onRange,
    required this.onDirection,
    required this.onReviewOnly,
  });

  final ActivityGrouping grouping;
  final ActivitySort sort;
  final String rangeLabel;
  final bool rangeActive;
  final TransactionDirection? direction;
  final bool reviewOnly;
  final ValueChanged<ActivityGrouping> onGrouping;
  final ValueChanged<ActivitySort> onSort;
  final ValueChanged<_RangePreset> onRange;
  final ValueChanged<TransactionDirection> onDirection;
  final VoidCallback onReviewOnly;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 36,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: FlowSpace.xl),
      children: [
        _MenuChip<ActivityGrouping>(
          label: switch (grouping) {
            ActivityGrouping.day => 'By day',
            ActivityGrouping.category => 'By category',
            ActivityGrouping.merchant => 'By merchant',
          },
          // Grouping always has a value, so the chip reads as a mode rather
          // than a filter and never shows as "active".
          active: false,
          entries: const [
            (ActivityGrouping.day, 'By day'),
            (ActivityGrouping.category, 'By category'),
            (ActivityGrouping.merchant, 'By merchant'),
          ],
          onSelected: onGrouping,
        ),
        const SizedBox(width: FlowSpace.sm),
        _MenuChip<_RangePreset>(
          label: rangeLabel,
          active: rangeActive,
          entries: const [
            (_RangePreset.all, 'All time'),
            (_RangePreset.thisMonth, 'This month'),
            (_RangePreset.lastMonth, 'Last month'),
            (_RangePreset.threeMonths, 'Last 3 months'),
            (_RangePreset.custom, 'Pick dates…'),
          ],
          onSelected: onRange,
        ),
        const SizedBox(width: FlowSpace.sm),
        _FilterChip(
          label: 'In',
          selected: direction == TransactionDirection.incoming,
          onTap: () => onDirection(TransactionDirection.incoming),
        ),
        const SizedBox(width: FlowSpace.sm),
        _FilterChip(
          label: 'Out',
          selected: direction == TransactionDirection.outgoing,
          onTap: () => onDirection(TransactionDirection.outgoing),
        ),
        const SizedBox(width: FlowSpace.sm),
        _FilterChip(
          label: 'Needs review',
          selected: reviewOnly,
          onTap: onReviewOnly,
        ),
        const SizedBox(width: FlowSpace.sm),
        _MenuChip<ActivitySort>(
          label: switch (sort) {
            ActivitySort.newest => 'Newest',
            ActivitySort.oldest => 'Oldest',
            ActivitySort.largest => 'Largest',
            ActivitySort.smallest => 'Smallest',
          },
          active: sort != ActivitySort.newest,
          entries: const [
            (ActivitySort.newest, 'Newest'),
            (ActivitySort.oldest, 'Oldest'),
            (ActivitySort.largest, 'Largest'),
            (ActivitySort.smallest, 'Smallest'),
          ],
          onSelected: onSort,
        ),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
        borderRadius: FlowRadius.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
          alignment: Alignment.center,
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

class _MenuChip<T> extends StatelessWidget {
  const _MenuChip({
    required this.label,
    required this.active,
    required this.entries,
    required this.onSelected,
  });

  final String label;
  final bool active;
  final List<(T, String)> entries;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return PopupMenuButton<T>(
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in entries)
          PopupMenuItem<T>(value: entry.$1, child: Text(entry.$2)),
      ],
      child: Container(
        padding: const EdgeInsets.only(left: FlowSpace.md, right: FlowSpace.sm),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? flow.accent : flow.raised,
          borderRadius: FlowRadius.pill,
          border: Border.all(color: active ? flow.accent : flow.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: active ? flow.onAccent : flow.ink,
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: active ? flow.onAccent : flow.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ selection bar

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.total,
    required this.anyPending,
    required this.onSelectAll,
    required this.onCategory,
    required this.onConfirm,
    required this.onDelete,
    required this.onClose,
  });

  final int count;
  final int total;
  final bool anyPending;
  final VoidCallback onSelectAll;
  final VoidCallback onCategory;
  final VoidCallback onConfirm;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.xl),
        children: [
          Center(
            child: Text(
              '$count selected',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          const SizedBox(width: FlowSpace.md),
          if (count < total) ...[
            _FilterChip(label: 'All', selected: false, onTap: onSelectAll),
            const SizedBox(width: FlowSpace.sm),
          ],
          _FilterChip(label: 'Category', selected: false, onTap: onCategory),
          if (anyPending) ...[
            const SizedBox(width: FlowSpace.sm),
            _FilterChip(label: 'Confirm', selected: false, onTap: onConfirm),
          ],
          const SizedBox(width: FlowSpace.sm),
          _DangerChip(label: 'Delete', onTap: onDelete),
          const SizedBox(width: FlowSpace.sm),
          _FilterChip(label: 'Done', selected: false, onTap: onClose),
        ],
      ),
    );
  }
}

class _DangerChip extends StatelessWidget {
  const _DangerChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return InkWell(
      onTap: onTap,
      borderRadius: FlowRadius.pill,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: FlowSpace.md),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: FlowRadius.pill,
          border: Border.all(color: flow.expense.withValues(alpha: .6)),
        ),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: flow.expense),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- ledger

class _Group {
  const _Group({
    required this.label,
    required this.sortKey,
    required this.items,
    required this.totals,
  });

  final String label;
  final String sortKey;
  final List<MoneyTransaction> items;
  final _Totals totals;
}

class _Totals {
  const _Totals({required this.incoming, required this.outgoing});

  final int incoming;
  final int outgoing;

  static _Totals of(List<MoneyTransaction> values, String? currency) {
    var incoming = 0;
    var outgoing = 0;
    for (final item in values) {
      if (item.currency != currency) continue;
      if (item.direction == TransactionDirection.incoming) {
        incoming += item.amountMinor;
      } else {
        outgoing += item.amountMinor;
      }
    }
    return _Totals(incoming: incoming, outgoing: outgoing);
  }
}

class _LedgerList extends StatelessWidget {
  const _LedgerList({
    required this.groups,
    required this.grouping,
    required this.currency,
    required this.hidden,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final List<_Group> groups;
  final ActivityGrouping grouping;
  final String? currency;
  final bool hidden;
  final bool selecting;
  final Set<int> selected;
  final ValueChanged<MoneyTransaction> onTap;
  final ValueChanged<MoneyTransaction> onLongPress;

  @override
  Widget build(BuildContext context) {
    // Flattened so the builder stays O(visible) over hundreds of rows.
    final entries = <Object>[];
    for (final group in groups) {
      entries.add(group);
      entries.addAll(group.items);
    }

    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: FlowSpace.xl + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is _Group) {
          return _GroupHeader(group: entry, currency: currency, hidden: hidden);
        }
        final item = entry as MoneyTransaction;
        return _LedgerRow(
          item: item,
          grouping: grouping,
          hidden: hidden,
          selecting: selecting,
          selected: selected.contains(item.id),
          onTap: () => onTap(item),
          onLongPress: () => onLongPress(item),
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.currency,
    required this.hidden,
  });

  final _Group group;
  final String? currency;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FlowSpace.xl,
        FlowSpace.lg,
        FlowSpace.xl,
        FlowSpace.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(color: flow.inkSoft),
            ),
          ),
          if (currency != null && !hidden) ...[
            if (group.totals.incoming > 0)
              Padding(
                padding: const EdgeInsets.only(left: FlowSpace.sm),
                child: Text(
                  '+${formatMoney(group.totals.incoming, currency!)}',
                  style: FlowType.amountSmall.copyWith(color: flow.income),
                ),
              ),
            if (group.totals.outgoing > 0)
              Padding(
                padding: const EdgeInsets.only(left: FlowSpace.sm),
                child: Text(
                  '−${formatMoney(group.totals.outgoing, currency!)}',
                  style: FlowType.amountSmall.copyWith(color: flow.inkSoft),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Header action that reads more messages, spinning while it works.
class _SyncButton extends StatelessWidget {
  const _SyncButton({required this.working, required this.onSync});

  final bool working;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return IconButton(
      tooltip: working ? 'Reading messages…' : 'Sync messages',
      onPressed: working ? null : onSync,
      color: flow.inkSoft,
      icon: working
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: flow.accent,
              ),
            )
          : const Icon(Icons.sync_rounded),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.item,
    required this.grouping,
    required this.hidden,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final MoneyTransaction item;
  final ActivityGrouping grouping;
  final bool hidden;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final incoming = item.direction == TransactionDirection.incoming;
    final pending = item.reviewState == ReviewState.needsReview;

    final when = grouping == ActivityGrouping.day
        ? DateFormat('h:mm a').format(item.occurredAt)
        : DateFormat('d MMM').format(item.occurredAt);
    // Grouped by category the category is already the header, so the row
    // spends its subline on when instead of repeating it.
    final subline = switch (grouping) {
      ActivityGrouping.category => when,
      _ => '${item.category} · $when',
    };

    return Semantics(
      button: true,
      selected: selected,
      label:
          '${item.merchant}, ${incoming ? 'in' : 'out'} '
          '${formatMoney(item.amountMinor, item.currency)}'
          '${pending ? ', needs review' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(minHeight: FlowDensity.compactRow),
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpace.xl,
            vertical: FlowSpace.xs,
          ),
          color: selected ? flow.accent.withValues(alpha: .10) : null,
          child: Row(
            children: [
              if (selecting)
                Padding(
                  padding: const EdgeInsets.only(right: FlowSpace.md),
                  child: Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 18,
                    color: selected ? flow.accent : flow.inkFaint,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: FlowSpace.md),
                  // Money in is the exception worth marking, so it keeps a
                  // dedicated avatar; everything else is identified by its
                  // category. A pending row carries a small dot so "needs a
                  // look" is visible without reading the subline.
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (incoming)
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: flow.income.withValues(alpha: .16),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.south_west_rounded,
                            size: 19,
                            color: flow.income,
                          ),
                        )
                      else
                        FlowCategoryAvatar(category: item.category),
                      if (pending)
                        Positioned(
                          right: -1,
                          top: -1,
                          child: Container(
                            width: 11,
                            height: 11,
                            decoration: BoxDecoration(
                              color: flow.attention,
                              shape: BoxShape.circle,
                              border: Border.all(color: flow.canvas, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.merchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      pending ? '$subline · needs a look' : subline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: pending ? flow.attention : flow.inkFaint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FlowSpace.md),
              Text(
                hidden
                    ? '••••'
                    : '${incoming ? '+' : '−'}'
                          '${formatMoney(item.amountMinor, item.currency)}',
                style: FlowType.amountRow.copyWith(
                  color: incoming ? flow.income : flow.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- empty states

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.importing, required this.onImport});
  final bool importing;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FlowSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.receipt_long_outlined, size: 28, color: flow.accent),
            const SizedBox(height: FlowSpace.lg),
            Text(
              'Your record starts here.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: FlowSpace.sm),
            Text(
              'Fund Flow reads your transaction messages and keeps the '
              'ledger for you. Nothing is typed in by hand.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.lg),
            FilledButton.icon(
              onPressed: importing ? null : onImport,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(FlowDensity.minimumTarget),
                backgroundColor: flow.accent,
                foregroundColor: flow.onAccent,
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadius.sm,
                ),
              ),
              icon: const Icon(Icons.sms_outlined, size: 18),
              label: Text(importing ? 'Checking messages…' : 'Check messages'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatch extends StatelessWidget {
  const _NoMatch({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Nothing matches',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: FlowSpace.xs),
          Text(
            'No transactions fit the current filters.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: flow.inkSoft),
          ),
          const SizedBox(height: FlowSpace.md),
          TextButton(onPressed: onClear, child: const Text('Clear filters')),
        ],
      ),
    );
  }
}
