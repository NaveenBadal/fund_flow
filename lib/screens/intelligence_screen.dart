import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/command_ui.dart';
import 'analytics_screen.dart';
import 'financial_health_screen.dart';
import 'heatmap_screen.dart';
import 'year_in_review_screen.dart';

class IntelligenceScreen extends ConsumerWidget {
  const IntelligenceScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights =
        ref.watch(spendingInsightsProvider).asData?.value ?? const [];
    final anomalies =
        ref.watch(anomalyAlertsProvider).asData?.value ?? const [];
    final health = ref.watch(financialHealthScoreProvider).asData?.value;
    return CommandScaffold(
      eyebrow: 'Patterns, explained',
      title: 'Intelligence',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.inverseSurface,
                borderRadius: AppRadius.all(AppRadius.xxl),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FINANCIAL PULSE',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onInverseSurface
                                    .withValues(alpha: .6),
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          health == null
                              ? 'Reading your patterns…'
                              : '${health.score}/100',
                          style: Theme.of(context).textTheme.headlineLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onInverseSurface,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          anomalies.isEmpty
                              ? 'Nothing unusual needs attention.'
                              : '${anomalies.length} unusual pattern${anomalies.length == 1 ? '' : 's'} detected.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onInverseSurface
                                    .withValues(alpha: .72),
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.graphic_eq_rounded,
                    size: 46,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (insights.isNotEmpty) ...[
          const SliverToBoxAdapter(child: SectionLabel('Worth knowing')),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 126,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: insights.take(4).length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final insight = insights[index];
                  return Container(
                    width: 245,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: AppRadius.all(AppRadius.lg),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outlineVariant.withValues(alpha: .45),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          insight.icon,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const Spacer(),
                        Text(
                          insight.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          insight.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SectionLabel('Explore')),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.12,
            children: [
              _Explore(
                title: 'Trends',
                caption: 'Charts and comparisons',
                icon: Icons.show_chart_rounded,
                onTap: () => _push(context, const AnalyticsScreen()),
              ),
              _Explore(
                title: 'Health',
                caption: 'Score and guidance',
                icon: Icons.favorite_outline_rounded,
                onTap: () => _push(context, const FinancialHealthScreen()),
              ),
              _Explore(
                title: 'Calendar',
                caption: 'Daily spending rhythm',
                icon: Icons.calendar_view_month_rounded,
                onTap: () => _push(context, const HeatmapScreen()),
              ),
              _Explore(
                title: 'Year story',
                caption: 'Your annual review',
                icon: Icons.auto_awesome_rounded,
                onTap: () => _push(context, const YearInReviewScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _Explore extends StatelessWidget {
  const _Explore({
    required this.title,
    required this.caption,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String caption;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: AppRadius.all(AppRadius.lg),
    child: InkWell(
      borderRadius: AppRadius.all(AppRadius.lg),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const Spacer(),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 3),
            Text(
              caption,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
