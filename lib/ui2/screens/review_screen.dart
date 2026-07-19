import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../../ui/format/money_format.dart';
import '../flow_categories.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';
import '../tokens/flow_type.dart';

/// Clearing the backlog.
///
/// The app reads messages so nobody has to type, and the cost of that is a
/// queue of things a machine was unsure about. Previously there was no way
/// through it: correcting one meant opening a form sheet with four fields,
/// which nobody will do three hundred times.
///
/// This is built for volume. One card at a time, the source message shown
/// beside what was read from it, and confirming is a single tap that never
/// opens a keyboard. Correcting a category is one more tap, because the
/// category is what a machine gets wrong most often and the amount is
/// already checked against the message text before it ever gets here.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Ids deliberately passed over, kept for this session only so skipping
  /// moves forward without permanently hiding anything.
  final _skipped = <int>{};
  int _clearedThisSession = 0;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final flow = context.flow;
    final pending = app.transactions
        .where(
          (item) =>
              item.reviewState == ReviewState.needsReview &&
              !_skipped.contains(item.id),
        )
        .toList();

    if (pending.isEmpty) {
      return _AllClear(
        cleared: _clearedThisSession,
        skipped: _skipped.length,
        onBringBackSkipped: _skipped.isEmpty
            ? null
            : () => setState(_skipped.clear),
      );
    }

    final total = app.transactions
        .where((item) => item.reviewState == ReviewState.needsReview)
        .length;
    final current = pending.first;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FlowSpace.xl,
            FlowSpace.lg,
            FlowSpace.xl,
            FlowSpace.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 1 ? '1 left' : '$total left',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                    ),
                  ],
                ),
              ),
              if (_clearedThisSession > 0)
                Text(
                  '$_clearedThisSession done',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: flow.income),
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: FlowSpace.xl),
            child: _ReviewCard(
              key: ValueKey(current.id),
              item: current,
              onCategory: (value) => _recategorise(current, value),
            ),
          ),
        ),
        _Actions(
          onSkip: () => setState(() => _skipped.add(current.id ?? -1)),
          onConfirm: () => _confirm(current),
        ),
      ],
    );
  }

  Future<void> _confirm(MoneyTransaction item) async {
    // Haptic rather than a toast: at this volume a confirmation that has to
    // be read would slow the loop it is meant to reward.
    unawaited(HapticFeedback.lightImpact());
    setState(() => _clearedThisSession++);
    await ref.read(appControllerProvider.notifier).confirmTransaction(item);
  }

  Future<void> _recategorise(MoneyTransaction item, String category) async {
    unawaited(HapticFeedback.selectionClick());
    setState(() => _clearedThisSession++);
    await ref
        .read(appControllerProvider.notifier)
        .saveTransaction(
          item.copyWith(
            category: category,
            reviewState: ReviewState.confirmed,
            confidence: 1,
          ),
        );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({super.key, required this.item, required this.onCategory});

  final MoneyTransaction item;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final incoming = item.direction == TransactionDirection.incoming;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(FlowSpace.lg),
          decoration: BoxDecoration(
            color: flow.raised,
            borderRadius: FlowRadius.md,
            border: Border.all(color: flow.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                incoming ? 'Money in' : 'Money out',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: flow.inkSoft),
              ),
              const SizedBox(height: FlowSpace.xs),
              Text(
                '${incoming ? '+' : '−'}'
                '${formatMoney(item.amountMinor, item.currency)}',
                style: FlowType.amountHero.copyWith(
                  color: incoming ? flow.income : flow.ink,
                ),
              ),
              const SizedBox(height: FlowSpace.sm),
              Text(
                item.merchant,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                _when(item.occurredAt),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
              ),
            ],
          ),
        ),

        // The source is shown, not hidden behind a disclosure. This screen
        // asks someone to vouch for a machine's reading, which they cannot do
        // without seeing what it read.
        if ((item.sourceText ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: FlowSpace.md),
          Text(
            'Read from this message',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: flow.inkSoft),
          ),
          const SizedBox(height: FlowSpace.xs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(FlowSpace.md),
            decoration: BoxDecoration(
              color: flow.sunken,
              borderRadius: FlowRadius.sm,
            ),
            child: Text(
              item.sourceText!.trim(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: flow.inkSoft,
                height: 1.45,
              ),
            ),
          ),
        ],

        const SizedBox(height: FlowSpace.lg),
        Text(
          'Category',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: flow.inkSoft),
        ),
        const SizedBox(height: FlowSpace.sm),
        Wrap(
          spacing: FlowSpace.sm,
          runSpacing: FlowSpace.sm,
          children: [
            // Offered inline so the common correction never opens a keyboard.
            for (final category in kFlowCategories)
              _CategoryChip(
                label: category,
                selected: category.toLowerCase() == item.category.toLowerCase(),
                onTap: () => onCategory(category),
              ),
          ],
        ),
        const SizedBox(height: FlowSpace.lg),
      ],
    );
  }

  static String _when(DateTime value) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.day} ${months[value.month - 1]} · ${value.hour}:$minute';
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
      label: selected ? '$label, current category' : 'Set category to $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpace.md,
            vertical: FlowSpace.sm,
          ),
          // No alignment: setting one makes the container expand to its
          // constraints, which stretched every chip to full width and stacked
          // them one per row instead of wrapping.
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

class _Actions extends StatelessWidget {
  const _Actions({required this.onSkip, required this.onConfirm});
  final VoidCallback onSkip;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FlowSpace.xl,
        FlowSpace.sm,
        FlowSpace.xl,
        FlowSpace.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onSkip,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(FlowDensity.minimumTarget),
                side: BorderSide(color: flow.line),
                foregroundColor: flow.inkSoft,
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadius.sm,
                ),
              ),
              child: const Text('Skip'),
            ),
          ),
          const SizedBox(width: FlowSpace.md),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: onConfirm,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(FlowDensity.minimumTarget),
                backgroundColor: flow.accent,
                foregroundColor: flow.onAccent,
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadius.sm,
                ),
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Looks right'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AllClear extends StatelessWidget {
  const _AllClear({
    required this.cleared,
    required this.skipped,
    this.onBringBackSkipped,
  });

  final int cleared;
  final int skipped;
  final VoidCallback? onBringBackSkipped;

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
            Icon(Icons.task_alt_rounded, size: 30, color: flow.income),
            const SizedBox(height: FlowSpace.lg),
            Text(
              skipped > 0 ? 'Nothing left to look at' : 'All caught up',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: FlowSpace.sm),
            Text(
              cleared > 0
                  ? 'You cleared $cleared this session. New captures appear '
                        'here only when the AI is unsure.'
                  : 'Everything captured so far has been confirmed. New '
                        'captures appear here only when the AI is unsure.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: flow.inkSoft),
            ),
            if (onBringBackSkipped != null) ...[
              const SizedBox(height: FlowSpace.lg),
              TextButton(
                onPressed: onBringBackSkipped,
                child: Text(
                  skipped == 1
                      ? 'Bring back 1 skipped'
                      : 'Bring back $skipped skipped',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
