import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/expense_form_sheet.dart';
import '../widgets/ui/command_ui.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});
  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _direction = 'all';

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
      eyebrow: 'Observed · inferred · verified',
      title: 'Money memory',
      slivers: [
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.memory_rounded,
              title: 'Memory is temporarily quiet',
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
              return direction && words.contains(_query);
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
                    child: _MemoryLens(
                      controller: _search,
                      query: _query,
                      direction: _direction,
                      understood: understood,
                      automated: automated,
                      onQuery: (value) =>
                          setState(() => _query = value.trim().toLowerCase()),
                      onDirection: (value) =>
                          setState(() => _direction = value),
                    ),
                  ),
                ),
                if (visible.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: StatePanel(
                      icon: Icons.blur_off_rounded,
                      title: 'No memory resonates',
                      message:
                          'Change the words or widen the signal direction.',
                    ),
                  )
                else ...[
                  const SliverToBoxAdapter(
                    child: SectionLabel('Memory fragments'),
                  ),
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
            hintText: 'Recall “coffee last winter” or “salary”…',
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
                  '$understood understood',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                Text(
                  '$automated sensed automatically',
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
  Widget build(BuildContext context) => InkWell(
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
    return InkWell(
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
                    '${DateFormat('h:mm a').format(event.date)} · ${event.category} · ${event.originalSms.isEmpty ? 'taught' : 'sensed'}',
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
    );
  }
}
