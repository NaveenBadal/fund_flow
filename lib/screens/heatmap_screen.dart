import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';

class HeatmapScreen extends ConsumerWidget {
  const HeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final heatmapAsync = ref.watch(heatmapDataProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending Heatmap'),
      ),
      body: heatmapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          if (data.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined, size: 64, color: scheme.outline),
                  const SizedBox(height: 16),
                  Text('No data yet', style: theme.textTheme.titleLarge),
                ],
              ),
            );
          }

          final maxAmount = data.values.reduce(max);
          final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Last 365 days',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Each square = one day. Darker = more spending.',
                            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 20),
                          _HeatmapGrid(data: data, maxAmount: maxAmount),
                          const SizedBox(height: 12),
                          _Legend(maxAmount: maxAmount),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Top spend days',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          ...(data.entries.toList()
                                ..sort((a, b) => b.value.compareTo(a.value)))
                              .take(5)
                              .map((e) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: _intensityColor(
                                                e.value, maxAmount, scheme.primary),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            DateFormat('EEEE, MMM d, yyyy').format(e.key),
                                            style: theme.textTheme.bodyMedium,
                                          ),
                                        ),
                                        Text(
                                          fmt.format(e.value),
                                          style: theme.textTheme.titleSmall?.copyWith(
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  )),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 88)),
            ],
          );
        },
      ),
    );
  }
}

class _HeatmapGrid extends StatefulWidget {
  const _HeatmapGrid({required this.data, required this.maxAmount});

  final Map<DateTime, double> data;
  final double maxAmount;

  @override
  State<_HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<_HeatmapGrid> {
  DateTime? _hoveredDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

    final now = DateTime.now();
    final startDay = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 364));

    // Build weeks (columns), each with up to 7 days
    final weeks = <List<DateTime?>>[];
    final firstDayOfWeek = startDay.subtract(Duration(days: startDay.weekday % 7));
    var current = firstDayOfWeek;

    while (current.isBefore(now.add(const Duration(days: 7)))) {
      final week = <DateTime?>[];
      for (int d = 0; d < 7; d++) {
        final day = current.add(Duration(days: d));
        if (day.isBefore(startDay) || day.isAfter(now)) {
          week.add(null);
        } else {
          week.add(DateTime(day.year, day.month, day.day));
        }
      }
      weeks.add(week);
      current = current.add(const Duration(days: 7));
    }

    // Month labels
    final monthLabels = <int, String>{};
    for (int w = 0; w < weeks.length; w++) {
      for (final day in weeks[w]) {
        if (day != null && day.day <= 7) {
          monthLabels[w] = DateFormat('MMM').format(day);
          break;
        }
      }
    }

    const cellSize = 12.0;
    const cellGap = 2.0;

    return LayoutBuilder(builder: (context, constraints) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month labels row
          SizedBox(
            height: 20,
            child: Row(
              children: weeks.asMap().entries.map((e) {
                final label = monthLabels[e.key];
                return SizedBox(
                  width: cellSize + cellGap,
                  child: label != null
                      ? Text(label,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontSize: 9,
                              ))
                      : const SizedBox.shrink(),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          // Grid
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: weeks.map((week) {
              return Padding(
                padding: const EdgeInsets.only(right: cellGap),
                child: Column(
                  children: week.map((day) {
                    if (day == null) {
                      return SizedBox(width: cellSize, height: cellSize + cellGap);
                    }
                    final amount = widget.data[day] ?? 0;
                    final color = amount > 0
                        ? _intensityColor(amount, widget.maxAmount, scheme.primary)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.4);

                    return GestureDetector(
                      onTap: () {
                        setState(() => _hoveredDay = day);
                        if (amount > 0) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                '${DateFormat('MMM d, yyyy').format(day)}: ${fmt.format(amount)}'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: cellGap),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                            border: _hoveredDay == day
                                ? Border.all(color: scheme.primary, width: 1.5)
                                : null,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ),
          if (_hoveredDay != null) ...[
            const SizedBox(height: 8),
            Text(
              '${DateFormat('EEEE, MMMM d, yyyy').format(_hoveredDay!)}: ${fmt.format(widget.data[_hoveredDay!] ?? 0)}',
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      );
    });
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.maxAmount});

  final double maxAmount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fmt = NumberFormat.compact(locale: 'en_IN');

    return Row(
      children: [
        Text('Less', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(width: 6),
        ...List.generate(5, (i) {
          final intensity = i / 4;
          return Padding(
            padding: const EdgeInsets.only(right: 3),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: intensity == 0
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
                    : _intensityColor(maxAmount * intensity, maxAmount, scheme.primary),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
        const SizedBox(width: 6),
        Text('${fmt.format(maxAmount)}+',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

Color _intensityColor(double amount, double maxAmount, Color primary) {
  if (maxAmount == 0) return primary.withValues(alpha: 0.1);
  final intensity = (amount / maxAmount).clamp(0.1, 1.0);
  return primary.withValues(alpha: intensity);
}
