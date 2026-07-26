import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../shell/flow_nav.dart';
import '../shell/flow_shell.dart';
import 'activity_screen.dart';
import 'analytics_screen.dart';
import 'chat_screen.dart';
import 'review_screen.dart';
import 'settings_screen.dart';
import 'today_screen.dart';

/// Wires the destinations into the shell.
class FlowHome extends ConsumerStatefulWidget {
  const FlowHome({super.key});

  @override
  ConsumerState<FlowHome> createState() => _FlowHomeState();
}

class _FlowHomeState extends ConsumerState<FlowHome> {
  FlowDestination _destination = FlowDestination.home;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final review = app.transactions
        .where((item) => item.reviewState == ReviewState.needsReview)
        .length;

    return FlowShell(
      destination: _destination,
      onDestinationChanged: (value) => setState(() => _destination = value),
      reviewCount: review,
      composerBusy: app.asking,
      composerHint: switch (_destination) {
        FlowDestination.home => 'this month',
        FlowDestination.activity => 'your activity',
        FlowDestination.ask => 'your money',
      },
      onOpenChat: () => setState(() => _destination = FlowDestination.ask),
      today: TodayScreen(
        onReview: _openReview,
        onOpenSettings: _openSettings,
        onOpenAnalytics: _openAnalytics,
        onAsk: _askInChat,
      ),
      activity: const ActivityScreen(),
      review: const ChatScreen(),
    );
  }

  /// Opens the conversation already asking [question].
  ///
  /// What Today notices is deliberately shallow — it states the finding and
  /// nothing more — so the card hands straight to the agent for the why
  /// rather than making someone retype what they just tapped.
  Future<void> _askInChat(String question) async {
    setState(() => _destination = FlowDestination.ask);
    await ref.read(appControllerProvider.notifier).ask(question);
  }

  Future<void> _openAnalytics() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SafeArea(child: AnalyticsScreen())),
    ),
  );

  Future<void> _openReview() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SafeArea(child: ReviewScreen())),
    ),
  );

  Future<void> _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: SafeArea(child: SettingsScreen())),
    ),
  );
}
