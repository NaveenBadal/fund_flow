import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/assistant_message.dart';
import 'expense_provider.dart';

class AssistantConversationNotifier
    extends AsyncNotifier<List<AssistantMessage>> {
  @override
  Future<List<AssistantMessage>> build() =>
      ref.read(databaseProvider).getAssistantMessages();

  Future<void> addUser(String text) =>
      _add(AssistantMessage(user: true, text: text, timestamp: DateTime.now()));

  Future<void> addAssistant({
    required String text,
    required int sources,
    required bool verified,
    String filterDetails = '',
  }) => _add(
    AssistantMessage(
      user: false,
      text: text,
      sources: sources,
      verified: verified,
      filterDetails: filterDetails,
      timestamp: DateTime.now(),
    ),
  );

  Future<void> _add(AssistantMessage message) async {
    final inserted = await ref
        .read(databaseProvider)
        .insertAssistantMessage(message);
    state = AsyncValue.data([...(state.value ?? const []), inserted]);
  }

  Future<void> clear() async {
    await ref.read(databaseProvider).clearAssistantMessages();
    state = const AsyncValue.data([]);
  }
}

final assistantConversationProvider =
    AsyncNotifierProvider<
      AssistantConversationNotifier,
      List<AssistantMessage>
    >(AssistantConversationNotifier.new);
