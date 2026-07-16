import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/development_update_ui.dart';
import '../widgets/expense_form_sheet.dart';
import '../widgets/money_chat_sheet.dart';
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            onPressed: () => ref.read(privateModeProvider.notifier).toggle(),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          IconButton(
            tooltip: 'Add transaction',
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: async.when(
        loading: () => const _ActivityLoading(),
        error: (error, _) => _EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Transactions unavailable',
          message: '$error',
          action: 'Try again',
          onAction: () => ref.invalidate(expenseListProvider),
        ),
        data: (all) => _content(all, hidden),
      ),
    );
  }

  Widget _content(List<Expense> all, bool hidden) {
    final now = DateTime.now();
    final month = all.where(
      (item) => item.date.year == now.year && item.date.month == now.month,
    );
    final spent = month
        .where((item) => !item.isIncome)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final received = month
        .where((item) => item.isIncome)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final currency =
        all.firstOrNull?.currency ??
        ref.watch(preferredCurrencyProvider) ??
        'INR';
    final visible = all.where(_matches).toList();
    final groups = <DateTime, List<Expense>>{};
    for (final item in visible) {
      groups.putIfAbsent(DateUtils.dateOnly(item.date), () => []).add(item);
    }
    final categories = all.map((item) => item.category).toSet().toList()
      ..sort();

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        const SliverToBoxAdapter(child: DevelopmentUpdateBanner()),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchField(
                  controller: _search,
                  query: _query,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
                const SizedBox(height: 16),
                _MonthlySummary(
                  spent: spent,
                  received: received,
                  currency: currency,
                  hidden: hidden,
                  onSpent: () => setState(() => _direction = 'out'),
                  onReceived: () => setState(() => _direction = 'in'),
                ),
                const SizedBox(height: 16),
                _FilterBar(
                  direction: _direction,
                  dateRange: _dateRange,
                  category: _category,
                  categories: categories,
                  onDirection: (value) => setState(() => _direction = value),
                  onDate: _pickDateRange,
                  onCategory: (value) => setState(() => _category = value),
                  onClear: _clearFilters,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: all.isEmpty
                  ? Icons.receipt_long_outlined
                  : Icons.search_off_rounded,
              title: all.isEmpty ? 'No transactions yet' : 'No results',
              message: all.isEmpty
                  ? 'Add a transaction or sync your bank messages to get started.'
                  : 'Try another search or clear the filters.',
              action: all.isEmpty ? 'Add transaction' : 'Clear filters',
              onAction: all.isEmpty ? _add : _clearFilters,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
            sliver: SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups.entries.elementAt(index);
                return _TransactionGroup(
                  day: group.key,
                  transactions: group.value,
                  hidden: hidden,
                  onTap: _showDetails,
                  onEdit: _edit,
                );
              },
            ),
          ),
      ],
    );
  }

  bool _matches(Expense item) {
    final direction =
        _direction == 'all' ||
        (_direction == 'in' ? item.isIncome : !item.isIncome);
    final words =
        '${item.displayMerchant} ${item.category} ${item.tags} '
                '${item.amount.toStringAsFixed(2)}'
            .toLowerCase();
    final inRange =
        _dateRange == null ||
        (!item.date.isBefore(_dateRange!.start) &&
            item.date.isBefore(_dateRange!.end.add(const Duration(days: 1))));
    return direction &&
        inRange &&
        (_category == null || item.category == _category) &&
        words.contains(_query);
  }

  void _clearFilters() => setState(() {
    _query = '';
    _search.clear();
    _direction = 'all';
    _dateRange = null;
    _category = null;
  });

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final value = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now.add(const Duration(days: 1)),
      initialDateRange: _dateRange,
      helpText: 'Choose date range',
    );
    if (value != null && mounted) setState(() => _dateRange = value);
  }

  Future<void> _add() => _openForm();

  Future<void> _edit(Expense expense) => _openForm(expense);

  Future<void> _openForm([Expense? expense]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ExpenseFormSheet(
        initialExpense: expense,
        onSave: (value) async {
          if (expense == null) {
            await ref.read(expenseListProvider.notifier).addExpense(value);
          } else {
            await ref.read(expenseListProvider.notifier).updateExpense(value);
          }
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
        onDelete: expense?.id == null
            ? null
            : () async {
                await ref
                    .read(expenseListProvider.notifier)
                    .deleteExpense(expense!.id!);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
      ),
    );
  }

  Future<void> _showDetails(Expense item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _TransactionDetails(
        item: item,
        onEdit: () {
          Navigator.pop(sheetContext);
          _edit(item);
        },
        onReanalyze: item.originalSms.isEmpty
            ? null
            : () {
                Navigator.pop(sheetContext);
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MoneyChatSheet(
                      fullScreen: true,
                      initialPrompt:
                          'Re-analyze transaction ${item.id} from its original SMS and propose any source, destination, or category corrections.',
                    ),
                  ),
                );
              },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SearchBar(
    controller: controller,
    hintText: 'Search transactions',
    leading: const Icon(Icons.search_rounded),
    trailing: [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Clear search',
          onPressed: () {
            controller.clear();
            onChanged('');
          },
          icon: const Icon(Icons.close_rounded),
        ),
    ],
    elevation: const WidgetStatePropertyAll(0),
    backgroundColor: WidgetStatePropertyAll(
      Theme.of(context).colorScheme.surfaceContainerHigh,
    ),
    onChanged: onChanged,
  );
}

