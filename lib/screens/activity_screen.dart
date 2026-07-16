import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/development_update_ui.dart';
import '../widgets/expense_form_sheet.dart';
import '../widgets/ui/command_ui.dart';
import 'settings_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _direction = 'all';
  DateTimeRange? _dateRange;
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expenseListProvider);
    final hidden = ref.watch(privateModeProvider);
    return CommandScaffold(
      eyebrow: 'Search · review · understand',
      title: 'Total Activity',
      actions: [
        IconButton(
          tooltip: hidden ? 'Show amounts' : 'Hide amounts',
          onPressed: () => ref.read(privateModeProvider.notifier).toggle(),
          icon: Icon(
            hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
      slivers: [
        const SliverToBoxAdapter(child: DevelopmentUpdateBanner()),
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.receipt_long_rounded,
              title: 'Transactions are temporarily unavailable',
              message: '$error',
            ),
          ),
          data: (all) {
            final visible = all.where((event) {
              final direction =
                  _direction == 'all' ||
                  (_direction == 'in' ? event.isIncome : !event.isIncome);
              final words = '${event.merchant} ${event.category} ${event.tags}'
                  .toLowerCase();
              final inRange =
                  _dateRange == null ||
                  (!event.date.isBefore(_dateRange!.start) &&
                      event.date.isBefore(
                        _dateRange!.end.add(const Duration(days: 1)),
                      ));
              final inCategory =
                  _category == null || event.category == _category;
              return direction &&
                  inRange &&
                  inCategory &&
                  words.contains(_query);
            }).toList();
            final thisMonth = all.where((e) {
              final now = DateTime.now();
              return e.date.year == now.year && e.date.month == now.month;
            }).toList();
            final understood = thisMonth.length;
            final automated = thisMonth
                .where((e) => e.originalSms.isNotEmpty)
                .length;
            final days = <DateTime, List<Expense>>{};
            for (final event in visible) {
              days
                  .putIfAbsent(DateUtils.dateOnly(event.date), () => [])
                  .add(event);
            }

            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _MemoryLens(
                          controller: _search,
                          query: _query,
                          direction: _direction,
                          understood: understood,
                          automated: automated,
                          onQuery: (value) => setState(
                            () => _query = value.trim().toLowerCase(),
                          ),
                          onDirection: (value) =>
                              setState(() => _direction = value),
                        ),
                        const SizedBox(height: 12),
                        _ActivityFilters(
                          dateRange: _dateRange,
                          category: _category,
                          categories:
                              all
                                  .map((event) => event.category)
                                  .toSet()
                                  .toList()
                                ..sort(),
                          onDateRange: _pickDateRange,
                          onCategory: (value) =>
                              setState(() => _category = value),
                          onClear: () => setState(() {
                            _dateRange = null;
                            _category = null;
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: StatePanel(
                      icon: Icons.blur_off_rounded,
                      title: 'No matching transactions',
                      message: 'Try different words or change the type filter.',
                    ),
                  )
                else ...[
                  const SliverToBoxAdapter(child: SectionLabel('Transactions')),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                    sliver: SliverList.builder(
                      itemCount: days.length,
                      itemBuilder: (context, dayIndex) {
                        final entry = days.entries.elementAt(dayIndex);
                        return _DayFragment(
                          day: entry.key,
                          events: entry.value,
                          hidden: hidden,
                          onOpen: _edit,
                        );
                      },
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      helpText: 'Filter transactions by date',
    );
    if (selected != null && mounted) setState(() => _dateRange = selected);
  }

  Future<void> _edit(Expense expense) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => ExpenseFormSheet(
        initialExpense: expense,
        onSave: (value) async {
          await ref.read(expenseListProvider.notifier).updateExpense(value);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
        onDelete: expense.id == null
            ? null
            : () async {
                await ref
                    .read(expenseListProvider.notifier)
                    .deleteExpense(expense.id!);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
      ),
    );
  }
}

class _ActivityFilters extends StatelessWidget {
  const _ActivityFilters({
    required this.dateRange,
    required this.category,
    required this.categories,
    required this.onDateRange,
    required this.onCategory,
    required this.onClear,
  });
  final DateTimeRange? dateRange;
  final String? category;
  final List<String> categories;
  final VoidCallback onDateRange;
  final ValueChanged<String?> onCategory;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final active = dateRange != null || category != null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDateRange,
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: Text(
              dateRange == null
                  ? 'Any date'
                  : '${DateFormat('d MMM').format(dateRange!.start)} – ${DateFormat('d MMM').format(dateRange!.end)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PopupMenuButton<String?>(
            onSelected: onCategory,
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All categories')),
              for (final value in categories)
                PopupMenuItem(value: value, child: Text(value)),
            ],
            child: InputChip(
              avatar: const Icon(Icons.category_outlined, size: 18),
              label: Text(
                category ?? 'All categories',
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: null,
            ),
          ),
        ),
        if (active)
          IconButton(
            tooltip: 'Clear filters',
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off_rounded),
          ),
      ],
    );
  }
}

