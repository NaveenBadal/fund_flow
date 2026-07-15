import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/action_item.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/expense_form_sheet.dart';
import '../widgets/ui/command_ui.dart';
import 'budget_screen.dart';
import 'plan_screen.dart';
import 'subscriptions_screen.dart';

enum _InboxFilter { all, urgent, imports, planning }

class ActionInboxButton extends ConsumerWidget {
  const ActionInboxButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(actionInboxProvider).asData?.value.length ?? 0;
    return IconButton(
      tooltip: 'Action inbox',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const ActionInboxScreen()),
      ),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 9 ? '9+' : '$count'),
        child: const Icon(Icons.inbox_outlined),
      ),
    );
  }
}

class ActionInboxScreen extends ConsumerStatefulWidget {
  const ActionInboxScreen({super.key});

  @override
  ConsumerState<ActionInboxScreen> createState() => _ActionInboxScreenState();
}

class _ActionInboxScreenState extends ConsumerState<ActionInboxScreen> {
  _InboxFilter _filter = _InboxFilter.all;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(actionInboxProvider);
    return CommandScaffold(
      eyebrow: 'Only decisions that change the outcome',
      title: 'Interventions',
      slivers: [
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.inbox_outlined,
              title: 'Inbox unavailable',
              message: '$error',
              action: FilledButton(
                onPressed: () => ref.invalidate(actionInboxProvider),
                child: const Text('Try again'),
              ),
            ),
          ),
          data: (all) {
            final urgent = all
                .where((item) => item.priority == ActionItemPriority.urgent)
                .length;
            final items = all.where(_matchesFilter).toList();
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: _InboxSummary(total: all.length, urgent: urgent),
                ),
                SliverToBoxAdapter(child: _filters()),
                if (items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: StatePanel(
                      icon: all.isEmpty
                          ? Icons.task_alt_rounded
                          : Icons.filter_alt_off_rounded,
                      title: all.isEmpty
                          ? 'You are all caught up'
                          : 'No matches',
                      message: all.isEmpty
                          ? 'Nothing needs a decision right now. Fund Flow will keep watching quietly.'
                          : 'There are no actions in this filter.',
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    sliver: SliverList.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _ActionCard(
                        item: items[index],
                        onAction: () => _perform(items[index]),
                        onDismiss: () => _dismiss(items[index]),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _filters() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
    child: SegmentedButton<_InboxFilter>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _InboxFilter.all, label: Text('All')),
        ButtonSegment(value: _InboxFilter.urgent, label: Text('Urgent')),
        ButtonSegment(value: _InboxFilter.imports, label: Text('Imports')),
        ButtonSegment(value: _InboxFilter.planning, label: Text('Planning')),
      ],
      selected: {_filter},
      onSelectionChanged: (value) => setState(() => _filter = value.first),
    ),
  );

  bool _matchesFilter(ActionItem item) => switch (_filter) {
    _InboxFilter.all => true,
    _InboxFilter.urgent => item.priority == ActionItemPriority.urgent,
    _InboxFilter.imports => item.kind == ActionItemKind.importIssue,
    _InboxFilter.planning =>
      item.kind == ActionItemKind.budget ||
          item.kind == ActionItemKind.commitment ||
          item.kind == ActionItemKind.planning,
  };

  Future<void> _perform(ActionItem item) async {
    switch (item.kind) {
      case ActionItemKind.importIssue:
        final body = item.smsBody;
        if (body == null) return;
        await ref.read(databaseProvider).unmarkSmsParsed([body]);
        ref.invalidate(parsedSmsAuditProvider);
        ref.invalidate(actionInboxProvider);
        await ref.read(syncProvider.notifier).sync();
        return;
      case ActionItemKind.anomaly:
        final expenses = ref.read(expenseListProvider).asData?.value ?? [];
        final expense = expenses
            .where((e) => e.id == item.expenseId)
            .firstOrNull;
        if (expense != null && mounted) await _edit(expense);
        return;
      case ActionItemKind.budget:
        await _push(const BudgetScreen());
        return;
      case ActionItemKind.commitment:
        await _push(const SubscriptionsScreen());
        return;
      case ActionItemKind.planning:
        await _push(const PlanScreen());
        return;
    }
  }

  Future<void> _edit(Expense expense) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
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

  Future<void> _dismiss(ActionItem item) async {
    await ref.read(actionDismissalsProvider.notifier).dismiss(item.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Removed from your inbox.'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(actionDismissalsProvider.notifier).restore(item.key),
        ),
      ),
    );
  }

  Future<void> _push(Widget page) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => page),
    );
  }
}

class _InboxSummary extends StatelessWidget {
  const _InboxSummary({required this.total, required this.urgent});
  final int total;
  final int urgent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: AppRadius.all(AppRadius.xxl),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total == 0
                        ? 'CLEAR FOR NOW'
                        : '$total DECISION${total == 1 ? '' : 'S'}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onInverseSurface.withValues(alpha: .62),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    total == 0
                        ? 'Nothing needs you'
                        : urgent == 0
                        ? 'No urgent actions'
                        : '$urgent worth doing now',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              total == 0 ? Icons.done_all_rounded : Icons.inbox_rounded,
              color: scheme.primary,
              size: 42,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.item,
    required this.onAction,
    required this.onDismiss,
  });

  final ActionItem item;
  final VoidCallback onAction;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (item.priority) {
      ActionItemPriority.urgent => context.finance.expense,
      ActionItemPriority.important => context.finance.warning,
      ActionItemPriority.upcoming => scheme.primary,
    };
    final icon = switch (item.kind) {
      ActionItemKind.importIssue => Icons.sms_failed_outlined,
      ActionItemKind.anomaly => Icons.manage_search_rounded,
      ActionItemKind.budget => Icons.speed_rounded,
      ActionItemKind.commitment => Icons.event_rounded,
      ActionItemKind.planning => Icons.account_balance_wallet_outlined,
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppRadius.all(AppRadius.lg),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: AppRadius.all(13),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.body,
                      maxLines: item.kind == ActionItemKind.importIssue ? 3 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(item.actionLabel),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: onDismiss, child: const Text('Not now')),
            ],
          ),
        ],
      ),
    );
  }
}
