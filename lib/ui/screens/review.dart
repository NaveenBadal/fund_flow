import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../ff_format.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_controls.dart';
import '../widgets/ff_group.dart';
import '../widgets/ff_money.dart';
import '../widgets/ff_notice.dart';
import '../widgets/ff_screen.dart';
import '../widgets/ff_transaction_row.dart';
import 'transaction_editor.dart';

/// Confirming what was read automatically.
///
/// One at a time, with the message it came from in view. A queue shown as a
/// list invites bulk-approving things nobody looked at, which defeats the only
/// reason the queue exists.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _skipped = <int?>{};

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final c = context.ff;
    final pending = app.transactions
        .where(
          (t) =>
              t.reviewState == ReviewState.needsReview &&
              !_skipped.contains(t.id),
        )
        .toList();

    if (pending.isEmpty) {
      return FFScreen(
        title: 'Review',
        large: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: FFEmpty(
                icon: Icons.check_circle_rounded,
                title: _skipped.isEmpty ? 'Nothing to review' : 'All caught up',
                message: 'Everything captured has been confirmed.',
                action: 'Done',
                onAction: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      );
    }

    final item = pending.first;
    final done = _skipped.length;
    final incoming = item.direction == TransactionDirection.incoming;

    return FFScreen(
      title: 'Review',
      large: false,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              FFSpace.sm,
              FFSpace.gutter,
              FFSpace.xl,
            ),
            child: Column(
              children: [
                Text(
                  '${pending.length} left${done == 0 ? '' : ' · $done skipped'}',
                  style: FFText.footnote.copyWith(color: c.secondaryLabel),
                ),
                const SizedBox(height: FFSpace.xl),
                FFCategoryGlyph(category: item.category, size: 56),
                const SizedBox(height: FFSpace.lg),
                FFMoney(
                  minor: incoming ? item.amountMinor : -item.amountMinor,
                  currency: item.currency,
                  signed: true,
                  style: FFText.money,
                  color: incoming ? c.green : c.label,
                ),
                const SizedBox(height: 6),
                Text(
                  readableMerchant(item.merchant),
                  textAlign: TextAlign.center,
                  style: FFText.title3,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('d MMMM · h:mm a').format(item.occurredAt),
                  style: FFText.footnote.copyWith(color: c.secondaryLabel),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            children: [
              FFRow(title: 'Category', value: item.category, chevron: false),
              FFRow(
                title: 'Direction',
                value: incoming ? 'Money in' : 'Money out',
                chevron: false,
              ),
              if ((item.account ?? '').isNotEmpty)
                FFRow(title: 'Account', value: item.account!, chevron: false),
            ],
          ),
        ),
        if ((item.sourceText ?? '').trim().isNotEmpty)
          SliverToBoxAdapter(
            child: FFGroup(
              header: 'Read from this message',
              children: [
                Padding(
                  padding: const EdgeInsets.all(FFSpace.lg),
                  child: SelectableText(
                    item.sourceText!.trim(),
                    style: FFText.footnote.copyWith(color: c.secondaryLabel),
                  ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FFSpace.gutter),
            child: Column(
              children: [
                FFButton(
                  'Looks right',
                  icon: Icons.check_rounded,
                  onTap: () => ref
                      .read(appControllerProvider.notifier)
                      .confirmTransaction(
                        item.copyWith(reviewState: ReviewState.confirmed),
                      ),
                ),
                const SizedBox(height: FFSpace.sm),
                FFButton(
                  'Correct the details',
                  style: FFButtonStyle.tinted,
                  onTap: () =>
                      showTransactionEditor(context, transaction: item),
                ),
                const SizedBox(height: FFSpace.xs),
                FFButton(
                  'Skip for now',
                  style: FFButtonStyle.plain,
                  onTap: () => setState(() => _skipped.add(item.id)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
