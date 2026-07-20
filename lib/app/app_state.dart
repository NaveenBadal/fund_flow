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
  paused,
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
      phase == ImportPhase.understanding ||
      phase == ImportPhase.paused;
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
    this.activeThreadId,
    this.threads = const [],
    this.importStatus = const ImportStatus(),
    this.asking = false,
    this.askStage,
    this.askDraft,
    this.error,
    this.locked = false,
    this.pendingAgentProposal,
    this.lastAgentAction,
    this.lastAgentUndoId,
  });
  final AppPreferences preferences;
  final List<MoneyTransaction> transactions;
  final List<ConversationMessage> conversation;

  /// Thread the conversation belongs to. Null means an unsent new chat, which
  /// is not persisted until its first question.
  final int? activeThreadId;

  /// History, most recently active first.
  final List<ConversationThread> threads;
  final AiConnection aiConnection;
  final ImportStatus importStatus;
  final bool asking;
  final String? askStage;
  final String? askDraft;
  final String? error;
  final bool locked;
  final AgentProposal? pendingAgentProposal;
  final String? lastAgentAction;

  /// The undo record the last applied action wrote, if it wrote one.
  ///
  /// Undo used to pop whichever record was newest, so undoing after an action
  /// that saved no record — clearing a conversation — reversed an unrelated
  /// earlier change instead. Null means the action cannot be undone and the
  /// offer is not made.
  final int? lastAgentUndoId;

  AppState copyWith({
    AppPreferences? preferences,
    List<MoneyTransaction>? transactions,
    List<ConversationMessage>? conversation,
    int? activeThreadId,
    bool clearActiveThreadId = false,
    List<ConversationThread>? threads,
    AiConnection? aiConnection,
    ImportStatus? importStatus,
    bool? asking,
    String? askStage,
    String? askDraft,
    bool clearAskDraft = false,
    String? error,
    bool clearError = false,
    bool? locked,
    AgentProposal? pendingAgentProposal,
    bool clearPendingAgentProposal = false,
    String? lastAgentAction,
    bool clearLastAgentAction = false,
    int? lastAgentUndoId,
  }) => AppState(
    preferences: preferences ?? this.preferences,
    transactions: transactions ?? this.transactions,
    conversation: conversation ?? this.conversation,
    activeThreadId: clearActiveThreadId
        ? null
        : activeThreadId ?? this.activeThreadId,
    threads: threads ?? this.threads,
    aiConnection: aiConnection ?? this.aiConnection,
    importStatus: importStatus ?? this.importStatus,
    asking: asking ?? this.asking,
    askStage: askStage ?? this.askStage,
    askDraft: clearAskDraft ? null : askDraft ?? this.askDraft,
    error: clearError ? null : error ?? this.error,
    locked: locked ?? this.locked,
    pendingAgentProposal: clearPendingAgentProposal
        ? null
        : pendingAgentProposal ?? this.pendingAgentProposal,
    lastAgentAction: clearLastAgentAction
        ? null
        : lastAgentAction ?? this.lastAgentAction,
    lastAgentUndoId: clearLastAgentAction
        ? null
        : lastAgentUndoId ?? this.lastAgentUndoId,
  );
}
