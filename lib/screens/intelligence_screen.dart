import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/command_ui.dart';
import '../widgets/money_chat_sheet.dart';
import 'action_inbox_screen.dart';

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
      eyebrow: 'The patterns behind your choices',
      title: 'Financial oracle',
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 12),
          child: ActionInboxButton(),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
            child: Material(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(34),
              child: InkWell(
                borderRadius: BorderRadius.circular(34),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => const MoneyChatSheet(),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 32,
                        color: Color(0xFFC7FF4A),
                      ),
                      SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ASK YOUR MONEY ANYTHING',
                              style: TextStyle(
                                color: Color(0xFFC7FF4A),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.3,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Start a private reasoning session',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Every answer is grounded in your actual records.',
                              style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: Colors.white54),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
          const SliverToBoxAdapter(
            child: SectionLabel('Signals worth interrupting you'),
          ),
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
      ],
    );
  }
}
