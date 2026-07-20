import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../agent/agent_presentation.dart';
import '../../domain/transaction.dart';
import '../../domain/money_format.dart';
import '../charts/flow_charts.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';
import '../tokens/flow_type.dart';

/// Renders a structured answer in the flow design language.
///
/// Every figure the model states is drawn from the typed parts it composed,
/// never re-derived here: this view decides shape and rhythm, not numbers.
/// When [animate] is true the parts land one after another, which is the
/// honest rendering of an answer that was composed as a sequence — and makes
/// a long answer feel assembled rather than dumped.
class FlowAnswerView extends StatefulWidget {
  const FlowAnswerView({
    super.key,
    required this.parts,
    required this.transactions,
    required this.onFollowUp,
    required this.onTransaction,
    required this.onRecategorise,
    required this.onToggleReview,
    this.animate = false,
  });

  final List<AgentPart> parts;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onFollowUp;
  final ValueChanged<MoneyTransaction> onTransaction;
  final ValueChanged<MoneyTransaction> onRecategorise;
  final ValueChanged<MoneyTransaction> onToggleReview;
  final bool animate;

  @override
  State<FlowAnswerView> createState() => _FlowAnswerViewState();
}

class _FlowAnswerViewState extends State<FlowAnswerView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: FlowMotion.standard + FlowMotion.stagger * widget.parts.length,
    );
    if (widget.animate) {
      _entrance.forward();
    } else {
      _entrance.value = 1;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final parts = widget.parts;
    // A change stated in a metric row must not be restated by the comparison
    // beneath it: one finding should not look like two.
    final deltaShown = parts.any(
      (part) =>
          part.kind == AgentPartKind.metricRow &&
          (part.data['metrics'] as List? ?? const []).whereType<Map>().any(
            (metric) => metric['changeFraction'] is num,
          ),
    );
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final total = _entrance.duration!.inMilliseconds.toDouble();
    final step = FlowMotion.stagger.inMilliseconds.toDouble();
    final span = FlowMotion.standard.inMilliseconds.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < parts.length; index++) ...[
          if (widget.animate && !reduced)
            AnimatedBuilder(
              animation: _entrance,
              builder: (context, child) {
                final t = CurvedAnimation(
                  parent: _entrance,
                  curve: Interval(
                    (index * step / total).clamp(0.0, 1.0),
                    ((index * step + span) / total).clamp(0.0, 1.0),
                    curve: FlowMotion.enter,
                  ),
                ).value;
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, 8 * (1 - t)),
                    child: child,
                  ),
                );
              },
              child: _part(parts[index], deltaShown),
            )
          else
            _part(parts[index], deltaShown),
          if (index != parts.length - 1)
            SizedBox(height: _gapAfter(parts[index].kind)),
        ],
      ],
    );
  }

  Widget _part(AgentPart part, bool deltaShown) => _PartView(
    part: part,
    transactions: widget.transactions,
    onFollowUp: widget.onFollowUp,
    onTransaction: widget.onTransaction,
    onRecategorise: widget.onRecategorise,
    onToggleReview: widget.onToggleReview,
    deltaAlreadyShown: deltaShown,
  );

  /// Vertical rhythm follows meaning: a conclusion and the figures proving
  /// it belong together; a source note sits apart from what it annotates.
  static double _gapAfter(AgentPartKind kind) => switch (kind) {
    AgentPartKind.conclusion => FlowSpace.md,
    AgentPartKind.metricRow => FlowSpace.lg + FlowSpace.xs,
    AgentPartKind.narrative || AgentPartKind.insight => FlowSpace.lg,
    AgentPartKind.sourceNote => FlowSpace.sm,
    _ => FlowSpace.xl,
  };
}

class _PartView extends StatelessWidget {
  const _PartView({
    required this.part,
    required this.transactions,
    required this.onFollowUp,
    required this.onTransaction,
    required this.onRecategorise,
    required this.onToggleReview,
    this.deltaAlreadyShown = false,
  });