class _MonthlySummary extends StatelessWidget {
  const _MonthlySummary({
    required this.spent,
    required this.received,
    required this.currency,
    required this.hidden,
    required this.onSpent,
    required this.onReceived,
  });
  final double spent;
  final double received;
  final String currency;
  final bool hidden;
  final VoidCallback onSpent;
  final VoidCallback onReceived;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This month', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  label: 'Money out',
                  amount: spent,
                  currency: currency,
                  hidden: hidden,
                  color: Theme.of(context).colorScheme.onSurface,
                  onTap: onSpent,
                ),
              ),
              SizedBox(
                height: 46,
                child: VerticalDivider(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  label: 'Money in',
                  amount: received,
                  currency: currency,
                  hidden: hidden,
                  color: context.finance.income,
                  onTap: onReceived,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.amount,
    required this.currency,
    required this.hidden,
    required this.color,
    required this.onTap,
  });
  final String label;
  final double amount;
  final String currency;
  final bool hidden;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              hidden ? maskAmount(currency) : formatAmount(amount, currency),
              style: AppTheme.money(
                Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.direction,
    required this.dateRange,
    required this.category,
    required this.categories,
    required this.onDirection,
    required this.onDate,
    required this.onCategory,
    required this.onClear,
  });
  final String direction;
  final DateTimeRange? dateRange;
  final String? category;
  final List<String> categories;
  final ValueChanged<String> onDirection;
  final VoidCallback onDate;
  final ValueChanged<String?> onCategory;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final active = dateRange != null || category != null || direction != 'all';
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final value in const [
            ('all', 'All'),
            ('out', 'Money out'),
            ('in', 'Money in'),
          ]) ...[
            FilterChip(
              label: Text(value.$2),
              selected: direction == value.$1,
              onSelected: (_) => onDirection(value.$1),
            ),
            const SizedBox(width: 8),
          ],
          ActionChip(
            avatar: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
              dateRange == null
                  ? 'Date'
                  : '${DateFormat('d MMM').format(dateRange!.start)}–${DateFormat('d MMM').format(dateRange!.end)}',
            ),
            onPressed: onDate,
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String?>(
            onSelected: onCategory,
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('All categories')),
              for (final value in categories)
                PopupMenuItem(value: value, child: Text(value)),
            ],
            child: Chip(
              avatar: const Icon(Icons.category_outlined, size: 18),
              label: Text(category ?? 'Category'),
            ),
          ),
          if (active) ...[
            const SizedBox(width: 4),
            TextButton(onPressed: onClear, child: const Text('Clear')),
          ],
        ],
      ),
    );
  }
}

class _TransactionGroup extends StatelessWidget {
  const _TransactionGroup({
    required this.day,
    required this.transactions,
    required this.hidden,
    required this.onTap,
    required this.onEdit,
  });
  final DateTime day;
  final List<Expense> transactions;
  final bool hidden;
  final ValueChanged<Expense> onTap;
  final ValueChanged<Expense> onEdit;

