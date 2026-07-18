import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/agent_artifact.dart';
import '../theme/app_tokens.dart';
import '../utils/currency_utils.dart';

class AgentArtifactCard extends StatelessWidget {
  const AgentArtifactCard({
    super.key,
    required this.artifact,
    required this.onPrompt,
  });

  final AgentArtifact artifact;
  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    if (artifact.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: artifact.title,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: ShapeDecoration(
          color: scheme.surfaceContainer,
          shape: ExpressiveShape.card(radius: AppRadius.xl),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _icon,
                      size: 20,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artifact.title,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (artifact.subtitle.isNotEmpty)
                          Text(
                            artifact.subtitle,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.verified_user_outlined,
                    size: 18,
                    color: scheme.primary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _content(context),
              if (artifact.actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in artifact.actions)
                      ActionChip(
                        label: Text(action),
                        onPressed: () => onPrompt(action),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData get _icon => switch (artifact.kind) {
    AgentArtifactKind.transactions => Icons.receipt_long_outlined,
    AgentArtifactKind.summary => Icons.account_balance_wallet_outlined,
    AgentArtifactKind.breakdown => Icons.donut_large_rounded,
    AgentArtifactKind.comparison => Icons.compare_arrows_rounded,
    AgentArtifactKind.recurring => Icons.autorenew_rounded,
    AgentArtifactKind.forecast => Icons.trending_up_rounded,
    AgentArtifactKind.anomalies => Icons.notification_important_outlined,
    AgentArtifactKind.action => Icons.task_alt_rounded,
    AgentArtifactKind.insight => Icons.lightbulb_outline_rounded,
    _ => Icons.blur_on_outlined,
  };

  Widget _content(BuildContext context) => switch (artifact.kind) {
    AgentArtifactKind.transactions => _transactions(context),
    AgentArtifactKind.breakdown => _breakdown(context),
    AgentArtifactKind.comparison => _comparison(context),
    AgentArtifactKind.recurring => _recurring(context),
    AgentArtifactKind.forecast => _forecast(context),
    AgentArtifactKind.anomalies => _anomalies(context),
    AgentArtifactKind.summary => _summary(context),
    AgentArtifactKind.action => _action(context),
    _ => const SizedBox.shrink(),
  };

  Widget _transactions(BuildContext context) {
    final records = artifact.data['records'] as List<dynamic>? ?? const [];
    return Column(
      children: records.take(5).whereType<Map>().map((raw) {
        final item = raw.cast<String, dynamic>();
        return _ResultRow(
          title: item['merchant']?.toString() ?? 'Unknown',
          subtitle: _date(item['date']),
          value: formatAmount(
            (item['amount'] as num?)?.toDouble() ?? 0,
            item['currency']?.toString() ?? '',
          ),
        );
      }).toList(),
    );
  }

  Widget _breakdown(BuildContext context) {
    final groups = artifact.data['groups'] as List<dynamic>? ?? const [];
    final typed = groups.take(6).whereType<Map>().toList();
    final maximum = typed.fold<double>(
      0,
      (value, row) => ((row['total'] as num?)?.toDouble() ?? 0) > value
          ? (row['total'] as num).toDouble()
          : value,
    );
    return Column(
      children: typed.map((raw) {
        final item = raw.cast<String, dynamic>();
        final total = (item['total'] as num?)?.toDouble() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              _ResultRow(
                title: item['label']?.toString() ?? 'Unknown',
                value: formatAmount(total, item['currency']?.toString() ?? ''),
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: maximum == 0 ? 0 : total / maximum,
                borderRadius: BorderRadius.circular(999),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _comparison(BuildContext context) {
    final values = artifact.data['comparisons'] as List<dynamic>? ?? const [];
    return Column(
      children: values
          .whereType<Map>()
          .where((raw) {
            return (raw['first'] as num? ?? 0) != 0 ||
                (raw['second'] as num? ?? 0) != 0;
          })
          .map((raw) {
            final item = raw.cast<String, dynamic>();
            final change = (item['change'] as num?)?.toDouble() ?? 0;
            return _ResultRow(
              title: item['direction'] == 'income' ? 'Income' : 'Spending',
              subtitle:
                  '${change >= 0 ? '+' : ''}${formatAmount(change, item['currency'].toString())}',
              value: formatAmount(
                (item['second'] as num).toDouble(),
                item['currency'].toString(),
              ),
            );
          })
          .toList(),
    );
  }

  Widget _recurring(BuildContext context) => _list(
    artifact.data['recurring'],
    (item) => _ResultRow(
      title: item['merchant']?.toString() ?? 'Unknown',
      subtitle: 'About every ${item['frequency_days']} days',
      value: formatAmount(
        (item['average_amount'] as num?)?.toDouble() ?? 0,
        item['currency']?.toString() ?? '',
      ),
    ),
  );

  Widget _anomalies(BuildContext context) => _list(
    artifact.data['anomalies'] ??
        (artifact.data['duplicate_pairs'] as List<dynamic>?)
            ?.map((pair) => (pair as Map)['possible_duplicate'])
            .toList(),
    (item) => _ResultRow(
      title: item['merchant']?.toString() ?? 'Unknown',
      subtitle: _date(item['date']),
      value: formatAmount(
        (item['amount'] as num?)?.toDouble() ?? 0,
        item['currency']?.toString() ?? '',
      ),
    ),
  );

  Widget _forecast(BuildContext context) => _list(
    artifact.data['forecast'],
    (item) => _ResultRow(
      title: '${item['horizon_days']}-day projected net',
      subtitle: 'Based on the previous ${item['basis_days']} days',
      value: formatAmount(
        (item['projected_net'] as num?)?.toDouble() ?? 0,
        item['currency']?.toString() ?? '',
      ),
    ),
  );

  Widget _summary(BuildContext context) {
    final budgets = artifact.data['budgets'] as List<dynamic>?;
    if (budgets != null) {
      return Column(
        children: budgets.whereType<Map>().map((raw) {
          final item = raw.cast<String, dynamic>();
          final used = (item['percent_used'] as num?)?.toDouble() ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                _ResultRow(
                  title: item['name']?.toString() ?? 'Budget',
                  subtitle: '${used.round()}% used',
                  value: formatAmount(
                    (item['remaining'] as num?)?.toDouble() ?? 0,
                    item['currency']?.toString() ?? '',
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: (used / 100).clamp(0, 1)),
              ],
            ),
          );
        }).toList(),
      );
    }
    final totals = artifact.data['totals_by_currency'] as Map? ?? const {};
    return Column(
      children: totals.entries.map((entry) {
        final values = (entry.value as Map).cast<String, dynamic>();
        return _ResultRow(
          title: 'Paid',
          subtitle: (values['income'] as num? ?? 0) == 0
              ? null
              : 'Received ${formatAmount((values['income'] as num).toDouble(), entry.key.toString())}',
          value: formatAmount(
            (values['expense'] as num?)?.toDouble() ?? 0,
            entry.key.toString(),
          ),
        );
      }).toList(),
    );
  }

  Widget _action(BuildContext context) => Row(
    children: [
      Icon(
        Icons.check_circle_rounded,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(width: 10),
      const Expanded(child: Text('Applied and verified on this device')),
    ],
  );

  Widget _list(dynamic raw, Widget Function(Map<String, dynamic>) builder) {
    final values = raw as List<dynamic>? ?? const [];
    return Column(
      children: values
          .take(6)
          .whereType<Map>()
          .map((value) => builder(value.cast<String, dynamic>()))
          .toList(),
    );
  }

  String? _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed == null ? null : DateFormat('d MMM · h:mm a').format(parsed);
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.title, required this.value, this.subtitle});
  final String title;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: Text(value, style: Theme.of(context).textTheme.labelLarge),
          ),
        ),
      ],
    ),
  );
}
