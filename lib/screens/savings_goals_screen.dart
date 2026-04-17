import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/savings_goal.dart';
import '../providers/expense_provider.dart';
import '../utils/currency_utils.dart';

// Preset swatches for goal colour picker
const _kSwatches = [
  0xFF6750A4, // purple
  0xFF0061A4, // blue
  0xFF006E1C, // green
  0xFFBA1A1A, // red
  0xFFE65100, // orange
  0xFFF57F17, // amber
  0xFF00695C, // teal
  0xFF4A148C, // deep-purple
];

class SavingsGoalsScreen extends ConsumerWidget {
  const SavingsGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(savingsGoalsProvider);
    final privateMode = ref.watch(privateModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      body: goalsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (goals) {
          if (goals.isEmpty) {
            return const _EmptyState();
          }
          return CustomScrollView(
            slivers: [
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: _SectionHeader('Your Goals'),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                sliver: SliverList.separated(
                  itemCount: goals.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final goal = goals[index];
                    return _SavingsGoalCard(
                      goal: goal,
                      privateMode: privateMode,
                      onTap: () => _openSheet(context, ref, goal),
                      onDismissed: () => ref
                          .read(savingsGoalsProvider.notifier)
                          .remove(goal.id!),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Goal'),
      ),
    );
  }

  void _openSheet(BuildContext context, WidgetRef ref, SavingsGoal? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _GoalFormSheet(existing: existing),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(fontWeight: FontWeight.w800),
      );
}

class _SavingsGoalCard extends StatelessWidget {
  const _SavingsGoalCard({
    required this.goal,
    required this.privateMode,
    required this.onTap,
    required this.onDismissed,
  });

  final SavingsGoal goal;
  final bool privateMode;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = goal.color;
    final daysLeft = goal.daysLeft;

    return Dismissible(
      key: ValueKey('goal_${goal.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.red),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete goal?'),
            content: Text('Remove "${goal.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onDismissed(),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Progress ring
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          startDegreeOffset: -90,
                          sectionsSpace: 0,
                          centerSpaceRadius: 22,
                          sections: [
                            PieChartSectionData(
                              value: goal.progress,
                              color: goal.isCompleted
                                  ? Colors.green
                                  : color,
                              radius: 10,
                              showTitle: false,
                            ),
                            PieChartSectionData(
                              value: 1 - goal.progress,
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              radius: 10,
                              showTitle: false,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(goal.progress * 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: goal.isCompleted ? Colors.green : color,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              goal.name,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (goal.isCompleted)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Completed',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        privateMode
                            ? '${maskAmount('INR')} of ${maskAmount('INR')}'
                            : '${formatAmount(goal.currentAmount, 'INR')} of ${formatAmount(goal.targetAmount, 'INR')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      if (daysLeft != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          daysLeft < 0
                              ? 'Overdue by ${daysLeft.abs()} days'
                              : daysLeft == 0
                                  ? 'Due today'
                                  : '$daysLeft days left',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: daysLeft < 0
                                ? Colors.red
                                : daysLeft <= 7
                                    ? Colors.amber.shade700
                                    : scheme.onSurface.withValues(alpha: 0.5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalFormSheet extends ConsumerStatefulWidget {
  const _GoalFormSheet({this.existing});
  final SavingsGoal? existing;

  @override
  ConsumerState<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends ConsumerState<_GoalFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _targetCtrl;
  late TextEditingController _currentCtrl;
  DateTime? _deadline;
  late int _colorValue;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _targetCtrl = TextEditingController(
        text: g != null ? g.targetAmount.toStringAsFixed(2) : '');
    _currentCtrl = TextEditingController(
        text: g != null ? g.currentAmount.toStringAsFixed(2) : '0.00');
    _deadline = g?.deadline;
    _colorValue = g?.colorValue ?? _kSwatches.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _currentCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final goal = SavingsGoal(
      id: widget.existing?.id,
      name: _nameCtrl.text.trim(),
      targetAmount: double.parse(_targetCtrl.text.trim()),
      currentAmount: double.parse(_currentCtrl.text.trim()),
      deadline: _deadline,
      colorValue: _colorValue,
    );

    await ref.read(savingsGoalsProvider.notifier).upsert(goal);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isEditing ? 'Edit Goal' : 'New Goal',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              // Name
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Goal name',
                  prefixIcon: const Icon(Icons.flag_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              // Target + current amounts
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _targetCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Target (₹)',
                        prefixIcon:
                            const Icon(Icons.flag_circle_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (v) {
                        final amt = double.tryParse(v?.trim() ?? '');
                        if (amt == null || amt <= 0) {
                          return 'Enter target';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _currentCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Saved so far (₹)',
                        prefixIcon:
                            const Icon(Icons.savings_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                      ),
                      validator: (v) {
                        if (double.tryParse(v?.trim() ?? '') == null) {
                          return 'Enter amount';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Deadline picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_rounded),
                title: Text(
                  _deadline == null
                      ? 'No deadline'
                      : '${_deadline!.day}/${_deadline!.month}/${_deadline!.year}',
                  style: theme.textTheme.bodyMedium,
                ),
                subtitle: const Text('Target date (optional)'),
                trailing: _deadline != null
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        tooltip: 'Remove deadline',
                        onPressed: () => setState(() => _deadline = null),
                      )
                    : null,
                onTap: _pickDeadline,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
                ),
              ),
              const SizedBox(height: 16),
              // Colour swatches
              Text(
                'Colour',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: _kSwatches.map((c) {
                  final selected = c == _colorValue;
                  return GestureDetector(
                    onTap: () => setState(() => _colorValue = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: selected
                              ? scheme.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: Color(c).withValues(alpha: 0.4),
                                  blurRadius: 6,
                                )
                              ]
                            : null,
                      ),
                      child: selected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(isEditing ? 'Update Goal' : 'Save Goal'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.savings_rounded, size: 40, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'No goals yet.',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to set a savings target.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
