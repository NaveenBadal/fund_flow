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
import 'settings_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(expenseListProvider);
    final sync = ref.watch(syncProvider);
    final hidden = ref.watch(privateModeProvider);

    return CommandScaffold(
      eyebrow: DateFormat('EEEE · d MMMM').format(DateTime.now()),
      title: 'Today',
      actions: [
        IconButton(
          tooltip: hidden ? 'Reveal amounts' : 'Hide amounts',
          onPressed: () => ref.read(privateModeProvider.notifier).toggle(),
          icon: Icon(
            hidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            icon: const Icon(Icons.tune_rounded),
          ),
        ),
      ],
      floatingActionButton: _QuickAction(
        syncing: sync.isActive,
        onSync: () => ref.read(syncProvider.notifier).sync(),
        onAdd: () => _openExpense(context, ref),
      ),
      slivers: [
        if (sync.phase != SyncPhase.idle)
          SliverToBoxAdapter(child: _SyncLine(sync)),
        entries.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.cloud_off_rounded,
              title: 'Your data took a detour',
              message: '$error',
              action: FilledButton(
                onPressed: () => ref.invalidate(expenseListProvider),
                child: const Text('Try again'),
              ),
            ),
          ),
          data: (items) => items.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: StatePanel(
                    icon: Icons.south_west_rounded,
                    title: 'Your money story starts here',
                    message:
                        'Sync bank messages or add the first transaction. Everything stays organized automatically.',
                    action: FilledButton.icon(
                      onPressed: () => ref.read(syncProvider.notifier).sync(),
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text('Sync messages'),
                    ),
                  ),
                )
              : _TodayContent(
                  items: items,
                  hidden: hidden,
                  onOpen: (e) => _openExpense(context, ref, e),
                ),
        ),
      ],
    );
  }

  static Future<void> _openExpense(
    BuildContext context,
    WidgetRef ref, [
    Expense? expense,
  ]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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
}

class _TodayContent extends StatelessWidget {
  const _TodayContent({
    required this.items,
    required this.hidden,
    required this.onOpen,
  });
  final List<Expense> items;
  final bool hidden;
  final ValueChanged<Expense> onOpen;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = items
        .where((e) => e.date.year == now.year && e.date.month == now.month)
        .toList();
    final today = items.where((e) => DateUtils.isSameDay(e.date, now)).toList();
    final spent = month
        .where((e) => !e.isIncome)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final income = month
        .where((e) => e.isIncome)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final todaySpent = today
        .where((e) => !e.isIncome)
        .fold<double>(0, (sum, e) => sum + e.amount);
    final currency = items.first.currency;
    final remaining = income - spent;
    final daysLeft = DateTime(now.year, now.month + 1, 0).day - now.day + 1;
    final dailyRoom = remaining > 0 ? remaining / daysLeft : 0.0;
    String money(double value) =>
        hidden ? maskAmount(currency) : formatAmount(value, currency);

    final latest = items.take(6).toList();
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inverseSurface,
                borderRadius: AppRadius.all(AppRadius.xxl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AVAILABLE THIS MONTH',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onInverseSurface.withValues(alpha: 0.65),
                      letterSpacing: 1.3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      money(remaining),
                      key: ValueKey(hidden),
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onInverseSurface,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: _HeroDatum(label: 'Spent', value: money(spent)),
                      ),
                      Container(
                        width: 1,
                        height: 32,
                        color: Theme.of(
                          context,
                        ).colorScheme.onInverseSurface.withValues(alpha: 0.18),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: _HeroDatum(
                          label: 'Daily room',
                          value: money(dailyRoom),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionLabel('At a glance')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 130,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              children: [
                SizedBox(
                  width: 170,
                  child: MetricTile(
                    label: 'Today',
                    value: money(todaySpent),
                    icon: Icons.today_rounded,
                    caption: '${today.length} movements',
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 170,
                  child: MetricTile(
                    label: 'Money in',
                    value: money(income),
                    icon: Icons.south_west_rounded,
                    color: context.finance.income,
                    caption: 'This month',
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 170,
                  child: MetricTile(
                    label: 'Days left',
                    value: '$daysLeft',
                    icon: Icons.hourglass_bottom_rounded,
                    caption: 'In this cycle',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SectionLabel('Latest activity')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.separated(
            itemCount: latest.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 54,
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            itemBuilder: (context, index) => _LedgerRow(
              expense: latest[index],
              hidden: hidden,
              onTap: () => onOpen(latest[index]),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroDatum extends StatelessWidget {
  const _HeroDatum({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(
            context,
          ).colorScheme.onInverseSurface.withValues(alpha: 0.65),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.fade,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onInverseSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.expense,
    required this.hidden,
    required this.onTap,
  });
  final Expense expense;
  final bool hidden;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final color = expense.isIncome
        ? context.finance.income
        : categoryColor(expense.category);
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.all(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.all(14),
              ),
              child: Icon(
                expense.isIncome
                    ? Icons.south_west_rounded
                    : categoryIcon(expense.category),
                color: color,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${expense.category} · ${DateFormat('h:mm a').format(expense.date)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              hidden
                  ? maskAmount(expense.currency)
                  : '${expense.isIncome ? '+' : '−'}${formatAmount(expense.amount, expense.currency)}',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: expense.isIncome ? context.finance.income : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SyncLine extends StatelessWidget {
  const _SyncLine(this.sync);
  final SyncState sync;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.65),
        borderRadius: AppRadius.all(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sync.phase == SyncPhase.error
                    ? Icons.error_outline_rounded
                    : sync.phase == SyncPhase.complete
                    ? Icons.check_circle_outline_rounded
                    : Icons.bolt_rounded,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sync.errorMessage ?? sync.detail ?? 'Preparing sync',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (sync.total > 0)
                Text(
                  '${(sync.current / sync.total * 100).clamp(0, 100).round()}%',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
            ],
          ),
          if (sync.isActive && sync.total > 0) ...[
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: AppRadius.all(99),
              child: LinearProgressIndicator(
                value: (sync.current / sync.total).clamp(0, 1),
                minHeight: 5,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.syncing,
    required this.onSync,
    required this.onAdd,
  });
  final bool syncing;
  final VoidCallback onSync;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 84),
    child: FloatingActionButton.extended(
      onPressed: syncing
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.bolt_rounded),
                        title: const Text('Sync bank messages'),
                        subtitle: const Text('Import new transactions'),
                        onTap: () {
                          Navigator.pop(context);
                          onSync();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.edit_rounded),
                        title: const Text('Add manually'),
                        subtitle: const Text('Create an expense or income'),
                        onTap: () {
                          Navigator.pop(context);
                          onAdd();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
      icon: syncing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_rounded),
      label: Text(syncing ? 'Syncing' : 'Quick add'),
    ),
  );
}

extension on SyncState {
  bool get isActive =>
      phase == SyncPhase.requestingPermissions ||
      phase == SyncPhase.fetchingSms ||
      phase == SyncPhase.analyzing;
}
