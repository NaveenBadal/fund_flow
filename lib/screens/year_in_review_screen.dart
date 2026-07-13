import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';

class YearInReviewScreen extends ConsumerStatefulWidget {
  const YearInReviewScreen({super.key, this.year});
  final int? year;
  @override
  ConsumerState<YearInReviewScreen> createState() => _YearInReviewScreenState();
}

class _YearInReviewScreenState extends ConsumerState<YearInReviewScreen> {
  late int _year = widget.year ?? DateTime.now().year;
  final _shareKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(yearInReviewProvider(_year));
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('Year story'),
            actions: [
              IconButton(
                onPressed: _share,
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (
                    var year = DateTime.now().year - 2;
                    year <= DateTime.now().year;
                    year++
                  )
                    ButtonSegment(value: year, label: Text('$year')),
                ],
                selected: {_year},
                onSelectionChanged: (value) =>
                    setState(() => _year = value.first),
              ),
            ),
          ),
          async.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: StatePanel(
                icon: Icons.auto_awesome_rounded,
                title: 'Story unavailable',
                message: '$error',
              ),
            ),
            data: (data) => SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
              sliver: SliverToBoxAdapter(
                child: RepaintBoundary(
                  key: _shareKey,
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(26),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.inverseSurface,
                            borderRadius: AppRadius.all(36),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_year',
                                style: Theme.of(context).textTheme.displayLarge
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -2,
                                    ),
                              ),
                              Text(
                                'A year measured in choices.',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onInverseSurface,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 28),
                              Text(
                                'TOTAL SPENT',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onInverseSurface
                                          .withValues(alpha: .55),
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                formatAmount(
                                  (data['totalSpent'] as num?)?.toDouble() ?? 0,
                                  'INR',
                                ),
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onInverseSurface,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _StoryTile(
                                label: 'NO-SPEND DAYS',
                                value: '${data['zeroSpendDays'] ?? 0}',
                                caption: 'quiet days',
                                color: context.finance.income,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _StoryTile(
                                label: 'ACTIVE DAYS',
                                value: '${data['activeDays'] ?? 0}',
                                caption: 'days with movement',
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (data['topMerchant'] != null)
                          _Statement(
                            kicker: 'MOST VISITED',
                            title: data['topMerchant'] as String,
                            detail: formatAmount(
                              (data['topMerchantTotal'] as num?)?.toDouble() ??
                                  0,
                              'INR',
                            ),
                            icon: Icons.storefront_rounded,
                          ),
                        const SizedBox(height: 12),
                        if (data['topCategory'] != null)
                          _Statement(
                            kicker: 'BIGGEST THEME',
                            title: data['topCategory'] as String,
                            detail: 'Your leading spending category',
                            icon: Icons.category_rounded,
                          ),
                        const SizedBox(height: 12),
                        if (data['maxSpendDay'] != null)
                          _Statement(
                            kicker: 'THE BIG DAY',
                            title: _day(data['maxSpendDay'] as String),
                            detail: formatAmount(
                              (data['maxSpendAmount'] as num?)?.toDouble() ?? 0,
                              'INR',
                            ),
                            icon: Icons.local_fire_department_rounded,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _day(String raw) {
    final date = DateTime.tryParse(raw);
    return date == null ? raw : DateFormat('EEEE, d MMMM').format(date);
  }

  Future<void> _share() async {
    try {
      final boundary =
          _shareKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File(
        '${(await getTemporaryDirectory()).path}/money_story_$_year.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: 'My $_year money story',
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Share failed: $error')));
      }
    }
  }
}

class _StoryTile extends StatelessWidget {
  const _StoryTile({
    required this.label,
    required this.value,
    required this.caption,
    required this.color,
  });
  final String label, value, caption;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    height: 150,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: AppRadius.all(AppRadius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        Text(caption, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

class _Statement extends StatelessWidget {
  const _Statement({
    required this.kicker,
    required this.title,
    required this.detail,
    required this.icon,
  });
  final String kicker, title, detail;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.all(AppRadius.lg),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .45),
      ),
    ),
    child: Row(
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                kicker,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