  final AgentPart part;
  final bool deltaAlreadyShown;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onFollowUp;
  final ValueChanged<MoneyTransaction> onTransaction;
  final ValueChanged<MoneyTransaction> onRecategorise;
  final ValueChanged<MoneyTransaction> onToggleReview;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return switch (part.kind) {
      AgentPartKind.conclusion => _MarkdownText(
        text: _text,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      AgentPartKind.narrative => _MarkdownText(
        text: _text,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      AgentPartKind.metricRow => _MetricRow(data: part.data),
      AgentPartKind.comparison => _Comparison(
        data: part.data,
        deltaAlreadyShown: deltaAlreadyShown,
      ),
      AgentPartKind.breakdown => _Breakdown(data: part.data),
      AgentPartKind.transactionList => _TransactionEvidence(
        ids: _ids,
        transactions: transactions,
        onTransaction: onTransaction,
        onRecategorise: onRecategorise,
        onToggleReview: onToggleReview,
      ),
      AgentPartKind.insight => _Notice(
        icon: Icons.lightbulb_outline_rounded,
        text: _text,
        color: flow.accent,
      ),
      AgentPartKind.sourceNote => _SourceDisclosure(text: _text),
      AgentPartKind.followUps => _FollowUps(
        questions: _strings(part.data['questions']),
        onTap: onFollowUp,
      ),
      AgentPartKind.proposal => _ProposalSummary(data: part.data),
      AgentPartKind.warning => _Notice(
        icon: Icons.info_outline_rounded,
        text: _text,
        color: flow.attention,
      ),
    };
  }

  String get _text => part.data['text']?.toString().trim() ?? '';
  List<int> get _ids => (part.data['transactionIds'] as List? ?? const [])
      .whereType<num>()
      .map((value) => value.toInt())
      .toList();
}

class _MarkdownText extends StatelessWidget {
  const _MarkdownText({required this.text, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final base = style ?? Theme.of(context).textTheme.bodyLarge;
    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: base,
        h1: Theme.of(context).textTheme.headlineLarge,
        h2: Theme.of(context).textTheme.headlineMedium,
        h3: Theme.of(context).textTheme.titleLarge,
        listBullet: base,
        blockquote: base?.copyWith(color: flow.inkSoft),
        code: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          color: flow.ink,
        ),
        codeblockDecoration: BoxDecoration(
          color: flow.sunken,
          borderRadius: FlowRadius.sm,
        ),
      ),
    );
  }
}

double? _fraction(Object? value) => value is num ? value.toDouble() : null;