  String _label() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEEE, d MMMM').format(day);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          _label(),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      Card(
        child: Column(
          children: [
            for (var index = 0; index < transactions.length; index++) ...[
              _TransactionRow(
                item: transactions[index],
                hidden: hidden,
                onTap: () => onTap(transactions[index]),
                onEdit: () => onEdit(transactions[index]),
              ),
              if (index != transactions.length - 1)
                const Divider(height: 1, indent: 72),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
    ],
  );
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.item,
    required this.hidden,
    required this.onTap,
    required this.onEdit,
  });
  final Expense item;
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  bool get needsReview =>
      item.displayMerchant.trim().isEmpty ||
      item.displayMerchant.toLowerCase() == 'unknown';

  @override
  Widget build(BuildContext context) {
    final amount = hidden
        ? maskAmount(item.currency)
        : '${item.isIncome ? '+' : '−'}${formatAmount(item.amount, item.currency)}';
    final avatarColor = needsReview
        ? context.finance.warningSurface
        : item.isIncome
        ? context.finance.incomeSurface
        : Theme.of(context).colorScheme.surfaceContainerHigh;
    final iconColor = needsReview
        ? context.finance.warning
        : item.isIncome
        ? context.finance.income
        : categoryColor(item.category);
    return Semantics(
      button: true,
      label:
          '${needsReview ? 'Needs review' : item.displayMerchant}, $amount, ${item.category}, ${DateFormat('d MMMM, h:mm a').format(item.date)}',
      child: InkWell(
        onTap: onTap,
        onLongPress: onEdit,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: avatarColor,
                child: Icon(
                  needsReview
                      ? Icons.priority_high_rounded
                      : item.isIncome
                      ? Icons.south_west_rounded
                      : categoryIcon(item.category),
                  color: iconColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      needsReview ? 'Needs review' : item.displayMerchant,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      needsReview
                          ? 'Source or destination wasn’t detected'
                          : '${item.category} • ${item.originalSms.isEmpty ? 'Manual' : 'SMS'} • ${DateFormat('h:mm a').format(item.date)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: needsReview
                            ? context.finance.warning
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                amount,
                style: AppTheme.money(
                  Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: item.isIncome ? context.finance.income : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionDetails extends StatelessWidget {
  const _TransactionDetails({
    required this.item,
    required this.onEdit,
    required this.onReanalyze,
  });
  final Expense item;
  final VoidCallback onEdit;
  final VoidCallback? onReanalyze;

  bool get needsReview =>
      item.displayMerchant.trim().isEmpty ||
      item.displayMerchant.toLowerCase() == 'unknown';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text(
              item.isIncome ? 'Money received' : 'Money sent',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${item.isIncome ? '+' : '−'}${formatAmount(item.amount, item.currency)}',
              style: AppTheme.money(Theme.of(context).textTheme.headlineMedium),
            ),
          ),
          const SizedBox(height: 28),
          _DetailLine(
            label: item.isIncome ? 'From' : 'To',
            value: needsReview ? 'Unknown' : item.displayMerchant,
            warning: needsReview,
          ),
          _DetailLine(label: 'Category', value: item.category),
          _DetailLine(
            label: 'Date',
            value: DateFormat('d MMMM yyyy, h:mm a').format(item.date),
          ),
          _DetailLine(
            label: 'Added from',
            value: item.originalSms.isEmpty ? 'Manual entry' : 'Bank SMS',
          ),
          if (item.tags.trim().isNotEmpty)
            _DetailLine(label: 'Tags', value: item.tags),
          const SizedBox(height: 20),
          if (needsReview && onReanalyze != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onReanalyze,
                icon: const Icon(Icons.auto_awesome_outlined),
                label: const Text('Analyze original SMS'),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit transaction'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
    this.warning = false,
  });
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: warning ? context.finance.warning : null,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    ),
  );
}

class _ActivityLoading extends StatelessWidget {
  const _ActivityLoading();

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: 7,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, index) => Container(
      height: index == 0
          ? 56
          : index == 1
          ? 112
          : 72,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
  );
}
