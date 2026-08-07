import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../agent/agent_presentation.dart';
import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../../domain/money_format.dart';
import '../../domain/transaction.dart';
import '../activity/transaction_page.dart';
import '../activity/transaction_row.dart';
import '../common/formatting.dart';

/// Renders one typed answer part.
///
/// The agent's answers are structured data, not markdown. That is the single
/// biggest difference between this and a chat window: a total arrives as a
/// figure with a currency, so it can be drawn as a chart, coloured by
/// direction, and tapped through to the transactions behind it. Rendering the
/// same answer as prose throws all of that away and puts the whole burden of
/// believing it on the reader.
class AnswerPartView extends ConsumerWidget {
  const AnswerPartView({
    super.key,
    required this.part,
    required this.onFollowUp,
  });

  final AgentPart part;
  final ValueChanged<String> onFollowUp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);
    String? text() => part.data['text']?.toString();

    return switch (part.kind) {
      // The answer itself: full width, no card, largest prose on the screen.
      AgentPartKind.conclusion => Text(
        text() ?? '',
        style: FluxType.bodyLarge.copyWith(color: palette.text),
      ),

      AgentPartKind.redirect => _RedirectBlock(text: text() ?? ''),

      AgentPartKind.narrative || AgentPartKind.insight => Text(
        text() ?? '',
        style: FluxType.body.copyWith(color: palette.textMuted),
      ),

      AgentPartKind.warning => FluxCard(
        color: palette.attentionSoft,
        border: palette.attention.withValues(alpha: 0.3),
        radius: FluxRadius.sm,
        padding: const EdgeInsets.all(FluxSpace.x4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 17,
              color: palette.attention,
            ),
            const SizedBox(width: FluxSpace.x3),
            Expanded(
              child: Text(
                text() ?? '',
                style: FluxType.caption.copyWith(color: palette.text),
              ),
            ),
          ],
        ),
      ),

      AgentPartKind.metricRow => _MetricRow(part: part, money: money),
      AgentPartKind.comparison => _Comparison(part: part, money: money),
      AgentPartKind.breakdown => _Breakdown(part: part, money: money),
      AgentPartKind.transactionList => _TransactionList(part: part),

      AgentPartKind.sourceNote => Text(
        text() ?? '',
        style: FluxType.caption.copyWith(color: palette.textFaint),
      ),

      AgentPartKind.followUps => _FollowUps(part: part, onFollowUp: onFollowUp),

      // The approval card is rendered by the thread rather than here: it
      // belongs to the app's pending state, not to the text of the answer, and
      // it has to survive a rebuild of the message list.
      AgentPartKind.proposal => const SizedBox.shrink(),
    };
  }
}

