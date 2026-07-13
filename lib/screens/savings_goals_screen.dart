import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/savings_goal.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';

class SavingsGoalsScreen extends ConsumerWidget {
  const SavingsGoalsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savingsGoalsProvider);
    final hidden = ref.watch(privateModeProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New goal'),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Savings goals')),
          async.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: StatePanel(
                icon: Icons.flag_outlined,
                title: 'Goals unavailable',
                message: '$error',
              ),
            ),
            data: (goals) {
              if (goals.isEmpty) {
                return const SliverFillRemaining(
                  hasScrollBody: false,
                  child: StatePanel(
                    icon: Icons.flag_rounded,
                    title: 'Make the future concrete',
                    message:
                        'Create a target, fund it over time, and see exactly how close you are.',
                  ),
                );
              }
              final target = goals.fold<double>(
                0,
                (sum, goal) => sum + goal.targetAmount,
              );
              final saved = goals.fold<double>(
                0,
                (sum, goal) => sum + goal.currentAmount,
              );
              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: AppRadius.all(AppRadius.xxl),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FUNDED ACROSS ALL GOALS',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.2,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hidden
                                  ? maskAmount('INR')
                                  : formatAmount(saved, 'INR'),
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: AppRadius.all(99),
                              child: LinearProgressIndicator(
                                value: target == 0 ? 0 : saved / target,
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${(target == 0 ? 0 : saved / target * 100).round()}% of ${formatAmount(target, 'INR')}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SectionLabel('Your targets')),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    sliver: SliverList.separated(
                      itemCount: goals.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _GoalRow(
                        goal: goals[index],
                        hidden: hidden,
                        onTap: () => _open(context, goals[index]),
                        onDelete: goals[index].id == null
                            ? null
                            : () => ref
                                  .read(savingsGoalsProvider.notifier)
                                  .remove(goals[index].id!),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, [SavingsGoal? goal]) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _GoalSheet(goal: goal),
      );
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.goal,
    required this.hidden,
    required this.onTap,
    this.onDelete,
  });
  final SavingsGoal goal;
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final color = goal.color;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.all(AppRadius.lg),
      child: InkWell(
        borderRadius: AppRadius.all(AppRadius.lg),
        onTap: onTap,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .13),
                      borderRadius: AppRadius.all(14),
                    ),
                    child: Icon(
                      goal.isCompleted
                          ? Icons.check_rounded
                          : Icons.flag_rounded,
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
                          goal.name,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (goal.deadline != null)
                          Text(
                            '${goal.daysLeft != null && goal.daysLeft! >= 0 ? '${goal.daysLeft} days left' : 'Deadline passed'} · ${DateFormat('d MMM y').format(goal.deadline!)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    hidden
                        ? maskAmount('INR')
                        : formatAmount(goal.currentAmount, 'INR'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: AppRadius.all(99),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 8,
                  color: color,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Text(
                    '${(goal.progress * 100).round()}% funded',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  Text(
                    'Target ${formatAmount(goal.targetAmount, 'INR')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({this.goal});
  final SavingsGoal? goal;
  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  late final TextEditingController _name, _target, _saved;
  DateTime? _deadline;
  late int _color;
  bool _saving = false;
  static const _colors = [
    0xFF4E7100,
    0xFF16845B,
    0xFF4267D5,
    0xFFD95745,
    0xFF9A6800,
    0xFF7955B7,
  ];
  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _name = TextEditingController(text: g?.name ?? '');
    _target = TextEditingController(
      text: g == null ? '' : g.targetAmount.toStringAsFixed(0),
    );
    _saved = TextEditingController(
      text: g == null ? '' : g.currentAmount.toStringAsFixed(0),
    );
    _deadline = g?.deadline;
    _color = g?.colorValue ?? _colors.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 28,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.goal == null ? 'New savings goal' : 'Edit goal',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Goal name',
              prefixIcon: Icon(Icons.flag_outlined),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MoneyField(controller: _target, label: 'Target'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MoneyField(controller: _saved, label: 'Already saved'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(
              _deadline == null
                  ? 'No deadline'
                  : DateFormat('d MMMM yyyy').format(_deadline!),
            ),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _pickDate,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            children: [
              for (final value in _colors)
                GestureDetector(
                  onTap: () => setState(() => _color = value),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: value == _color
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save goal'),
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (date != null) setState(() => _deadline = date);
  }

  Future<void> _save() async {
    final target = double.tryParse(_target.text);
    final saved = double.tryParse(_saved.text) ?? 0;
    if (_name.text.trim().isEmpty || target == null || target <= 0) return;
    setState(() => _saving = true);
    await ref
        .read(savingsGoalsProvider.notifier)
        .upsert(
          SavingsGoal(
            id: widget.goal?.id,
            name: _name.text.trim(),
            targetAmount: target,
            currentAmount: saved,
            deadline: _deadline,
            colorValue: _color,
          ),
        );
    if (mounted) Navigator.pop(context);
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
    ],
    decoration: InputDecoration(labelText: label, prefixText: '₹ '),
  );
}
