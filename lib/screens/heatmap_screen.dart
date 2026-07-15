import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';

class HeatmapScreen extends ConsumerWidget {
  const HeatmapScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(heatmapDataProvider);
    final hidden = ref.watch(privateModeProvider);
    final currency = ref.watch(preferredCurrencyProvider);
    return CommandScaffold(
      eyebrow: 'Time leaves a financial fingerprint',
      title: 'Money rhythm',
      slivers: [
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SliverFillRemaining(
            child: StatePanel(
              icon: Icons.calendar_month_outlined,
              title: 'Calendar unavailable',
              message: '$error',
            ),
          ),
          data: (data) {
            if (data.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: StatePanel(
                  icon: Icons.calendar_month_rounded,
                  title: 'No rhythm yet',
                  message:
                      'Your daily pattern will emerge as movements enter the ledger.',
                ),
              );
            }
            final maximum = data.values.reduce(max);
            final total = data.values.fold<double>(
              0,
              (sum, value) => sum + value,
            );
            final active = data.values.where((value) => value > 0).length;
            final top = data.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            return SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 125,
                            child: MetricTile(
                              label: 'Tracked year',
                              value: hidden
                                  ? maskAmount(currency)
                                  : formatAmount(total, currency),
                              icon: Icons.calendar_view_month_rounded,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 125,
                            child: MetricTile(
                              label: 'Active days',
                              value: '$active',
                              icon: Icons.brightness_5_rounded,
                              caption: '${365 - active} no-spend days',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SectionLabel('Sixteen-week pulse'),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF090D16),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(38),
                          bottomLeft: Radius.circular(38),
                          bottomRight: Radius.circular(8),
                        ),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: _CalendarGrid(
                        data: data,
                        maximum: maximum,
                        currency: currency,
                        hidden: hidden,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SectionLabel('Highest-spend days'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList.separated(
                    itemCount: min(6, top.length),
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .4),
                    ),
                    itemBuilder: (context, index) {
                      final item = top[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 5),
                        leading: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: .12),
                            borderRadius: AppRadius.all(14),
                          ),
                          child: Center(
                            child: Text(
                              '${item.key.day}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          DateFormat('EEEE').format(item.key),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          DateFormat('d MMMM yyyy').format(item.key),
                        ),
                        trailing: Text(
                          hidden
                              ? maskAmount(currency)
                              : formatAmount(item.value, currency),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.data,
    required this.maximum,
    required this.currency,
    required this.hidden,
  });
  final Map<DateTime, double> data;
  final double maximum;
  final String currency;
  final bool hidden;
  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final days = [
      for (var offset = 111; offset >= 0; offset--)
        today.subtract(Duration(days: offset)),
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'QUIET',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onInverseSurface.withValues(alpha: .55),
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            for (var i = 1; i <= 4; i++)
              Container(
                width: 12,
                height: 12,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: i / 4),
                  borderRadius: AppRadius.all(3),
                ),
              ),
            const SizedBox(width: 7),
            Text(
              'BUSY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onInverseSurface.withValues(alpha: .55),
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 16,
            mainAxisSpacing: 5,
            crossAxisSpacing: 5,
          ),
          itemCount: days.length,
          itemBuilder: (context, index) {
            final day = days[index];
            final amount = data[day] ?? 0;
            final intensity = maximum == 0
                ? 0.0
                : (amount / maximum).clamp(.08, 1.0);
            return Tooltip(
              message:
                  '${DateFormat('d MMM').format(day)} · ${hidden ? maskAmount(currency) : formatAmount(amount, currency)}',
              child: Container(
                decoration: BoxDecoration(
                  color: amount == 0
                      ? scheme.onInverseSurface.withValues(alpha: .08)
                      : scheme.primary.withValues(alpha: intensity),
                  borderRadius: AppRadius.all(4),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
