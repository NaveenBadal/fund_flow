import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../theme/ff_theme.dart';
import '../widgets/ff_tab_bar.dart';
import 'activity.dart';
import 'ask.dart';
import 'summary.dart';

/// Which tab is showing.
///
/// Held outside the widget so a pushed page — a transaction, an insight — can
/// send someone to a sibling tab and pop itself, instead of opening a second
/// copy of a tab they already had.
class ShellTab extends Notifier<int> {
  @override
  int build() => 0;

  void set(int value) => state = value;
}

final shellTabProvider = NotifierProvider<ShellTab, int>(ShellTab.new);

/// The three places the app has.
///
/// Everything else — settings, a breakdown, a transaction, a review queue —
/// is reached from one of these and comes back to it. A small, flat map is
/// what makes an app feel like it has nothing hidden in it.
class FFShell extends ConsumerWidget {
  const FFShell({super.key});

  static const _tabs = [
    FFTab(
      label: 'Summary',
      icon: Icons.pie_chart_outline_rounded,
      active: Icons.pie_chart_rounded,
    ),
    FFTab(
      label: 'Activity',
      icon: Icons.receipt_long_outlined,
      active: Icons.receipt_long_rounded,
    ),
    FFTab(
      label: 'Ask',
      icon: Icons.auto_awesome_outlined,
      active: Icons.auto_awesome_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final index = ref.watch(shellTabProvider);
    final review = app.transactions
        .where((t) => t.reviewState == ReviewState.needsReview)
        .length;
    final padding = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: context.ff.groupedBackground,
      // The tab bar keeps its place when the keyboard opens; the screen above
      // it does the moving. A tab bar riding up on the keyboard looks loose.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            // Every screen inside gets the tab bar's height added to its safe
            // area, so content scrolls under the blur and still comes to rest
            // clear of it — without any screen knowing the bar exists.
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: padding.copyWith(
                  bottom: padding.bottom + kFFTabBarHeight,
                ),
              ),
              child: IndexedStack(
                index: index,
                children: const [
                  SummaryScreen(),
                  ActivityScreen(),
                  AskScreen(),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FFTabBar(
              tabs: _tabs,
              index: index,
              badges: {1: review},
              onChanged: ref.read(shellTabProvider.notifier).set,
            ),
          ),
        ],
      ),
    );
  }
}
