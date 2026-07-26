import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../shell/flow_nav.dart';
import '../components/flow_sheet_inset.dart';
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
  FlowDestination _destination = FlowDestination.today;

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
        FlowDestination.today => 'this month',
        FlowDestination.activity => 'your activity',
        FlowDestination.review => 'what needs review',
      },
      onOpenChat: _openChat,
      today: TodayScreen(
        onReview: () => setState(() => _destination = FlowDestination.review),
        onOpenSettings: _openSettings,
        onOpenAnalytics: _openAnalytics,
        onAsk: _askInChat,
      ),
      activity: const ActivityScreen(),
      review: const ReviewScreen(),
    );
  }

  /// Opens the conversation already asking [question].
  ///
  /// What Today notices is deliberately shallow — it states the finding and
  /// nothing more — so the card hands straight to the agent for the why
  /// rather than making someone retype what they just tapped.
  Future<void> _askInChat(String question) async {
    final chat = _openChat();
    await ref.read(appControllerProvider.notifier).ask(question);
    await chat;
  }

  Future<void> _openAnalytics() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .5,
      maxChildSize: .96,
      builder: (context, controller) => PrimaryScrollController(
        controller: controller,
        child: const AnalyticsScreen(),
      ),
    ),
  );

  /// Chat opens over whatever is on screen and returns to it. Conversation is
  /// something brought to the current context rather than a place navigated
  /// to and back from.
  Future<void> _openChat() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .94,
      minChildSize: .5,
      maxChildSize: .96,
      builder: (context, controller) =>
          const FlowSheetInset(child: ChatScreen()),
    ),
  );

  Future<void> _openSettings() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheet) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .5,
      maxChildSize: .96,
      builder: (context, controller) => PrimaryScrollController(
        controller: controller,
        child: const SettingsScreen(),
      ),
    ),
  );
}
