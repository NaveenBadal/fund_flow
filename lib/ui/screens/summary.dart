import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app_controller.dart';
import '../../domain/insight_engine.dart';
import '../../domain/transaction.dart';
import '../ff_format.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_charts.dart';
import '../widgets/ff_group.dart';
import '../widgets/ff_money.dart';
import '../widgets/ff_notice.dart';
import '../widgets/ff_pressable.dart';
import '../widgets/ff_screen.dart';
import '../widgets/ff_transaction_row.dart';
import 'analysis.dart';
import 'ask.dart';
import 'review.dart';
import 'settings/settings.dart';
import 'shell.dart';
import 'transaction_detail.dart';
import 'transaction_editor.dart';

/// Where the app opens.
///
/// One figure answers the only question most people have — how much have I
/// spent this month — and everything below it is either something that needs
/// deciding or a way to go deeper. Nothing is here merely because there was
/// room for it.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  int _offset = 0;
  int? _scrubbed;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    final c = context.ff;

    final today = DateTime.now();
    final period = DateTime(today.year, today.month + _offset);
    final days = DateUtils.getDaysInMonth(period.year, period.month);
    final upTo = _offset == 0
        ? DateTime(period.year, period.month, today.day, 23, 59)
        : DateTime(period.year, period.month, days, 23, 59);

    final month = app.transactions
        .where(
          (t) =>
              t.occurredAt.year == period.year &&
              t.occurredAt.month == period.month,
        )
        .toList();
    final currency = dominantCurrency(month, app.preferences.currency);
    final out = sumOf(month, TransactionDirection.outgoing, currency);
    final incoming = sumOf(month, TransactionDirection.incoming, currency);
    final daily = dailyTotals(month, currency, days);
    final baseline = previousComparable(app.transactions, upTo, currency);
    final change = baseline == 0 ? null : (out - baseline) / baseline;
    final hidden = app.preferences.hideAmounts;

    final review = app.transactions
        .where((t) => t.reviewState == ReviewState.needsReview)
        .length;
    final insights = InsightEngine.insights(app.transactions, upTo, limit: 2);
    final recent = [...app.transactions]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return FFScreen(
      title: 'Summary',
      trailing: [
        FFBarButton(
          icon: hidden
              ? Icons.visibility_off_rounded
              : Icons.visibility_rounded,
          tooltip: hidden ? 'Show amounts' : 'Hide amounts',
          onTap: () => controller.updatePreferences(
            app.preferences.copyWith(hideAmounts: !hidden),
          ),
        ),
        FFBarButton(
          icon: Icons.settings_rounded,
          tooltip: 'Settings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: _MonthCard(
            period: period,
            canGoForward: _offset < 0,
            onBack: () => setState(() {
              _offset--;
              _scrubbed = null;
            }),
            onForward: () => setState(() {
              _offset++;
              _scrubbed = null;
            }),
            spent: out,
            currency: currency,
            hidden: hidden,
            change: change,
            daily: daily,
            count: month.length,
            scrubbed: _scrubbed,
            emphasis: _offset == 0 ? today.day - 1 : null,
            onScrub: (value) => setState(() => _scrubbed = value),
            onOpenAnalysis: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AnalysisScreen(period: period),
              ),
            ),
          ),
        ),
        if (review > 0)
          SliverToBoxAdapter(
            child: FFNotice(
              icon: Icons.error_rounded,
              tone: FFNoticeTone.attention,
              title: review == 1
                  ? '1 transaction needs a look'
                  : '$review transactions need a look',
              message: 'Captured automatically, but worth confirming.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ReviewScreen()),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: FFGroup(
            children: [
              FFRow(
                title: 'Received',
                icon: Icons.south_west_rounded,
                iconColor: c.greenFill,
                chevron: false,
                trailing: FFMoney(
                  minor: incoming,
                  currency: currency,
                  hidden: hidden,
                  style: FFText.body,
                  color: c.secondaryLabel,
                ),
              ),
              FFRow(
                title: 'Net this month',
                icon: Icons.calculate_rounded,
                iconColor: c.tint,
                chevron: false,
                trailing: FFMoney(
                  minor: incoming - out,
                  currency: currency,
                  hidden: hidden,
                  style: FFText.body.copyWith(fontWeight: FontWeight.w600),
                  color: incoming - out >= 0 ? c.green : c.label,
                ),
              ),
            ],
          ),
        ),
        if (insights.isNotEmpty)
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const FFHeading('Worth knowing'),
                FFGroup(
                  separatorIndent: 57,
                  children: [
                    for (final insight in insights)
                      FFRow(
                        title: insight.title,
                        subtitle: insight.detail,
                        icon: switch (insight.kind) {
                          InsightKind.duplicate => Icons.copy_all_rounded,
                          InsightKind.anomaly => Icons.trending_up_rounded,
                          InsightKind.pace => Icons.speed_rounded,
                        },
                        iconColor: switch (insight.kind) {
                          InsightKind.duplicate => c.orangeFill,
                          InsightKind.anomaly => c.redFill,
                          InsightKind.pace => c.tint,
                        },
                        onTap: () =>
                            openAsk(context, ref, seed: insight.question),
                      ),
                  ],
                ),
              ],
            ),
          ),
        if (recent.isEmpty)
          SliverToBoxAdapter(
            child: FFEmpty(
              icon: Icons.inbox_rounded,
              title: 'No transactions yet',
              message:
                  'Fund Flow reads payment messages and turns them into a '
                  'private record. Nothing leaves this device without you.',
              action: 'Check my messages',
              onAction: controller.importMessages,
              secondaryAction: 'Add one manually',
              onSecondaryAction: () => showTransactionEditor(context),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FFHeading(
                  'Recent',
                  trailing: 'See all',
                  onTrailing: () => ref.read(shellTabProvider.notifier).set(1),
                ),
                FFGroup(
                  separatorIndent: 64,
                  children: [
                    for (final item in recent.take(5))
                      FFTransactionRow(
                        item: item,
                        hidden: hidden,
                        showDay: true,
                        onTap: () => openTransaction(context, item),
                      ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({
    required this.period,
    required this.canGoForward,
    required this.onBack,
    required this.onForward,
    required this.spent,
    required this.currency,
    required this.hidden,
    required this.change,
    required this.daily,
    required this.count,
    required this.scrubbed,
    required this.emphasis,
    required this.onScrub,
    required this.onOpenAnalysis,
  });

  final DateTime period;
  final bool canGoForward;
  final VoidCallback onBack;
  final VoidCallback onForward;
  final int spent;
  final String currency;
  final bool hidden;
  final double? change;
  final List<int> daily;
  final int count;
  final int? scrubbed;
  final int? emphasis;
  final ValueChanged<int?> onScrub;
  final VoidCallback onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final scrubbing = scrubbed != null;
    // A chart of thirty-one zeroes is a dashed rule pretending to be
    // information. When there is nothing to plot, say so and take the space
    // back rather than leaving a hole where a shape should be.
    final blank = daily.every((value) => value == 0);
    final caption = scrubbing
        ? DateFormat(
            'EEEE d MMMM',
          ).format(DateTime(period.year, period.month, scrubbed! + 1))
        : 'Spent in ${DateFormat('MMMM').format(period)}';
    final amount = scrubbing ? daily[scrubbed!] : spent;

    final (String note, Color noteColor) = scrubbing
        ? (
            daily[scrubbed!] == 0 ? 'Nothing spent that day' : 'That day',
            c.secondaryLabel,
          )
        : count == 0
        ? ('Nothing recorded here yet', c.secondaryLabel)
        : change == null
        ? ('$count transactions captured', c.secondaryLabel)
        : (
            '${change! > 0 ? 'Up' : 'Down'} ${(change!.abs() * 100).round()}% '
                'on the same point last month',
            change! > 0 ? c.orange : c.green,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        FFSpace.gutter,
        0,
        FFSpace.gutter,
        FFSpace.xl,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(FFRadius.group),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: Row(
                children: [
                  _Step(
                    icon: Icons.chevron_left_rounded,
                    label: 'Previous month',
                    onTap: onBack,
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        DateFormat('MMMM yyyy').format(period),
                        textAlign: TextAlign.center,
                        style: FFText.subhead.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  _Step(
                    icon: Icons.chevron_right_rounded,
                    label: 'Next month',
                    onTap: canGoForward ? onForward : null,
                  ),
                ],
              ),
            ),
            const FFSeparator(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                FFSpace.lg,
                FFSpace.lg,
                FFSpace.lg,
                FFSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    style: FFText.subhead.copyWith(color: c.secondaryLabel),
                  ),
                  const SizedBox(height: 4),
                  FFMoney(
                    minor: amount,
                    currency: currency,
                    hidden: hidden,
                    style: FFText.money,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    note,
                    maxLines: 2,
                    style: FFText.subhead.copyWith(color: noteColor),
                  ),
                  if (!blank) ...[
                    const SizedBox(height: FFSpace.lg),
                    FFBars(
                      values: daily,
                      selected: scrubbed,
                      emphasis: emphasis,
                      onSelected: onScrub,
                    ),
                    const SizedBox(height: FFSpace.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final label in [
                          '1',
                          '${daily.length ~/ 2}',
                          '${daily.length}',
                        ])
                          Text(
                            label,
                            style: FFText.caption2.copyWith(
                              color: c.tertiaryLabel,
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (!blank) ...[
              const FFSeparator(indent: FFSpace.lg),
              FFRow(
                title: 'Breakdown',
                subtitle: 'Categories, merchants and daily rhythm',
                onTap: onOpenAnalysis,
                minHeight: 50,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FFPressable(
    onTap: onTap,
    semanticLabel: label,
    child: SizedBox(
      width: 48,
      height: 44,
      child: Icon(
        icon,
        size: 24,
        color: onTap == null ? context.ff.quaternaryLabel : context.ff.tint,
      ),
    ),
  );
}