/// An out-of-scope question, declined.
class _RedirectBlock extends StatelessWidget {
  const _RedirectBlock({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return FluxCard(
      color: palette.surfaceHighest,
      radius: FluxRadius.sm,
      padding: const EdgeInsets.all(FluxSpace.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.block_rounded, size: 17, color: palette.textMuted),
          const SizedBox(width: FluxSpace.x3),
          Expanded(
            child: Text(
              text,
              style: FluxType.body.copyWith(color: palette.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// Money and non-money figures, side by side.
class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.part, required this.money});
  final AgentPart part;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    // The contract names `metrics`; providers reach for `values` often enough
    // that refusing to read it would drop an otherwise correct answer.
    final raw = part.data['metrics'] ?? part.data['values'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();

    // If any tile carries a delta badge, every tile reserves room for one.
    // Otherwise a row of stat tiles comes out at two different heights, which
    // reads as a layout fault rather than as extra information on one of them.
    final anyChange = raw.whereType<Map>().any(
      (item) => item['changeFraction'] is num,
    );

    return Wrap(
      spacing: FluxSpace.x3,
      runSpacing: FluxSpace.x3,
      children: [
        for (final item in raw.whereType<Map>())
          () {
            final data = Map<String, Object?>.from(
              item.cast<String, Object?>(),
            );
            final amount = data['amountMinor'];
            final currency = data['currency']?.toString();
            final change = data['changeFraction'];
            final value = amount is num && isPlausibleCurrency(currency)
                ? money(amount.round(), currency!)
                : data['value']?.toString() ?? '—';
            return FluxCard(
              raised: true,
              radius: FluxRadius.sm,
              padding: const EdgeInsets.all(FluxSpace.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    data['label']?.toString() ?? '',
                    style: FluxType.caption.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: FluxSpace.x1 + 2),
                  Text(
                    value,
                    style: FluxType.moneySmall.copyWith(
                      color: palette.text,
                      fontSize: 20,
                    ),
                  ),
                  if (change is num) ...[
                    const SizedBox(height: FluxSpace.x2),
                    FluxDelta(fraction: change.toDouble(), compact: true),
                  ] else if (anyChange)
                    const SizedBox(height: FluxSpace.x2 + 18),
                ],
              ),
            );
          }(),
      ],
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.part, required this.money});
  final AgentPart part;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final currency = part.data['currency']?.toString() ?? '';
    final current = part.data['currentMinor'];
    final previous = part.data['previousMinor'];
    if (current is! num || previous is! num) return const SizedBox.shrink();

    return FluxCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (part.data['title'] != null) ...[
            Text(
              part.data['title'].toString(),
              style: FluxType.label.copyWith(color: palette.text),
            ),
            const SizedBox(height: FluxSpace.x3),
          ],
          FluxComparison(
            currentLabel:
                part.data['currentLabel']?.toString() ?? 'This period',
            currentValue: current.toDouble(),
            currentDisplay: money(current.round(), currency),
            previousLabel: part.data['previousLabel']?.toString() ?? 'Before',
            previousValue: previous.toDouble(),
            previousDisplay: money(previous.round(), currency),
          ),
          if (part.data['detail'] != null) ...[
            const SizedBox(height: FluxSpace.x3),
            Text(
              part.data['detail'].toString(),
              style: FluxType.caption.copyWith(color: palette.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.part, required this.money});
  final AgentPart part;
  final MoneyFormatter money;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final rows = part.data['rows'];
    if (rows is! List || rows.isEmpty) return const SizedBox.shrink();

    final entries = [
      for (final row in rows.whereType<Map>())
        () {
          final data = Map<String, Object?>.from(row.cast<String, Object?>());
          final amount = data['amountMinor'];
          return (
            label: data['label']?.toString() ?? '',
            value: amount is num ? amount.toDouble() : 0.0,
            currency: data['currency']?.toString() ?? '',
          );
        }(),
    ];
    final largest = entries.fold<double>(
      0,
      (highest, row) => row.value > highest ? row.value : highest,
    );

    return FluxCard(
      raised: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (part.data['title'] != null) ...[
            Text(
              part.data['title'].toString(),
              style: FluxType.label.copyWith(color: palette.text),
            ),
            const SizedBox(height: FluxSpace.x4),
          ],
          for (final row in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: FluxSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: ShapeDecoration(
                          color: palette.forCategory(row.label),
                          shape: const CircleBorder(),
                        ),
                      ),
                      const SizedBox(width: FluxSpace.x2),
                      Expanded(
                        child: Text(
                          row.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FluxType.body.copyWith(color: palette.text),
                        ),
                      ),
                      MoneyText(money(row.value.round(), row.currency)),
                    ],
                  ),
                  const SizedBox(height: FluxSpace.x2),
                  FluxProportion(
                    fraction: largest <= 0 ? 0 : row.value / largest,
                    color: palette.forCategory(row.label),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The transactions an answer cites, as real ledger rows.
///
/// Tappable through to the detail page, and from there to the SMS the figure
/// came out of. This is what makes a claim checkable rather than merely stated.
class _TransactionList extends ConsumerWidget {
  const _TransactionList({required this.part});
  final AgentPart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final money = ref.watch(moneyProvider);
    final ids = part.data['transactionIds'];
    if (ids is! List || ids.isEmpty) return const SizedBox.shrink();

    final wanted = ids.whereType<int>().toList();
    final all =
        ref.watch(appControllerProvider).value?.transactions ??
        const <MoneyTransaction>[];
    // Kept in the order the answer supplied, not the ledger's. An answer about
    // the largest charges has already ranked them, and re-sorting by date here
    // silently contradicts the sentence above the list.
    final byId = <int, MoneyTransaction>{};
    for (final item in all) {
      final id = item.id;
      if (id != null) byId[id] = item;
    }
    final items = [for (final id in wanted) ?byId[id]];
    if (items.isEmpty) {
      return Text(
        'The transactions behind this answer have since been removed.',
        style: FluxType.caption.copyWith(color: palette.textFaint),
      );
    }

    return FluxCard(
      raised: true,
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const FluxLine(indent: FluxSpace.x16),
            TransactionRow(
              transaction: items[index],
              money: money,
              showDate: true,
              onTap: items[index].id == null
                  ? null
                  : () => fluxPush(
                      context,
                      (context) => TransactionPage(id: items[index].id!),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FollowUps extends StatelessWidget {
  const _FollowUps({required this.part, required this.onFollowUp});
  final AgentPart part;
  final ValueChanged<String> onFollowUp;

  @override
  Widget build(BuildContext context) {
    final questions = part.data['questions'];
    if (questions is! List || questions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: FluxSpace.x2,
      runSpacing: FluxSpace.x2,
      children: [
        for (final question in questions.whereType<String>().take(3))
          FluxChip(
            label: question,
            icon: Icons.subdirectory_arrow_right_rounded,
            onTap: () => onFollowUp(question),
          ),
      ],
    );
  }
}
