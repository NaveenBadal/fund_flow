enum ImportRunState { running, completed, stopped, failed }

enum ImportItemState {
  queued,
  alreadySeen,
  transaction,
  notTransaction,
  uncertain,
  failed,
}

class ImportRunRecord {
  const ImportRunRecord({
    required this.id,
    required this.source,
    required this.state,
    required this.startedAt,
    required this.model,
    required this.endpoint,
    required this.total,
    required this.processed,
    required this.imported,
    this.completedAt,
    this.error,
  });

  final int id;
  final String source;
  final ImportRunState state;
  final DateTime startedAt;
  final DateTime? completedAt;
  final String model;
  final String endpoint;
  final int total;
  final int processed;
  final int imported;
  final String? error;

  factory ImportRunRecord.fromMap(Map<String, Object?> map) => ImportRunRecord(
    id: map['id'] as int,
    source: map['source'] as String,
    state: ImportRunState.values.byName(map['state'] as String),
    startedAt: DateTime.parse(map['started_at'] as String).toLocal(),
    completedAt: map['completed_at'] == null
        ? null
        : DateTime.parse(map['completed_at'] as String).toLocal(),
    model: map['model'] as String,
    endpoint: map['endpoint'] as String,
    total: map['total'] as int,
    processed: map['processed'] as int,
    imported: map['imported'] as int,
    error: map['error'] as String?,
  );
}

class ImportBatchRecord {
  const ImportBatchRecord({
    required this.id,
    required this.runId,
    required this.position,
    required this.state,
    required this.createdAt,
    required this.requestJson,
    this.completedAt,
    this.responseJson,
    this.error,
  });

  final int id;
  final int runId;
  final int position;
  final String state;
  final DateTime createdAt;
  final DateTime? completedAt;
  final String requestJson;
  final String? responseJson;
  final String? error;

  factory ImportBatchRecord.fromMap(Map<String, Object?> map) =>
      ImportBatchRecord(
        id: map['id'] as int,
        runId: map['run_id'] as int,
        position: map['position'] as int,
        state: map['state'] as String,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        completedAt: map['completed_at'] == null
            ? null
            : DateTime.parse(map['completed_at'] as String).toLocal(),
        requestJson: map['request_json'] as String,
        responseJson: map['response_json'] as String?,
        error: map['error'] as String?,
      );
}

class ImportItemRecord {
  const ImportItemRecord({
    required this.id,
    required this.runId,
    required this.fingerprint,
    required this.body,
    required this.receivedAt,
    required this.state,
    this.sender,
    this.reason,
    this.transactionId,
    this.batchId,
  });

  final int id;
  final int runId;
  final int? batchId;
  final String fingerprint;
  final String? sender;
  final String body;
  final DateTime receivedAt;
  final ImportItemState state;
  final String? reason;
  final int? transactionId;

  factory ImportItemRecord.fromMap(Map<String, Object?> map) =>
      ImportItemRecord(
        id: map['id'] as int,
        runId: map['run_id'] as int,
        batchId: map['batch_id'] as int?,
        fingerprint: map['fingerprint'] as String,
        sender: map['sender'] as String?,
        body: map['body'] as String,
        receivedAt: DateTime.parse(map['received_at'] as String).toLocal(),
        state: ImportItemState.values.byName(map['state'] as String),
        reason: map['reason'] as String?,
        transactionId: map['transaction_id'] as int?,
      );
}
