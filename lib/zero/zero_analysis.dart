import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/app_controller.dart';
import '../domain/money_format.dart';
import '../domain/transaction.dart';
import 'zero_theme.dart';

class ZeroAnalysis extends ConsumerWidget {
  const ZeroAnalysis({super.key, required this.period});
  final DateTime period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final values = app.transactions
        .where(
          (item) =>
              item.occurredAt.year == period.year &&
              item.occurredAt.month == period.month &&
              item.direction == TransactionDirection.outgoing &&
              item.currency == app.preferences.currency,
        )
        .toList();
    final total = values.fold(0, (sum, item) => sum + item.amountMinor);
    final categories = _groups(values, (item) => item.category);
    final merchants = _groups(values, (item) => item.merchant);
    final days = _days(
      values,
      DateUtils.getDaysInMonth(period.year, period.month),
    );
    final z = context.zero;
    return Scaffold(
      appBar: AppBar(title: const Text('Spending analysis')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 44),
                sliver: SliverList.list(
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(period),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: z.muted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      app.preferences.hideAmounts
                          ? '••••••'
                          : formatMoney(total, app.preferences.currency),
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 36),
                    _DailyBars(values: days),
                    const SizedBox(height: 44),
                    _GroupSection(
                      title: 'By category',
                      values: categories,
                      total: total,
                      currency: app.preferences.currency,
                      hidden: app.preferences.hideAmounts,
                    ),
                    const SizedBox(height: 42),
                    _GroupSection(
                      title: 'Top merchants',
                      values: merchants.take(8).toList(),
                      total: total,
                      currency: app.preferences.currency,
                      hidden: app.preferences.hideAmounts,
                    ),
                    const SizedBox(height: 42),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const _AnalysisNote(),
                        ),
                      ),
                      icon: const Icon(Icons.info_outline_rounded),
                      label: Text('${values.length} records included'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailyBars extends StatefulWidget {
  const _DailyBars({required this.values});
  final List<int> values;

  @override
  State<_DailyBars> createState() => _DailyBarsState();
}

class _DailyBarsState extends State<_DailyBars> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    final max = widget.values.fold(0, (a, b) => a > b ? a : b);
    return Semantics(
      label: 'Daily spending chart. Swipe across bars to inspect each day.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Daily rhythm',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              if (selected != null)
                Text(
                  '${selected! + 1} ${DateFormat.MMM().format(DateTime.now())}',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: context.zero.muted),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 112,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (detail) => setState(
                  () => selected =
                      (detail.localPosition.dx /
                              box.maxWidth *
                              widget.values.length)
                          .floor()
                          .clamp(0, widget.values.length - 1),
                ),
                onTapDown: (detail) => setState(
                  () => selected =
                      (detail.localPosition.dx /
                              box.maxWidth *
                              widget.values.length)
                          .floor()
                          .clamp(0, widget.values.length - 1),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < widget.values.length; i++)
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: max == 0
                              ? 2
                              : 4 + 104 * widget.values[i] / max,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: selected == i
                                ? context.zero.text
                                : context.zero.accent,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({
    required this.title,
    required this.values,
    required this.total,
    required this.currency,
    required this.hidden,
  });
  final String title;
  final List<(String, int)> values;
  final int total;
  final String currency;
  final bool hidden;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 15),
      if (values.isEmpty)
        Text(
          'Nothing to show for this period.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.zero.muted),
        )
      else
        for (final value in values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Text(value.$1)),
                    Text(
                      hidden ? '••••' : formatMoney(value.$2, currency),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: total == 0 ? 0 : value.$2 / total,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: context.zero.subtle,
                  color: context.zero.accent,
                ),
              ],
            ),
          ),
    ],
  );
}

class _AnalysisNote extends StatelessWidget {
  const _AnalysisNote();
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('What is included')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        'This analysis uses confirmed and unconfirmed outgoing records in your primary currency. Incoming transfers are excluded. Every figure is calculated locally from the transactions shown in Fund Flow.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    ),
  );
}

List<(String, int)> _groups(
  List<MoneyTransaction> values,
  String Function(MoneyTransaction) key,
) {
  final totals = <String, int>{};
  for (final value in values) {
    totals[key(value)] = (totals[key(value)] ?? 0) + value.amountMinor;
  }
  return totals.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2.compareTo(a.$2));
}

List<int> _days(List<MoneyTransaction> values, int count) => List.generate(
  count,
  (index) => values
      .where((item) => item.occurredAt.day == index + 1)
      .fold(0, (sum, item) => sum + item.amountMinor),
);
