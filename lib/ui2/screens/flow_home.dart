import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/transaction.dart';
import '../shell/flow_nav.dart';
import '../shell/flow_shell.dart';
import 'activity_screen.dart';
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
      ),
      activity: const ActivityScreen(),
      review: const ReviewScreen(),
    );
  }

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
      // Without this the sheet keeps its full height when the keyboard opens
      // and the composer — the whole point of the screen — sits underneath it,
      // so you cannot see what you are typing. The editor and connect sheets
      // already inset this way.
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const ChatScreen(),
      ),
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