/// Whether a rise in this metric is adverse. Spending up is bad; money in
/// going up is not.
bool _isSpending(String? label) {
  final text = label?.toLowerCase() ?? '';
  const incoming = ['received', 'income', 'credited', 'in', 'earned', 'refund'];
  return !incoming.any(text.contains);
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final values =
        (data['metrics'] as List? ?? data['values'] as List? ?? const [])
            .whereType<Map>()
            .take(4)
            .toList();
    if (values.isEmpty) return const SizedBox.shrink();

    // A lone metric is the answer itself, so it gets the amount-hero role
    // rather than being shrunk into a row of equals.
    if (values.length == 1) {
      final value = Map<Object?, Object?>.from(values.single);
      final amount = value['amountMinor'];
      if (amount is num && value['currency'] != null) {
        final change = _fraction(value['changeFraction']);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value['label']?.toString() ?? 'Total',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.xs),
            Row(
              children: [
                Flexible(
                  child: Text(
                    formatMoney(amount.toInt(), value['currency'].toString()),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FlowType.amountHero.copyWith(
                      fontSize: 34,
                      color: flow.ink,
                    ),
                  ),
                ),
                if (change != null) ...[
                  const SizedBox(width: FlowSpace.md),
                  FlowDelta(
                    fraction: change,
                    spending: _isSpending(value['label']?.toString()),
                  ),
                ],
              ],
            ),
          ],
        );
      }
    }
    return Wrap(
      spacing: FlowSpace.xl,
      runSpacing: FlowSpace.lg,
      children: [
        for (final raw in values)
          Builder(
            builder: (context) {
              final value = Map<Object?, Object?>.from(raw);
              final amount = value['amountMinor'];
              final display = amount is num && value['currency'] != null
                  ? formatMoney(amount.toInt(), value['currency'].toString())
                  : value['value']?.toString() ?? '—';
              final change = _fraction(value['changeFraction']);
              return ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 110, maxWidth: 200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value['label']?.toString() ?? 'Value',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                    ),
                    const SizedBox(height: FlowSpace.xs),
                    Text(
                      display,
                      style: FlowType.amountLarge.copyWith(color: flow.ink),
                    ),
                    if (change != null) ...[
                      const SizedBox(height: FlowSpace.xs),
                      FlowDelta(
                        fraction: change,
                        compact: true,
                        spending: _isSpending(value['label']?.toString()),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.data, this.deltaAlreadyShown = false});
  final Map<String, Object?> data;
  final bool deltaAlreadyShown;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final title = data['title']?.toString() ?? 'Compared with before';
    final detail = data['detail']?.toString() ?? data['text']?.toString() ?? '';
    final currentMinor = (data['currentMinor'] as num?)?.toInt();
    final previousMinor = (data['previousMinor'] as num?)?.toInt();
    final currency = data['currency']?.toString();
    return Container(
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
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          // Drawn only when the agent supplied both periods; otherwise the
          // prose stands alone rather than inventing a shape for one number.
          if (currentMinor != null &&
              previousMinor != null &&
              currency != null) ...[
            const SizedBox(height: FlowSpace.md),
            FlowCompareBars(
              currentLabel: data['currentLabel']?.toString() ?? 'This period',
              currentAmount: formatMoney(currentMinor, currency),
              currentMinor: currentMinor,
              previousLabel:
                  data['previousLabel']?.toString() ?? 'Previous period',
              previousAmount: formatMoney(previousMinor, currency),
              previousMinor: previousMinor,
              showDelta: !deltaAlreadyShown,
            ),
          ],
          if (detail.isNotEmpty) ...[
            const SizedBox(height: FlowSpace.sm),
            Text(
              detail,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final rows = (data['rows'] as List? ?? const [])
        .whereType<Map>()
        .take(8)
        .toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    final amounts = rows
        .map((row) => (row['amountMinor'] as num?)?.toInt() ?? 0)
        .toList();
    final maximum = max(1, amounts.reduce(max));
    final total = amounts.fold<int>(0, (sum, value) => sum + value);
    final currency = rows.first['currency']?.toString() ?? '';

    // A donut is legitimate only for part-to-whole at a glance: few
    // segments, and not close values — bars answer "which is bigger" far
    // better. The guard is mechanical so the choice never depends on taste.
    final shares = total > 0
        ? amounts.map((value) => value / total).toList()
        : const <double>[];
    final donut =
        rows.length >= 2 &&
        rows.length <= 5 &&
        total > 0 &&
        currency.isNotEmpty &&
        shares[0] - shares[1] >= .08;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data['title'] != null) ...[
          Text(
            data['title'].toString(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FlowSpace.md),
        ],
        if (donut)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FlowDonut(
                segments: [
                  for (var index = 0; index < rows.length; index++)
                    FlowDonutSegment(
                      value: amounts[index].toDouble(),
                      color: flow.seriesAt(index),
                    ),
                ],
                centerValue: formatMoney(total, currency),
                centerLabel: 'total',
              ),
              const SizedBox(width: FlowSpace.lg),
              Expanded(
                child: Column(
                  children: [
                    for (var index = 0; index < rows.length; index++)
                      _LegendRow(
                        color: flow.seriesAt(index),
                        label: rows[index]['label']?.toString() ?? 'Other',
                        amount: formatMoney(amounts[index], currency),
                        share: shares[index],
                      ),
                  ],
                ),
              ),
            ],
          )
        else
          for (var index = 0; index < rows.length; index++)
            FlowBarRow(
              label: rows[index]['label']?.toString() ?? 'Other',
              amount: rows[index]['currency'] == null
                  ? '${amounts[index]}'
                  : formatMoney(
                      amounts[index],
                      rows[index]['currency'].toString(),
                    ),
              fraction: amounts[index] / maximum,
              share: total > 0 ? amounts[index] / total : null,
              color: flow.seriesAt(index),
            ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.share,
  });

  final Color color;
  final String label;
  final String amount;
  final double share;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: FlowSpace.xs),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: FlowSpace.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Text(
            '${(share * 100).round()}%',
            style: FlowType.amountSmall.copyWith(color: flow.inkFaint),
          ),
          const SizedBox(width: FlowSpace.sm),
          Text(amount, style: FlowType.amountSmall.copyWith(color: flow.ink)),
        ],
      ),
    );
  }
}

class _TransactionEvidence extends StatelessWidget {
  const _TransactionEvidence({
    required this.ids,
    required this.transactions,
    required this.onTransaction,
    required this.onRecategorise,
    required this.onToggleReview,
  });

  final List<int> ids;
  final List<MoneyTransaction> transactions;
  final ValueChanged<MoneyTransaction> onTransaction;
  final ValueChanged<MoneyTransaction> onRecategorise;
  final ValueChanged<MoneyTransaction> onToggleReview;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final values = transactions
        .where((item) => ids.contains(item.id))
        .take(8)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: flow.raised,
        borderRadius: FlowRadius.md,
        border: Border.all(color: flow.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < values.length; index++) ...[
            _EvidenceRow(
              item: values[index],
              onOpen: () => onTransaction(values[index]),
              onRecategorise: () => onRecategorise(values[index]),
              onToggleReview: () => onToggleReview(values[index]),
            ),
            if (index != values.length - 1)
              Divider(
                height: 1,
                indent: FlowSpace.lg,
                endIndent: FlowSpace.lg,
                color: flow.line,
              ),
          ],
        ],
      ),
    );
  }
}

