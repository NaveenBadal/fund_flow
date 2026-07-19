import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../agent/agent_presentation.dart';
import '../../domain/transaction.dart';
import '../../ui/foundation/current_colors.dart';
import '../../ui/format/money_format.dart';

class AgentAnswerView extends StatelessWidget {
  const AgentAnswerView({
    super.key,
    required this.parts,
    required this.transactions,
    required this.onFollowUp,
    required this.onTransaction,
  });

  final List<AgentPart> parts;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onFollowUp;
  final ValueChanged<MoneyTransaction> onTransaction;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final part in parts) ...[
        _PartView(
          part: part,
          transactions: transactions,
          onFollowUp: onFollowUp,
          onTransaction: onTransaction,
        ),
        const SizedBox(height: 18),
      ],
    ],
  );
}

class _PartView extends StatelessWidget {
  const _PartView({
    required this.part,
    required this.transactions,
    required this.onFollowUp,
    required this.onTransaction,
  });

  final AgentPart part;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onFollowUp;
  final ValueChanged<MoneyTransaction> onTransaction;

  @override
  Widget build(BuildContext context) => switch (part.kind) {
    AgentPartKind.conclusion => _MarkdownText(
      text: _text,
      style: Theme.of(context).textTheme.headlineMedium,
    ),
    AgentPartKind.narrative => _MarkdownText(
      text: _text,
      style: Theme.of(context).textTheme.bodyLarge,
    ),
    AgentPartKind.metricRow => _MetricRow(data: part.data),
    AgentPartKind.comparison => _Comparison(data: part.data),
    AgentPartKind.breakdown => _Breakdown(data: part.data),
    AgentPartKind.transactionList => _TransactionEvidence(
      ids: _ids,
      transactions: transactions,
      onTransaction: onTransaction,
    ),
    AgentPartKind.insight => _Notice(
      icon: Icons.lightbulb_outline_rounded,
      text: _text,
      color: context.current.intelligence,
    ),
    AgentPartKind.sourceNote => _SourceDisclosure(text: _text, data: part.data),
    AgentPartKind.followUps => _FollowUps(
      questions: _strings(part.data['questions']),
      onTap: onFollowUp,
    ),
    AgentPartKind.proposal => _ProposalSummary(data: part.data),
    AgentPartKind.warning => _Notice(
      icon: Icons.info_outline_rounded,
      text: _text,
      color: context.current.review,
    ),
  };

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
        blockquote: base?.copyWith(color: context.current.muted),
        code: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontFamily: 'monospace',
          color: context.current.ink,
        ),
        codeblockDecoration: BoxDecoration(
          color: context.current.subtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.current.rule),
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.data});
  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    final values =
        (data['metrics'] as List? ?? data['values'] as List? ?? const [])
            .whereType<Map>()
            .take(4)
            .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        for (final raw in values)
          Builder(
            builder: (_) {
              final value = Map<Object?, Object?>.from(raw);
              final amount = value['amountMinor'];
              final display = amount is num && value['currency'] != null
                  ? formatMoney(amount.toInt(), value['currency'].toString())
                  : value['value']?.toString() ?? '—';
              return ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 120, maxWidth: 210),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value['label']?.toString() ?? 'Value',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.current.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      display,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontFamily: 'Space Grotesk',
                            fontWeight: FontWeight.w700,
                          ),
                    ),
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
  const _Comparison({required this.data});
  final Map<String, Object?> data;
  @override
  Widget build(BuildContext context) {
    final title = data['title']?.toString() ?? 'Compared with before';
    final detail = data['detail']?.toString() ?? data['text']?.toString() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.current.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.current.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(detail, style: TextStyle(color: context.current.muted)),
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
    final rows = (data['rows'] as List? ?? const [])
        .whereType<Map>()
        .take(8)
        .toList();
    final amounts = rows
        .map((row) => row['amountMinor'])
        .whereType<num>()
        .map((value) => value.toInt())
        .toList();
    final maximum = amounts.isEmpty ? 1 : max(1, amounts.reduce(max));
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data['title'] != null) ...[
          Text(
            data['title'].toString(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
        ],
        for (final raw in rows) ...[
          Builder(
            builder: (_) {
              final row = Map<Object?, Object?>.from(raw);
              final amount = (row['amountMinor'] as num?)?.toInt() ?? 0;
              final currency = row['currency']?.toString();
              return Padding(
                padding: const EdgeInsets.only(bottom: 13),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(row['label']?.toString() ?? 'Other'),
                        ),
                        if (currency != null)
                          Text(
                            formatMoney(amount, currency),
                            style: const TextStyle(fontFamily: 'Space Grotesk'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: max(.04, amount / maximum),
                        child: Container(
                          height: 5,
                          decoration: BoxDecoration(
                            color: context.current.intelligence,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _TransactionEvidence extends StatelessWidget {
  const _TransactionEvidence({
    required this.ids,
    required this.transactions,
    required this.onTransaction,
  });
  final List<int> ids;
  final List<MoneyTransaction> transactions;
  final ValueChanged<MoneyTransaction> onTransaction;

  @override
  Widget build(BuildContext context) {
    final values = transactions
        .where((item) => ids.contains(item.id))
        .take(8)
        .toList();
    if (values.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: context.current.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.current.rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < values.length; index++) ...[
            InkWell(
              onTap: () => onTransaction(values[index]),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(values[index].merchant),
                          const SizedBox(height: 3),
                          Text(
                            values[index].category,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: context.current.muted),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      formatMoney(
                        values[index].amountMinor,
                        values[index].currency,
                      ),
                      style: const TextStyle(fontFamily: 'Space Grotesk'),
                    ),
                    const SizedBox(width: 7),
                    const Icon(Icons.chevron_right_rounded, size: 19),
                  ],
                ),
              ),
            ),
            if (index != values.length - 1)
              Divider(
                height: 1,
                indent: 15,
                endIndent: 15,
                color: context.current.rule,
              ),
          ],
        ],
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: context.current.subtle,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _SourceDisclosure extends StatefulWidget {
  const _SourceDisclosure({required this.text, required this.data});
  final String text;
  final Map<String, Object?> data;
  @override
  State<_SourceDisclosure> createState() => _SourceDisclosureState();
}

class _SourceDisclosureState extends State<_SourceDisclosure> {
  bool open = false;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InkWell(
        onTap: () => setState(() => open = !open),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 17,
                color: context.current.income,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  open
                      ? 'Hide how this was calculated'
                      : 'How this was calculated',
                ),
              ),
              Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              ),
            ],
          ),
        ),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            widget.text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.current.muted),
          ),
        ),
    ],
  );
}

class _FollowUps extends StatelessWidget {
  const _FollowUps({required this.questions, required this.onTap});
  final List<String> questions;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Continue with', style: Theme.of(context).textTheme.labelLarge),
      const SizedBox(height: 7),
      for (final question in questions.take(3))
        InkWell(
          onTap: () => onTap(question),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Expanded(child: Text(question)),
                const Icon(Icons.arrow_forward_rounded, size: 17),
              ],
            ),
          ),
        ),
    ],
  );
}

class _ProposalSummary extends StatelessWidget {
  const _ProposalSummary({required this.data});
  final Map<String, Object?> data;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.current.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: context.current.intelligence),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Approval required',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: context.current.intelligence),
        ),
        const SizedBox(height: 7),
        Text(data['title']?.toString() ?? 'Review the proposed change'),
        const SizedBox(height: 5),
        Text(
          data['reversible'] == true
              ? 'Nothing changes until you approve. This can be undone.'
              : 'Nothing changes until you approve.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.current.muted),
        ),
      ],
    ),
  );
}

List<String> _strings(Object? value) => (value as List? ?? const [])
    .map((item) => item.toString().trim())
    .where((item) => item.isNotEmpty)
    .toList();
