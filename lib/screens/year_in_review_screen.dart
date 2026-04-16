import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../providers/expense_provider.dart';

class YearInReviewScreen extends ConsumerStatefulWidget {
  const YearInReviewScreen({super.key, this.year});

  final int? year;

  @override
  ConsumerState<YearInReviewScreen> createState() => _YearInReviewScreenState();
}

class _YearInReviewScreenState extends ConsumerState<YearInReviewScreen> {
  int get _year => widget.year ?? DateTime.now().year;
  final _shareKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final reviewAsync = ref.watch(yearInReviewProvider(_year));
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    final fmtCompact = NumberFormat.compact(locale: 'en_IN');

    return Scaffold(
      appBar: AppBar(
        title: Text('$_year in Review'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _shareCard(context),
            tooltip: 'Share',
          ),
        ],
      ),
      body: reviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final topMerchant = data['topMerchant'] as String?;
          final topMerchantTotal = data['topMerchantTotal'] as double? ?? 0;
          final topCategory = data['topCategory'] as String?;
          final totalSpent = data['totalSpent'] as double? ?? 0;
          final maxSpendDay = data['maxSpendDay'] as String?;
          final maxSpendAmount = data['maxSpendAmount'] as double? ?? 0;
          final zeroSpendDays = data['zeroSpendDays'] as int? ?? 0;
          final activeDays = data['activeDays'] as int? ?? 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
            child: RepaintBoundary(
              key: _shareKey,
              child: Column(
                children: [
                  // Hero year card
                  _WrappedCard(
                    gradient: [const Color(0xFF6750A4), const Color(0xFF9C4DD7)],
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_year',
                          style: theme.textTheme.displayLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Your Year in Review',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Total spent',
                          style: TextStyle(color: Colors.white60, fontSize: 14),
                        ),
                        Text(
                          fmt.format(totalSpent),
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.3, duration: 500.ms),

                  const SizedBox(height: 12),

                  // Top merchant
                  if (topMerchant != null)
                    _WrappedCard(
                      gradient: [const Color(0xFF006874), const Color(0xFF00A3B4)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Top Merchant', style: TextStyle(color: Colors.white60, fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(
                            topMerchant,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            fmt.format(topMerchantTotal),
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 150.ms).slideY(begin: 0.3, duration: 500.ms, delay: 150.ms),

                  const SizedBox(height: 12),

                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: _WrappedCard(
                          gradient: [const Color(0xFF386A20), const Color(0xFF52A030)],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Zero-spend days', style: TextStyle(color: Colors.white60, fontSize: 12)),
                              const SizedBox(height: 8),
                              Text(
                                '$zeroSpendDays',
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text('days', style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _WrappedCard(
                          gradient: [const Color(0xFF7D5260), const Color(0xFFB56576)],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Active days', style: TextStyle(color: Colors.white60, fontSize: 12)),
                              const SizedBox(height: 8),
                              Text(
                                '$activeDays',
                                style: theme.textTheme.displaySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text('days', style: const TextStyle(color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 500.ms, delay: 300.ms),

                  const SizedBox(height: 12),

                  // Most expensive day
                  if (maxSpendDay != null)
                    _WrappedCard(
                      gradient: [const Color(0xFFB71C1C), const Color(0xFFD32F2F)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Most expensive day', style: TextStyle(color: Colors.white60, fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(
                            () {
                              final dt = DateTime.tryParse(maxSpendDay);
                              return dt != null ? DateFormat('EEEE, MMMM d').format(dt) : maxSpendDay;
                            }(),
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            fmt.format(maxSpendAmount),
                            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 450.ms).slideY(begin: 0.3, duration: 500.ms, delay: 450.ms),

                  const SizedBox(height: 12),

                  // Top category
                  if (topCategory != null)
                    _WrappedCard(
                      gradient: [const Color(0xFFF57F17), const Color(0xFFF9A825)],
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Top Category', style: TextStyle(color: Colors.white60, fontSize: 14)),
                          const SizedBox(height: 8),
                          Text(
                            topCategory,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 600.ms).slideY(begin: 0.3, duration: 500.ms, delay: 600.ms),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _shareCard(BuildContext context) async {
    try {
      final boundary = _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/year_in_review_$_year.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          subject: '$_year Expense Wrapped',
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Share failed: $e')));
      }
    }
  }
}

class _WrappedCard extends StatelessWidget {
  const _WrappedCard({required this.gradient, required this.child});

  final List<Color> gradient;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: child,
    );
  }
}
