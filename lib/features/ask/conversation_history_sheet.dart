import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/conversation.dart';
import '../../ui/components/current_button.dart';
import '../../ui/foundation/current_colors.dart';

/// Past conversations.
///
/// Deletion lives here rather than in the chat header, beside the thing being
/// deleted. A header control acting on whatever happens to be open is easy to
/// press by mistake and gives no sense of what is about to be lost.
class ConversationHistorySheet extends ConsumerWidget {
  const ConversationHistorySheet({super.key, required this.onOpened});

  /// Called after a thread is opened, so the caller can dismiss the sheet.
  final VoidCallback onOpened;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final threads = app.threads;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your conversations',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.current.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chats',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ],
                ),
              ),
              CurrentButton(
                label: 'New chat',
                icon: Icons.add_rounded,
                compact: true,
                style: CurrentButtonStyle.outline,
                onPressed: () {
                  ref.read(appControllerProvider.notifier).startNewChat();
                  onOpened();
                },
              ),
            ],
          ),
        ),
        if (threads.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Chats you start will be kept here.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: context.current.muted),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(
                24,
                8,
                24,
                24 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: threads.length,
              itemBuilder: (context, index) => _ThreadRow(
                thread: threads[index],
                active: threads[index].id == app.activeThreadId,
                onOpen: () {
                  ref
                      .read(appControllerProvider.notifier)
                      .openConversationThread(threads[index].id);
                  onOpened();
                },
                onDelete: () => _confirmDelete(context, ref, threads[index]),
              ),
            ),
          ),
      ],
    );
  }

  /// Deleting a conversation cannot be undone, so it is confirmed and the
  /// dialog names the thread rather than asking about "this item".
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ConversationThread thread,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete this chat?'),
        content: Text(
          '"${thread.title}" and its ${thread.messageCount} '
          '${thread.messageCount == 1 ? 'message' : 'messages'} will be '
          'removed. Your transactions are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref
          .read(appControllerProvider.notifier)
          .deleteConversationThread(thread.id);
    }
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.active,
    required this.onOpen,
    required this.onDelete,
  });

  final ConversationThread thread;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(15, 13, 8, 13),
        decoration: BoxDecoration(
          color: context.current.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? context.current.intelligence : context.current.rule,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    thread.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      _relative(thread.updatedAt),
                      '${thread.messageCount} '
                          '${thread.messageCount == 1 ? 'message' : 'messages'}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: context.current.muted,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Delete chat',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              color: context.current.muted,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
      ),
    ),
  );

  /// Coarse relative time. Someone scanning history wants to place a chat,
  /// not read a timestamp.
  static String _relative(DateTime value) {
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    if (difference.inDays == 1) return 'Yesterday';
    if (difference.inDays < 7) return '${difference.inDays} days ago';
    return '${value.day}/${value.month}/${value.year}';
  }
}
