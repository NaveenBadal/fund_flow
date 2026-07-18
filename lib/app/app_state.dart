import '../domain/conversation.dart';
import '../agent/agent_proposal.dart';
import '../domain/preferences.dart';
import '../domain/transaction.dart';
import '../ingestion/sms_source.dart';

enum AiConnection { disconnected, checking, connected, rejected }

enum ImportPhase {
  idle,
  requestingPermission,
  reading,
  understanding,
  stopped,
  rateLimited,
  providerDisconnected,
  invalidResponse,
  complete,
  error,
}

class ImportStatus {
  const ImportStatus({
    this.phase = ImportPhase.idle,
    this.checked = 0,
    this.imported = 0,
    this.skipped = 0,
    this.permission,
    this.message,
  });
  final ImportPhase phase;
  final int checked;
  final int imported;
  final int skipped;
  final MessagePermission? permission;
  final String? message;
  bool get working =>
      phase == ImportPhase.requestingPermission ||
      phase == ImportPhase.reading ||
      phase == ImportPhase.understanding;
  bool get retryable =>
      phase == ImportPhase.stopped ||
      phase == ImportPhase.rateLimited ||
      phase == ImportPhase.providerDisconnected ||
      phase == ImportPhase.invalidResponse ||
      phase == ImportPhase.error;
}

class AppState {
  const AppState({
    required this.preferences,
    required this.transactions,
    required this.conversation,
    required this.aiConnection,
    this.importStatus = const ImportStatus(),
    this.asking = false,
    this.askStage,
    this.error,
    this.locked = false,
    this.pendingAgentProposal,
    this.lastAgentAction,
  });
  final AppPreferences preferences;
  final List<MoneyTransaction> transactions;
  final List<ConversationMessage> conversation;
  final AiConnection aiConnection;
  final ImportStatus importStatus;
  final bool asking;
  final String? askStage;
  final String? error;
  final bool locked;
  final AgentProposal? pendingAgentProposal;
  final String? lastAgentAction;

  AppState copyWith({
    AppPreferences? preferences,
    List<MoneyTransaction>? transactions,
    List<ConversationMessage>? conversation,
    AiConnection? aiConnection,
    ImportStatus? importStatus,
    bool? asking,
    String? askStage,
    String? error,
    bool clearError = false,
    bool? locked,
    AgentProposal? pendingAgentProposal,
    bool clearPendingAgentProposal = false,
    String? lastAgentAction,
    bool clearLastAgentAction = false,
  }) => AppState(
    preferences: preferences ?? this.preferences,
    transactions: transactions ?? this.transactions,
    conversation: conversation ?? this.conversation,
    aiConnection: aiConnection ?? this.aiConnection,
    importStatus: importStatus ?? this.importStatus,
    asking: asking ?? this.asking,
    askStage: askStage ?? this.askStage,
    error: clearError ? null : error ?? this.error,
    locked: locked ?? this.locked,
    pendingAgentProposal: clearPendingAgentProposal
        ? null
        : pendingAgentProposal ?? this.pendingAgentProposal,
    lastAgentAction: clearLastAgentAction
        ? null
        : lastAgentAction ?? this.lastAgentAction,
  );
}
