import 'package:flutter/material.dart' show Icons, SelectableText;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/transaction.dart';
import '../common/formatting.dart';
import '../shell/shell.dart';
import 'category_sheet.dart';
import 'merchant_page.dart';
import 'transaction_editor.dart';

/// One transaction, in full, including the message it came out of.
///
/// The evidence block is the reason this page exists. Everything in this app is
/// inferred by a language model from an SMS, and the only way that is
/// trustworthy is if the original text is always one tap away with the parsed
/// values visibly highlighted inside it.
class TransactionPage extends ConsumerWidget {
  const TransactionPage({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final money = ref.watch(moneyProvider);
    final transaction = app?.transactions
        .where((item) => item.id == id)
        .firstOrNull;

    if (transaction == null) {
      return const FluxDetailPage(
        title: 'Transaction',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: FluxEmpty(
              icon: Icons.search_off_rounded,
              title: 'This transaction is gone',
              message: 'It was deleted, or an undo removed it.',
            ),
          ),
        ],
      );
    }

    final incoming = transaction.direction == TransactionDirection.incoming;
    final needsReview = transaction.reviewState == ReviewState.needsReview;
    final controller = ref.read(appControllerProvider.notifier);

    return FluxDetailPage(
      title: transaction.merchant,
      actions: [
        FluxIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Edit',
          onPressed: () => showTransactionEditor(
            context: context,
            ref: ref,
            existing: transaction,
          ),
        ),
      ],
      bottomBar: needsReview
          ? Row(
              children: [
                Expanded(
                  child: FluxButton(
                    label: 'Looks right',
                    icon: Icons.check_rounded,
                    onPressed: () async {
                      await controller.confirmTransaction(transaction);
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                ),
                const SizedBox(width: FluxSpace.x3),
                Expanded(
                  child: FluxButton(
                    label: 'Fix it',
                    kind: FluxButtonKind.secondary,
                    onPressed: () => showTransactionEditor(
                      context: context,
                      ref: ref,
                      existing: transaction,
                    ),
                  ),
                ),
              ],
            )
          : null,
      slivers: [
        FluxSliverPadding(
          top: FluxSpace.x4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (needsReview) ...[
                _ReviewNote(confidence: transaction.confidence),
                const SizedBox(height: FluxSpace.x4),
              ],
              Text(
                incoming ? 'Money in' : 'Money out',
                style: FluxType.overline.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: FluxSpace.x2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  // Always exact here: masking the figure on the page where
                  // someone checks or corrects it defeats the purpose of both.
                  money.exact(transaction.amountMinor, transaction.currency),
                  incoming: incoming,
                  signed: true,
                  style: FluxType.moneyHero.copyWith(fontSize: 42),
                ),
              ),
              const SizedBox(height: FluxSpace.x2),
              Text(
                '${dayLabel(transaction.occurredAt)} at '
                '${timeLabel(transaction.occurredAt)}',
                style: FluxType.body.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: FluxSpace.x5),
              Wrap(
                spacing: FluxSpace.x2,
                runSpacing: FluxSpace.x2,
                children: [
                  FluxChip(
                    label: transaction.category,
                    selected: true,
                    tint: palette.forCategory(transaction.category),
                    trailingIcon: Icons.expand_more_rounded,
                    onTap: () async {
                      final chosen = await showCategorySheet(
                        context: context,
                        direction: transaction.direction,
                        selected: transaction.category,
                      );
                      if (chosen != null) {
                        await controller.saveTransaction(
                          transaction.copyWith(category: chosen),
                        );
                      }
                    },
                  ),
                  FluxChip(
                    label: 'All ${transaction.merchant}',
                    icon: Icons.storefront_outlined,
                    onTap: () => fluxPush(
                      context,
                      (context) => MerchantPage(merchant: transaction.merchant),
                    ),
                  ),
                  FluxChip(
                    label: 'Ask about this',
                    icon: Icons.auto_awesome_rounded,
                    onTap: () => openAsk(
                      context,
                      ref,
                      seed:
                          'Tell me about the ${transaction.merchant} charge on '
                          '${shortDay(transaction.occurredAt)}.',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FluxGroup(
            header: 'Details',
            children: [
              FluxRow(
                title: 'Account',
                value: transaction.account ?? 'Not stated in the message',
              ),
              FluxRow(
                title: 'Captured from',
                value: switch (transaction.source) {
                  TransactionSource.message => 'A bank SMS',
                  TransactionSource.notification => 'A bank notification',
                  TransactionSource.manual => 'You, by hand',
                },
              ),
              FluxRow(title: 'Currency', value: transaction.currency),
              if (transaction.note != null)
                FluxRow(title: 'Note', value: transaction.note!),
              FluxRow(
                title: 'Confidence',
                value: '${(transaction.confidence * 100).round()}%',
                trailing: SizedBox(
                  width: 54,
                  child: FluxProportion(
                    fraction: transaction.confidence,
                    color: transaction.confidence >= 0.8
                        ? palette.income
                        : palette.attention,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (transaction.sourceText != null)
          SliverToBoxAdapter(child: _EvidenceBlock(transaction: transaction)),
        SliverToBoxAdapter(
          child: FluxGroup(
            children: [
              FluxRow(
                title: 'Delete this transaction',
                icon: Icons.delete_outline_rounded,
                danger: true,
                onTap: () async {
                  final confirmed = await fluxConfirm(
                    context: context,
                    title: 'Delete this transaction?',
                    message:
                        'It comes out of every total and every chart. The '
                        'message it came from is not affected.',
                  );
                  if (!confirmed) return;
                  await controller.deleteTransaction(transaction.id!);
                  if (context.mounted) Navigator.of(context).maybePop();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewNote extends StatelessWidget {
  const _ReviewNote({required this.confidence});
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return FluxCard(
      color: palette.attentionSoft,
      border: palette.attention.withValues(alpha: 0.3),
      radius: FluxRadius.sm,
      padding: const EdgeInsets.all(FluxSpace.x4),
      child: Row(
        children: [
          Icon(Icons.rule_rounded, size: 18, color: palette.attention),
          const SizedBox(width: FluxSpace.x3),
          Expanded(
            child: Text(
              'Read at ${(confidence * 100).round()}% confidence. Check the '
              'message below and confirm or correct it.',
              style: FluxType.caption.copyWith(color: palette.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// The original message, with what was taken out of it highlighted.
class _EvidenceBlock extends ConsumerStatefulWidget {
  const _EvidenceBlock({required this.transaction});
  final MoneyTransaction transaction;

  @override
  ConsumerState<_EvidenceBlock> createState() => _EvidenceBlockState();
}

class _EvidenceBlockState extends ConsumerState<_EvidenceBlock> {
  bool _open = false;

  /// Spans of [text] that the extraction is claiming to have used.
  ///
  /// Found by searching for the values rather than recorded during parsing:
  /// the model returns values, not offsets, and asking it for offsets would be
  /// one more thing it can get wrong. A miss here simply leaves the text
  /// unhighlighted, which is honest — it never highlights the wrong thing.
  List<(int, int)> _highlights(String text) {
    final ranges = <(int, int)>[];
    final lower = text.toLowerCase();

    void add(String? needle) {
      if (needle == null) return;
      final value = needle.trim().toLowerCase();
      if (value.length < 3) return;
      final index = lower.indexOf(value);
      if (index >= 0) ranges.add((index, index + value.length));
    }

    add(widget.transaction.merchant);
    final minor = widget.transaction.amountMinor;
    for (final candidate in {
      minorToMajorInput(minor, widget.transaction.currency),
      (minor / 100).toStringAsFixed(2),
    }) {
      add(candidate);
    }
    ranges.sort((a, b) => a.$1.compareTo(b.$1));

    // Overlapping matches would paint a span twice and shift the text.
    final merged = <(int, int)>[];
    for (final range in ranges) {
      if (merged.isNotEmpty && range.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, range.$2 > last.$2 ? range.$2 : last.$2));
      } else {
        merged.add(range);
      }
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final text = widget.transaction.sourceText!;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final range in _highlights(text)) {
      if (range.$1 > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, range.$1)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.$1, range.$2),
          style: TextStyle(
            color: palette.iris,
            backgroundColor: palette.irisSoft,
          ),
        ),
      );
      cursor = range.$2;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));

    return Padding(
      padding: const EdgeInsets.only(
        left: FluxSpace.page,
        right: FluxSpace.page,
        top: FluxSpace.x6,
      ),
      child: FluxCard(
        padding: EdgeInsets.zero,
        clip: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FluxRow(
              title: 'From this message',
              subtitle: _open
                  ? 'Highlighted values are what was read out of it'
                  : 'The exact text this record came from',
              icon: Icons.sms_outlined,
              trailing: Icon(
                _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 20,
                color: palette.textFaint,
              ),
              onTap: () => setState(() => _open = !_open),
            ),
            AnimatedSize(
              duration: FluxMotion.duration(context, FluxMotion.normal),
              curve: FluxMotion.emphasized,
              alignment: Alignment.topCenter,
              child: _open
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FluxSpace.x4,
                        0,
                        FluxSpace.x4,
                        FluxSpace.x4,
                      ),
                      child: SelectableText.rich(
                        TextSpan(
                          children: spans,
                          style: FluxType.body.copyWith(
                            color: palette.textMuted,
                            height: 1.6,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
