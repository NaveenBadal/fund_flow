import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/money_format.dart';
import '../../domain/transaction.dart';
import '../ff_format.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_group.dart';
import '../widgets/ff_money.dart';
import '../widgets/ff_screen.dart';
import '../widgets/ff_sheet.dart';
import '../widgets/ff_transaction_row.dart';
import 'ask.dart';
import 'transaction_editor.dart';

void openTransaction(BuildContext context, MoneyTransaction item) {
  if (item.id == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => TransactionScreen(id: item.id!)),
  );
}

/// One transaction, and everything the app knows about why it exists.
///
/// The original message is shown rather than summarised. A record captured
/// automatically is only trustworthy if the evidence behind it can be read.
class TransactionScreen extends ConsumerWidget {
  const TransactionScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final item = app.transactions.where((t) => t.id == id).firstOrNull;
    final c = context.ff;

    if (item == null) {
      return const FFScreen(
        title: 'Transaction',
        large: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('This transaction no longer exists.')),
          ),
        ],
      );
    }

    final incoming = item.direction == TransactionDirection.incoming;
    final review = item.reviewState == ReviewState.needsReview;

    return FFScreen(
      title: readableMerchant(item.merchant),
      large: false,
      backLabel: 'Back',
      trailing: [
        FFBarButton(
          label: 'Edit',
          onTap: () => showTransactionEditor(context, transaction: item),
        ),
      ],
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
                FFCategoryGlyph(category: item.category, size: 56),
                const SizedBox(height: FFSpace.lg),
                FFMoney(
                  minor: incoming ? item.amountMinor : -item.amountMinor,
                  currency: item.currency,
                  hidden: app.preferences.hideAmounts,
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
                  DateFormat('EEEE d MMMM yyyy · h:mm a').format(
                    item.occurredAt,
                  ),
                  style: FFText.footnote.copyWith(color: c.secondaryLabel),
                ),
              ],
            ),
          ),
        ),
        if (review)
          SliverToBoxAdapter(
            child: FFGroup(
              children: [
                FFRow(
                  title: 'Confirm this transaction',
                  subtitle: 'It was read from a message and not yet checked',
                  icon: Icons.check_rounded,
                  iconColor: c.greenFill,
                  tinted: true,
                  chevron: false,
                  onTap: () => ref
                      .read(appControllerProvider.notifier)
                      .confirmTransaction(
                        item.copyWith(reviewState: ReviewState.confirmed),
                      ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: FFGroup(
            children: [
              FFRow(
                title: 'Category',
                value: item.category,
                chevron: false,
              ),
              FFRow(
                title: 'Direction',
                value: incoming ? 'Money in' : 'Money out',
                chevron: false,
              ),
              if ((item.account ?? '').isNotEmpty)
                FFRow(
                  title: 'Account',
                  value: item.account!,
                  chevron: false,
                ),
              FFRow(
                title: 'Captured from',
                value: sourceLabel(item.source),
                chevron: false,
              ),
              if ((item.note ?? '').trim().isNotEmpty)
                FFRow(
                  title: 'Note',
                  subtitle: item.note!.trim(),
                  chevron: false,
                ),
            ],
          ),
        ),
        if ((item.sourceText ?? '').trim().isNotEmpty)
          SliverToBoxAdapter(
            child: FFGroup(
              header: 'Original message',
              footer: item.confidence >= .9
                  ? 'Read with high confidence.'
                  : 'Read with lower confidence — worth a glance.',
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
          child: FFGroup(
            children: [
              FFRow(
                title: 'Ask about this',
                icon: Icons.auto_awesome_rounded,
                iconColor: c.tint,
                onTap: () => openAsk(
                  context,
                  ref,
                  seed:
                      'Tell me about the ${item.merchant} transaction for '
                      '${formatMoney(item.amountMinor, item.currency)}.',
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            children: [
              FFRow(
                title: 'Delete transaction',
                destructive: true,
                centered: true,
                chevron: false,
                onTap: () async {
                  final approved = await ffConfirm(
                    context,
                    title: 'Delete this transaction?',
                    message:
                        'It will be removed from totals, analysis and answers. '
                        'This cannot be undone.',
                    confirm: 'Delete',
                  );
                  if (!approved || !context.mounted) return;
                  await ref
                      .read(appControllerProvider.notifier)
                      .deleteTransaction(id);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
