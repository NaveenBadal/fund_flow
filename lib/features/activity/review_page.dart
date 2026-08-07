import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../../domain/transaction.dart';
import '../common/formatting.dart';
import 'category_sheet.dart';
import 'transaction_editor.dart';

/// The review queue, as a card stack.
///
/// This is the screen the app was missing. Every extraction the model was unsure
/// about was already marked `needsReview` and stored, and nothing in the
/// interface ever showed it — so low-confidence records quietly sat in totals
/// nobody had checked.
///
/// A stack rather than a list, because the job is repetitive and per-item: one
/// transaction, its original message, and two ways out. Clearing forty of them
/// should be forty taps in the same place, not forty round trips into a detail
/// page.
class ReviewPage extends ConsumerWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final queue = ref.watch(reviewQueueProvider);
    final money = ref.watch(moneyProvider);
    final controller = ref.read(appControllerProvider.notifier);

    if (queue.isEmpty) {
      return FluxDetailPage(
        title: 'Review',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: FluxEmpty(
              icon: Icons.task_alt_rounded,
              title: 'Nothing to review',
              message:
                  'Every transaction has either been read confidently or '
                  'checked by you.',
              actionLabel: 'Back to Home',
              onAction: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      );
    }

    final current = queue.first;
    final incoming = current.direction == TransactionDirection.incoming;

    return FluxDetailPage(
      title: '${queue.length} to review',
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Oldest first. Each one was read from a message the model was '
                'not confident about.',
                style: FluxType.body.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: FluxSpace.x5),
              // Keyed on the id so the card animates in as a new card rather
              // than mutating the old one in place.
              _ReviewCard(
                key: ValueKey('review-${current.id}'),
                transaction: current,
                money: money,
              ),
              const SizedBox(height: FluxSpace.x5),
              Row(
                children: [
                  Expanded(
                    child: FluxButton(
                      label: incoming ? 'Income is right' : 'Looks right',
                      icon: Icons.check_rounded,
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        await controller.confirmTransaction(current);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluxSpace.x3),
              Row(
                children: [
                  Expanded(
                    child: FluxButton(
                      label: 'Change category',
                      kind: FluxButtonKind.secondary,
                      onPressed: () async {
                        final chosen = await showCategorySheet(
                          context: context,
                          direction: current.direction,
                          selected: current.category,
                        );
                        if (chosen == null) return;
                        await controller.saveTransaction(
                          current.copyWith(
                            category: chosen,
                            reviewState: ReviewState.confirmed,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: FluxSpace.x3),
                  Expanded(
                    child: FluxButton(
                      label: 'Edit',
                      kind: FluxButtonKind.secondary,
                      onPressed: () => showTransactionEditor(
                        context: context,
                        ref: ref,
                        existing: current,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FluxSpace.x3),
              FluxButton(
                // Danger rather than ghost: a ghost button is iris, which is
                // the app's "this is the safe primary action" colour, and this
                // one deletes a record.
                label: 'Not a transaction — delete',
                kind: FluxButtonKind.danger,
                onPressed: () async {
                  final confirmed = await fluxConfirm(
                    context: context,
                    title: 'Not a transaction?',
                    message:
                        'Deleting removes it from every total. Use this when '
                        'the message was not about money at all.',
                  );
                  if (confirmed) {
                    await controller.deleteTransaction(current.id!);
                  }
                },
              ),
              const SizedBox(height: FluxSpace.x6),
              if (queue.length > 1)
                Text(
                  '${queue.length - 1} more after this one.',
                  textAlign: TextAlign.center,
                  style: FluxType.caption.copyWith(color: palette.textFaint),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    super.key,
    required this.transaction,
    required this.money,
  });

  final MoneyTransaction transaction;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final incoming = transaction.direction == TransactionDirection.incoming;

    return _CardEntrance(
      child: FluxCard(
        padding: const EdgeInsets.all(FluxSpace.x5),
        border: palette.attention.withValues(alpha: 0.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FluxAvatar(
                  name: transaction.merchant,
                  tint: palette.forCategory(transaction.category),
                  size: 36,
                ),
                const SizedBox(width: FluxSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.merchant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FluxType.subtitle.copyWith(color: palette.text),
                      ),
                      Text(
                        '${transaction.category} · '
                        '${dayLabel(transaction.occurredAt)}',
                        style: FluxType.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FluxSpace.x5),
            MoneyText(
              money.exact(transaction.amountMinor, transaction.currency),
              incoming: incoming,
              signed: true,
              style: FluxType.moneyLarge,
            ),
            const SizedBox(height: FluxSpace.x2),
            Row(
              children: [
                Icon(Icons.rule_rounded, size: 13, color: palette.attention),
                const SizedBox(width: 5),
                Text(
                  'Read at ${(transaction.confidence * 100).round()}% '
                  'confidence',
                  style: FluxType.caption.copyWith(color: palette.attention),
                ),
              ],
            ),
            if (transaction.sourceText != null) ...[
              const SizedBox(height: FluxSpace.x5),
              Container(
                width: double.infinity,
                decoration: ShapeDecoration(
                  color: palette.isDark
                      ? palette.background
                      : palette.surfaceHighest,
                  shape: FluxRadius.shape(FluxRadius.sm),
                ),
                padding: const EdgeInsets.all(FluxSpace.x4),
                child: Text(
                  transaction.sourceText!,
                  style: FluxType.caption.copyWith(
                    color: palette.textMuted,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Slides each new card up as the previous one is cleared.
///
/// The motion is what turns a queue into progress: without it, confirming an
/// item silently swaps the contents of a static box and the screen looks stuck.
class _CardEntrance extends StatefulWidget {
  const _CardEntrance({required this.child});

  final Widget child;

  @override
  State<_CardEntrance> createState() => _CardEntranceState();
}

class _CardEntranceState extends State<_CardEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: FluxMotion.normal,
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (FluxMotion.reduced(context)) return widget.child;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: FluxMotion.overshoot,
    );
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _controller,
        curve: FluxMotion.emphasized,
      ),
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(curved),
        child: widget.child,
      ),
    );
  }
}
