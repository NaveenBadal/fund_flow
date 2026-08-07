import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../design/flux.dart';
import '../common/formatting.dart';

/// Earlier conversations.
///
/// Titled from the person's own opening question rather than from a model-written
/// summary: their phrasing is what they will recognise when scanning the list,
/// and a title is not worth a round trip.
class ThreadsPage extends ConsumerWidget {
  const ThreadsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.flux;
    final app = ref.watch(appControllerProvider).value;
    final threads = app?.threads ?? const [];
    final controller = ref.read(appControllerProvider.notifier);

    if (threads.isEmpty) {
      return FluxDetailPage(
        title: 'Earlier chats',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: FluxEmpty(
              icon: Icons.forum_outlined,
              title: 'No earlier chats',
              message:
                  'A conversation is saved once you actually ask something, so '
                  'an abandoned one leaves nothing behind.',
              actionLabel: 'Back',
              onAction: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      );
    }

    return FluxDetailPage(
      title: 'Earlier chats',
      slivers: [
        SliverToBoxAdapter(
          child: FluxGroup(
            footer:
                'Conversations are stored on this device. Clearing them does '
                'not touch your transactions.',
            children: [
              for (final thread in threads)
                FluxRow(
                  title: thread.title,
                  subtitle:
                      '${dayLabel(thread.updatedAt)} · '
                      '${thread.messageCount} '
                      '${thread.messageCount == 1 ? 'message' : 'messages'}',
                  icon: thread.id == app?.activeThreadId
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  iconColor: thread.id == app?.activeThreadId
                      ? palette.iris
                      : null,
                  chevron: true,
                  onTap: () async {
                    await controller.openConversationThread(thread.id);
                    if (context.mounted) Navigator.of(context).maybePop();
                  },
                  trailing: FluxIconButton(
                    icon: Icons.delete_outline_rounded,
                    size: 17,
                    color: palette.textFaint,
                    tooltip: 'Delete chat',
                    onPressed: () async {
                      final confirmed = await fluxConfirm(
                        context: context,
                        title: 'Delete this chat?',
                        message:
                            'The conversation goes; every transaction it '
                            'discussed stays exactly as it is.',
                      );
                      if (confirmed) {
                        await controller.deleteConversationThread(thread.id);
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
