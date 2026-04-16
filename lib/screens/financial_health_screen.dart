import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/expense_provider.dart';

class FinancialHealthScreen extends ConsumerWidget {
  const FinancialHealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthAsync = ref.watch(financialHealthScoreProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Financial Health')),
      body: healthAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (health) {
          final gradeColor = _gradeColor(health.grade, scheme);

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: LinearGradient(
                          colors: [
                            gradeColor.withValues(alpha: 0.15),
                            gradeColor.withValues(alpha: 0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Ring chart
                          SizedBox(
                            height: 200,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                PieChart(
                                  PieChartData(
                                    startDegreeOffset: -90,
                                    sectionsSpace: 0,
                                    centerSpaceRadius: 70,
                                    sections: [
                                      PieChartSectionData(
                                        value: health.score.toDouble(),
                                        color: gradeColor,
                                        radius: 20,
                                        title: '',
                                      ),
                                      PieChartSectionData(
                                        value: (100 - health.score).toDouble(),
                                        color: scheme.surfaceContainerHighest,
                                        radius: 16,
                                        title: '',
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${health.score}',
                                      style: theme.textTheme.displaySmall?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: gradeColor,
                                      ),
                                    )
                                        .animate()
                                        .fadeIn(duration: 600.ms)
                                        .scale(begin: const Offset(0.5, 0.5), duration: 600.ms, curve: Curves.elasticOut),
                                    Text(
                                      health.gradeLabel,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        color: gradeColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Grade ${health.grade}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: gradeColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Sub-scores
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
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
                            'Score breakdown',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 20),
                          _ScoreRow(
                            label: 'Savings rate',
                            value: health.savingsRate,
                            description:
                                '${(health.savingsRate * 100).toStringAsFixed(1)}% of income saved',
                            weight: '40%',
                          ),
                          const SizedBox(height: 16),
                          _ScoreRow(
                            label: 'Budget adherence',
                            value: health.budgetAdherence,
                            description:
                                '${(health.budgetAdherence * 100).toStringAsFixed(0)}% of categories within budget',
                            weight: '35%',
                          ),
                          const SizedBox(height: 16),
                          _ScoreRow(
                            label: 'Spending trend',
                            value: health.trendScore,
                            description: health.trendScore >= 0.5
                                ? 'Spending is trending down'
                                : 'Spending increased vs last month',
                            weight: '25%',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // How it's calculated
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                sliver: SliverToBoxAdapter(
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    child: Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                        title: Text(
                          'How is this calculated?',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _FormulaRow('Savings rate (40%)', '(Income − Expense) ÷ Income'),
                                _FormulaRow('Budget adherence (35%)',
                                    '% of categories that stayed within their monthly limit'),
                                _FormulaRow('Spending trend (25%)',
                                    'Current month vs previous month expense'),
                                const SizedBox(height: 8),
                                Text(
                                  'Score = (Savings × 40) + (Adherence × 35) + (Trend × 25)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontStyle: FontStyle.italic,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  Color _gradeColor(String grade, ColorScheme scheme) {
    return switch (grade) {
      'A' => Colors.green.shade600,
      'B' => Colors.teal.shade500,
      'C' => Colors.amber.shade700,
      'D' => Colors.orange.shade700,
      _ => scheme.error,
    };
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.description,
    required this.weight,
  });

  final String label;
  final double value;
  final String description;
  final String weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Color barColor;
    if (value >= 0.7) {
      barColor = Colors.green.shade600;
    } else if (value >= 0.4) {
      barColor = Colors.amber.shade700;
    } else {
      barColor = scheme.error;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(
              weight,
              style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 8),
            Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _FormulaRow extends StatelessWidget {
  const _FormulaRow(this.label, this.formula);

  final String label;
  final String formula;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(formula, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
