import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../app/app_state.dart';
import '../../app/home_snapshot.dart';
import '../../design/flux.dart';
import '../activity/activity_filter.dart';
import '../activity/review_page.dart';
import '../common/formatting.dart';
import '../settings/settings_page.dart';
import '../shell/shell.dart';
import 'flow_card.dart';
import 'home_cards.dart';

/// Home: what your money is doing, with nothing typed and nothing asked.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final snapshot = ref.watch(homeSnapshotProvider);
    final money = ref.watch(moneyProvider);
    final importStatus = app?.importStatus ?? const ImportStatus();

    void filterTo({String? category, ReviewOnly review = ReviewOnly.any}) {
      ref.read(activityFilterProvider.notifier).state = ActivityFilter(
        category: category,
        review: review,
      );
      ref.read(shellTabProvider.notifier).state = 1;
    }

    return FluxPage(
      title: 'Home',
      bottomInset: shellBottomInset(context),
      onRefresh: () =>
          ref.read(appControllerProvider.notifier).refreshFromSources(),
      actions: [
        FluxIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onPressed: () => fluxPush(context, (context) => const SettingsPage()),
        ),
      ],
      slivers: [
        if (importStatus.working)
          FluxSliverPadding(
            top: FluxSpace.x2,
            child: _ImportProgress(status: importStatus),
          )
        else if (importStatus.retryable)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: FluxSpace.x2),
              child: FluxBanner(
                tone: FluxBannerTone.attention,
                title: 'Message import stopped',
                message:
                    importStatus.message ??
                    'Nothing was lost. Picking up where it left off is safe.',
                icon: Icons.sms_failed_outlined,
                actionLabel: 'Try again',
                onAction: () =>
                    ref.read(appControllerProvider.notifier).importMessages(),
              ),
            ),
          ),

        if (app?.aiConnection == AiConnection.disconnected &&
            (app?.preferences.onboardingComplete ?? false))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: FluxSpace.x2),
              child: FluxBanner(
                tone: FluxBannerTone.ai,
                title: 'Intelligence is not connected',
                message:
                    'Your records are all here. Reading new messages and '
                    'answering questions both need a provider.',
                icon: Icons.link_off_rounded,
                actionLabel: 'Connect',
                onAction: () =>
                    fluxPush(context, (context) => const SettingsPage()),
              ),
            ),
          ),

        if (snapshot.empty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: FluxEmpty(
              icon: Icons.inbox_outlined,
              title: 'No transactions yet',
              message:
                  'Fund Flow reads the transaction messages your bank already '
                  'sends. Run an import and this fills itself in.',
              actionLabel: 'Read my messages',
              onAction: () =>
                  ref.read(appControllerProvider.notifier).importMessages(),
            ),
          )
        else ...[
          FluxSliverPadding(
            top: FluxSpace.x2,
            child: FlowCard(snapshot: snapshot),
          ),
          FluxSliverPadding(
            child: AttentionStrip(
              snapshot: snapshot,
              onReview: () =>
                  fluxPush(context, (context) => const ReviewPage()),
              onDuplicates: () => openAsk(
                context,
                ref,
                seed: 'Which charges look like duplicates?',
              ),
              onBudget: (status) => filterTo(category: status.category),
            ),
          ),
          FluxSliverPadding(
            child: BreakdownCard(
              snapshot: snapshot,
              onCategory: (category) => filterTo(category: category),
            ),
          ),
          FluxSliverPadding(child: BudgetsCard(snapshot: snapshot)),
          FluxSliverPadding(child: DailyCard(snapshot: snapshot)),
          FluxSliverPadding(child: UpcomingCard(snapshot: snapshot)),
          if (snapshot.insights.isNotEmpty)
            FluxSliverPadding(
              child: InsightCard(
                insight: snapshot.insights.first,
                onAsk: (question) => openAsk(context, ref, seed: question),
              ),
            ),
          FluxSliverPadding(
            top: FluxSpace.x6,
            child: Text(
              'Everything above is calculated on this device from '
              '${snapshot.month.transactionCount} '
              '${snapshot.month.transactionCount == 1 ? 'record' : 'records'} '
              'in ${money.hidden ? 'your currency' : snapshot.currency} '
              'this month.',
              style: FluxType.caption.copyWith(color: palette.textFaint),
            ),
          ),
        ],
      ],
    );
  }
}

/// Import progress, shown while it runs.
///
/// Counts rather than a spinner: an import that reads 900 messages takes
/// minutes, and a bare spinner for minutes is indistinguishable from a hang.
class _ImportProgress extends StatelessWidget {
  const _ImportProgress({required this.status});
  final ImportStatus status;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final label = switch (status.phase) {
      ImportPhase.requestingPermission => 'Asking for permission',
      ImportPhase.reading => 'Reading messages',
      ImportPhase.understanding => 'Understanding messages',
      ImportPhase.paused => 'Paused',
      _ => 'Working',
    };
    return FluxCard(
      border: palette.iris.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: FluxType.subtitle.copyWith(color: palette.text),
                ),
              ),
              Text(
                '${status.imported} found',
                style: FluxType.moneySmall.copyWith(color: palette.iris),
              ),
            ],
          ),
          const SizedBox(height: FluxSpace.x2),
          Text(
            '${status.checked} checked · ${status.skipped} not money',
            style: FluxType.caption.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: FluxSpace.x4),
          const _IndeterminateBar(),
        ],
      ),
    );
  }
}

class _IndeterminateBar extends StatefulWidget {
  const _IndeterminateBar();

  @override
  State<_IndeterminateBar> createState() => _IndeterminateBarState();
}

class _IndeterminateBarState extends State<_IndeterminateBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 3,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: palette.surfaceHighest)),
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => FractionallySizedBox(
                widthFactor: 0.35,
                alignment: Alignment(-1 + 2 * _controller.value * 1.55, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: FluxPalette.ai),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