/// A record cited as evidence. Tapping it routes to the transaction itself;
/// the menu offers the two corrections worth making without leaving the
/// answer, because a wrong category discovered mid-conversation should cost
/// one tap, not a navigation.
class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.item,
    required this.onOpen,
    required this.onRecategorise,
    required this.onToggleReview,
  });

  final MoneyTransaction item;
  final VoidCallback onOpen;
  final VoidCallback onRecategorise;
  final VoidCallback onToggleReview;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final incoming = item.direction == TransactionDirection.incoming;
    final pending = item.reviewState == ReviewState.needsReview;
    return InkWell(
      onTap: onOpen,
      child: Container(
        constraints: const BoxConstraints(minHeight: FlowDensity.compactRow),
        padding: const EdgeInsets.only(left: FlowSpace.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    pending ? '${item.category} · needs a look' : item.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: pending ? flow.attention : flow.inkFaint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: FlowSpace.sm),
            Text(
              '${incoming ? '+' : '−'}'
              '${formatMoney(item.amountMinor, item.currency)}',
              style: FlowType.amountRow.copyWith(
                color: incoming ? flow.income : flow.ink,
              ),
            ),
            PopupMenuButton<void Function()>(
              tooltip: 'Actions',
              iconSize: 18,
              iconColor: flow.inkFaint,
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: onRecategorise,
                  child: const Text('Change category'),
                ),
                PopupMenuItem(
                  value: onToggleReview,
                  child: Text(pending ? 'Confirm' : 'Flag for review'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      padding: const EdgeInsets.all(FlowSpace.md),
      decoration: BoxDecoration(
        color: flow.sunken,
        borderRadius: FlowRadius.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: FlowSpace.sm + 2),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _SourceDisclosure extends StatefulWidget {
  const _SourceDisclosure({required this.text});
  final String text;
  @override
  State<_SourceDisclosure> createState() => _SourceDisclosureState();
}

class _SourceDisclosureState extends State<_SourceDisclosure> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => open = !open),
          borderRadius: FlowRadius.sm,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: FlowSpace.sm),
            child: Row(
              children: [
                Icon(Icons.fact_check_outlined, size: 16, color: flow.income),
                const SizedBox(width: FlowSpace.sm),
                Expanded(
                  child: Text(
                    open
                        ? 'Hide how this was calculated'
                        : 'How this was calculated',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
                  ),
                ),
                Icon(
                  open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: flow.inkFaint,
                ),
              ],
            ),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.only(bottom: FlowSpace.sm),
            child: Text(
              widget.text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: flow.inkSoft,
                height: 1.45,
              ),
            ),
          ),
      ],
    );
  }
}

class _FollowUps extends StatelessWidget {
  const _FollowUps({required this.questions, required this.onTap});
  final List<String> questions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    if (questions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: FlowSpace.sm,
      runSpacing: FlowSpace.sm,
      children: [
        for (final question in questions.take(3))
          InkWell(
            onTap: () => onTap(question),
            borderRadius: FlowRadius.pill,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FlowSpace.md,
                vertical: FlowSpace.sm,
              ),
              decoration: BoxDecoration(
                color: flow.raised,
                borderRadius: FlowRadius.pill,
                border: Border.all(color: flow.line),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      question,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  const SizedBox(width: FlowSpace.xs),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 13,
                    color: flow.inkFaint,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ProposalSummary extends StatelessWidget {
  const _ProposalSummary({required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: flow.raised,
        borderRadius: FlowRadius.md,
        border: Border.all(color: flow.accent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // This is the answer's record of what was proposed, and it stays in
          // the thread after the change is approved or declined. Only the
          // live approval card below may speak about the pending decision:
          // an answer still reading "nothing changes until you approve" an
          // hour after the change was applied is a lie about the ledger.
          Text(
            'Proposed change',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: flow.accent),
          ),
          const SizedBox(height: FlowSpace.sm),
          Text(
            data['title']?.toString() ?? 'Review the proposed change',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

List<String> _strings(Object? value) => (value as List? ?? const [])
    .map((item) => item.toString().trim())
    .where((item) => item.isNotEmpty)
    .toList();