class _MemoryLens extends StatelessWidget {
  const _MemoryLens({
    required this.controller,
    required this.query,
    required this.direction,
    required this.understood,
    required this.automated,
    required this.onQuery,
    required this.onDirection,
  });
  final TextEditingController controller;
  final String query;
  final String direction;
  final int understood;
  final int automated;
  final ValueChanged<String> onQuery;
  final ValueChanged<String> onDirection;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFF090D16),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(36),
        bottomLeft: Radius.circular(36),
        bottomRight: Radius.circular(8),
      ),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      children: [
        TextField(
          controller: controller,
          onChanged: onQuery,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search merchant, category, tag, or salary…',
            hintStyle: const TextStyle(color: Colors.white38),
            prefixIcon: const Icon(
              Icons.manage_search_rounded,
              color: Color(0xFFC7FF4A),
            ),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      controller.clear();
                      onQuery('');
                    },
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white54,
                    ),
                  ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: .06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            _LensChoice(
              label: 'ALL',
              active: direction == 'all',
              onTap: () => onDirection('all'),
            ),
            _LensChoice(
              label: 'OUT',
              active: direction == 'out',
              onTap: () => onDirection('out'),
            ),
            _LensChoice(
              label: 'IN',
              active: direction == 'in',
              onTap: () => onDirection('in'),
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$understood this month',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  '$automated imported automatically',
                  style: const TextStyle(color: Colors.white30, fontSize: 9),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );
}

class _LensChoice extends StatelessWidget {
  const _LensChoice({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: active,
    label: switch (label) {
      'ALL' => 'All transactions',
      'OUT' => 'Expenses only',
      'IN' => 'Income only',
      _ => label,
    },
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFFC7FF4A) : Colors.white38,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ),
    ),
  );
}

class _DayFragment extends StatelessWidget {
  const _DayFragment({
    required this.day,
    required this.events,
    required this.hidden,
    required this.onOpen,
  });
  final DateTime day;
  final List<Expense> events;
  final bool hidden;
  final ValueChanged<Expense> onOpen;

  @override
  Widget build(BuildContext context) {
    final total = events.fold<double>(
      0,
      (sum, event) => sum + (event.isIncome ? event.amount : -event.amount),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Column(
              children: [
                Text(
                  DateFormat('dd').format(day),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  DateFormat('MMM').format(day).toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 1,
                  ),
                ),
                Container(
                  width: 1,
                  height: 34,
                  margin: const EdgeInsets.only(top: 8),
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: .72),
                border: Border(
                  left: BorderSide(
                    color: total >= 0
                        ? context.finance.income
                        : context.finance.expense,
                    width: 2,
                  ),
                ),
              ),
              child: Column(
                children: [
                  for (final event in events)
                    _MemoryEvent(
                      event: event,
                      hidden: hidden,
                      onTap: () => onOpen(event),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryEvent extends StatelessWidget {
  const _MemoryEvent({
    required this.event,
    required this.hidden,
    required this.onTap,
  });
  final Expense event;
  final bool hidden;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = event.isIncome
        ? context.finance.income
        : categoryColor(event.category);
    final amount = hidden
        ? 'hidden amount'
        : '${event.isIncome ? 'income' : 'expense'} ${formatAmount(event.amount, event.currency)}';
    return Semantics(
      button: true,
      label:
          '${event.displayMerchant}, $amount, ${event.category}, ${DateFormat('d MMMM, h:mm a').format(event.date)}',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            children: [
              Icon(
                event.isIncome
                    ? Icons.call_received_rounded
                    : categoryIcon(event.category),
                color: color,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.displayMerchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${DateFormat('h:mm a').format(event.date)} · ${event.category} · ${event.originalSms.isEmpty ? 'manual' : 'automatic'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                hidden
                    ? maskAmount(event.currency)
                    : '${event.isIncome ? '+' : '−'}${formatAmount(event.amount, event.currency)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: event.isIncome ? color : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
