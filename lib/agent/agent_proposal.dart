enum AgentProposalKind {
  createTransaction,
  updateTransaction,
  deleteTransaction,
  bulkCategory,
  updateSettings,
  setAppLock,
  clearConversation,
  setMemory,
  deleteMemory,
  setBudget,
  deleteBudget,
}

enum AgentProposalStatus { pending, approved, rejected, expired, stale }

class AgentProposal {
  const AgentProposal({
    this.id,
    required this.kind,
    required this.title,
    required this.explanation,
    required this.arguments,
    required this.createdAt,
    required this.expiresAt,
    required this.affectedIds,
    this.details = const [],
    this.affectedFingerprint = const {},
    this.requiresAuthentication = false,
    this.reversible = true,
    this.status = AgentProposalStatus.pending,
  });

  final int? id;
  final AgentProposalKind kind;
  final String title;
  final String explanation;
  final Map<String, Object?> arguments;
  final DateTime createdAt;
  final DateTime expiresAt;
  final List<int> affectedIds;

  /// The change itself, in the words of the app rather than the model.
  ///
  /// A card reading only "Add a transaction" asks someone to approve
  /// something they cannot see. The model once proposed forty US dollars as
  /// forty cents, and no amount of care at the approval step could have
  /// caught it, because the amount was never on screen.
  final List<String> details;

  /// What the affected records looked like when this was proposed, keyed by
  /// transaction id.
  ///
  /// Existence of an id was the only thing checked at approval, so a
  /// proposal built against one row would happily apply to a row that had
  /// since been edited into something else. That mattered little inside a
  /// ten-minute window and matters a great deal inside a day, which is how
  /// long a reversible proposal now waits.
  final Map<int, String> affectedFingerprint;
  final bool requiresAuthentication;
  final bool reversible;
  final AgentProposalStatus status;

  /// A stable summary of the fields a change would overwrite.
  static String fingerprintOf({
    required int amountMinor,
    required String currency,
    required String merchant,
    required String category,
    required DateTime occurredAt,
  }) =>
      '$amountMinor|$currency|${merchant.trim().toLowerCase()}'
      '|${category.trim().toLowerCase()}|${occurredAt.toUtc().toIso8601String()}';

  AgentProposal copyWith({int? id, AgentProposalStatus? status}) =>
      AgentProposal(
        id: id ?? this.id,
        kind: kind,
        title: title,
        explanation: explanation,
        arguments: arguments,
        createdAt: createdAt,
        expiresAt: expiresAt,
        affectedIds: affectedIds,
        details: details,
        affectedFingerprint: affectedFingerprint,
        requiresAuthentication: requiresAuthentication,
        reversible: reversible,
        status: status ?? this.status,
      );

  Map<String, Object?> toMap() => {
    'id': id,
    'kind': kind.name,
    'title': title,
    'explanation': explanation,
    'arguments': arguments,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'affectedIds': affectedIds,
    'details': details,
    'affectedFingerprint': affectedFingerprint.map(
      (id, value) => MapEntry(id.toString(), value),
    ),
    'requiresAuthentication': requiresAuthentication,
    'reversible': reversible,
    'status': status.name,
  };
}
