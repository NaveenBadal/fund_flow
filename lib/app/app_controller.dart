import 'dart:io';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../data/fund_flow_store.dart';
import '../agent/agent_proposal.dart';
import '../agent/agent_runner.dart';
import '../agent/local_mcp_server.dart';
import '../data/secure_preferences.dart';
import '../domain/conversation.dart';
import '../domain/import_audit.dart';
import '../domain/preferences.dart';
import '../domain/transaction.dart';
import '../ingestion/ai_message_ingestion.dart';
import '../ingestion/message_candidate.dart';
import '../ingestion/notification_source.dart';
import '../ingestion/sms_source.dart';
import '../intelligence/ai_client.dart';
import '../update/app_updater.dart';
import 'app_state.dart';

const _maximumIngestionMessages = 12;
const _maximumIngestionCharacters = 9000;

int _ingestionBatchLength(List<MessageCandidate> values, int start) {
  var characters = 0;
  var count = 0;
  while (start + count < values.length && count < _maximumIngestionMessages) {
    final value = values[start + count];
    // Include a small allowance for IDs, timestamps and JSON field names.
    final next = (value.sender?.length ?? 0) + value.body.length + 160;
    if (count > 0 && characters + next > _maximumIngestionCharacters) break;
    characters += next;
    count++;
  }
  return count;
}

List<List<T>> _ingestionBatches<T>(
  List<T> values,
  MessageCandidate Function(T value) candidateOf,
) {
  final candidates = values.map(candidateOf).toList(growable: false);
  final batches = <List<T>>[];
  for (var start = 0; start < values.length;) {
    final count = _ingestionBatchLength(candidates, start);
    batches.add(values.sublist(start, start + count));
    start += count;
  }
  return batches;
}

final storeProvider = Provider((ref) {
  final store = FundFlowStore();
  ref.onDispose(store.close);
  return store;
});
final securePreferencesProvider = Provider(
  (ref) => const SecurePreferences(FlutterSecureStorage()),
);
final smsSourceProvider = Provider((ref) => SmsSource());
final notificationSourceProvider = Provider(
  (ref) => const NotificationSource(),
);
final aiClientProvider = Provider((ref) {
  final client = AiClient();
  ref.onDispose(client.close);
  return client;
});
final localAuthenticationProvider = Provider((ref) => LocalAuthentication());
final appControllerProvider = AsyncNotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends AsyncNotifier<AppState> {
  bool _stopImportRequested = false;
  AgentCancellationToken? _activeRun;
  @override
  Future<AppState> build() async {
    final secure = ref.read(securePreferencesProvider);
    final prefs = await secure.read();
    final key = await secure.apiKey();
    final store = ref.read(storeProvider);
    await store.recoverInterruptedImports();
    final values = await Future.wait([
      store.transactions(),
      store.conversation(),
    ]);
    var transactions = values[0] as List<MoneyTransaction>;
    if (prefs.captureNotifications) {
      transactions = await _drainNotifications(transactions, key, prefs);
    }
    return AppState(
      preferences: prefs,
      transactions: transactions,
      conversation: values[1] as List<ConversationMessage>,
      aiConnection: key.isEmpty
          ? AiConnection.disconnected
          : AiConnection.connected,
      locked: prefs.lockApp,
    );
  }

  AppState get _value => state.requireValue;
  Future<void> updatePreferences(AppPreferences value) async {
    await ref.read(securePreferencesProvider).write(value);
    state = AsyncData(_value.copyWith(preferences: value));
  }

  Future<bool> setAppLock(bool enabled) async {
    if (enabled && !await _authenticate('Turn on app lock')) return false;
    final prefs = _value.preferences.copyWith(lockApp: enabled);
    await ref.read(securePreferencesProvider).write(prefs);
    state = AsyncData(
      _value.copyWith(preferences: prefs, locked: false, clearError: true),
    );
    return true;
  }

  Future<bool> setNotificationCapture(bool enabled) async {
    final source = ref.read(notificationSourceProvider);
    if (enabled && !await source.hasAccess()) {
      await source.openAccessSettings();
      state = AsyncData(
        _value.copyWith(
          error:
              'Allow Fund Flow notification access, then turn capture on again.',
        ),
      );
      return false;
    }
    await source.setEnabled(enabled);
    final prefs = _value.preferences.copyWith(captureNotifications: enabled);
    await ref.read(securePreferencesProvider).write(prefs);
    var transactions = _value.transactions;
    if (enabled) {
      final key = await ref.read(securePreferencesProvider).apiKey();
      transactions = await _drainNotifications(
        transactions,
        key,
        _value.preferences,
      );
    }
    state = AsyncData(
      _value.copyWith(
        preferences: prefs,
        transactions: transactions,
        clearError: true,
      ),
    );
    return true;
  }

  Future<List<MoneyTransaction>> _drainNotifications(
    List<MoneyTransaction> existing,
    String apiKey,
    AppPreferences preferences,
  ) async {
    if (apiKey.isEmpty) return existing;
    int? auditRunId;
    try {
      final source = ref.read(notificationSourceProvider);
      final pending = await source.pending();
      if (pending.isEmpty) return existing;
      final seen = await ref
          .read(storeProvider)
          .seenImportFingerprints(
            pending.map((item) => item.candidate.fingerprint),
          );
      final unseen = pending
          .where((item) => !seen.contains(item.candidate.fingerprint))
          .toList();
      auditRunId = await ref
          .read(storeProvider)
          .beginImportRun(
            source: TransactionSource.notification.name,
            model: preferences.aiModel,
            endpoint: preferences.aiEndpoint,
            candidates: pending.map((item) => item.candidate).toList(),
            alreadySeen: seen,
          );
      final activeRunId = auditRunId;
      final acknowledged = <String>[];
      final batches = _ingestionBatches(unseen, (item) => item.candidate);
      for (var wave = 0; wave < batches.length; wave += 2) {
        final end = (wave + 2).clamp(0, batches.length);
        await Future.wait([
          for (var batchPosition = wave; batchPosition < end; batchPosition++)
            () async {
              final items = batches[batchPosition];
              final batchId = await ref
                  .read(storeProvider)
                  .beginImportBatch(
                    runId: activeRunId,
                    position: batchPosition,
                  );
              await ref
                  .read(storeProvider)
                  .assignImportBatch(
                    activeRunId,
                    batchId,
                    items.map((item) => item.candidate.fingerprint),
                  );
              final requests = <String>[];
              final responses = <String>[];
              late AiIngestionBatch analysis;
              try {
                analysis = await ref
                    .read(aiClientProvider)
                    .analyzeMessages(
                      endpoint: preferences.aiEndpoint,
                      apiKey: apiKey,
                      model: preferences.aiModel,
                      candidates: items.map((item) => item.candidate).toList(),
                      source: TransactionSource.notification,
                      now: DateTime.now(),
                      onRequest: requests.add,
                      onResponse: responses.add,
                    );
                await ref
                    .read(storeProvider)
                    .recordImportBatchRequest(
                      batchId,
                      _auditExchanges(requests),
                    );
                await ref
                    .read(storeProvider)
                    .recordImportBatchResponse(
                      batchId,
                      _auditExchanges(responses),
                    );
                await ref
                    .read(storeProvider)
                    .commitIngestionBatch(
                      analysis,
                      runId: activeRunId,
                      batchId: batchId,
                    );
              } catch (error) {
                if (requests.isNotEmpty) {
                  await ref
                      .read(storeProvider)
                      .recordImportBatchRequest(
                        batchId,
                        _auditExchanges(requests),
                      );
                }
                if (responses.isNotEmpty) {
                  await ref
                      .read(storeProvider)
                      .recordImportBatchResponse(
                        batchId,
                        _auditExchanges(responses),
                      );
                }
                await ref
                    .read(storeProvider)
                    .failImportBatch(batchId, _importFailureDetail(error));
                rethrow;
              }
              final committed = analysis.results
                  .map((item) => item.fingerprint)
                  .toSet();
              for (final item in items) {
                if (committed.contains(item.candidate.fingerprint)) {
                  acknowledged.add(item.id);
                }
              }
            }(),
        ]);
      }
      for (final item in pending) {
        if (seen.contains(item.candidate.fingerprint)) {
          acknowledged.add(item.id);
        }
      }
      await source.acknowledge(acknowledged);
      await ref
          .read(storeProvider)
          .finishImportRun(auditRunId, state: ImportRunState.completed);
      return ref.read(storeProvider).transactions();
    } catch (error) {
      if (auditRunId != null) {
        await ref
            .read(storeProvider)
            .finishImportRun(
              auditRunId,
              state: ImportRunState.failed,
              error: _importFailureDetail(error),
            );
      }
      return existing;
    }
  }

  void lock() {
    if (_value.preferences.lockApp && !_value.locked) {
      state = AsyncData(_value.copyWith(locked: true));
    }
  }

  Future<bool> unlock() async {
    if (!_value.locked) return true;
    final ok = await _authenticate('Unlock Fund Flow');
    if (ok) state = AsyncData(_value.copyWith(locked: false, clearError: true));
    return ok;
  }

  Future<bool> _authenticate(String reason) async {
    try {
      final auth = ref.read(localAuthenticationProvider);
      if (!await auth.isDeviceSupported()) {
        state = AsyncData(
          _value.copyWith(error: 'Set up a device screen lock first.'),
        );
        return false;
      }
      return auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      state = AsyncData(
        _value.copyWith(error: 'Device authentication is unavailable.'),
      );
      return false;
    }
  }

  Future<bool> connectAi({
    required String key,
    required String endpoint,
    required String model,
  }) async {
    state = AsyncData(
      _value.copyWith(aiConnection: AiConnection.checking, clearError: true),
    );
    final valid = await ref
        .read(aiClientProvider)
        .validate(endpoint: endpoint, apiKey: key, model: model);
    if (!valid) {
      state = AsyncData(
        _value.copyWith(
          aiConnection: AiConnection.rejected,
          error:
              'The connection was not accepted. Check the key, endpoint, and model.',
        ),
      );
      return false;
    }
    await ref.read(securePreferencesProvider).writeApiKey(key);
    final prefs = _value.preferences.copyWith(
      aiEndpoint: endpoint,
      aiModel: model,
    );
    await ref.read(securePreferencesProvider).write(prefs);
    state = AsyncData(
      _value.copyWith(
        preferences: prefs,
        aiConnection: AiConnection.connected,
        clearError: true,
      ),
    );
    return true;
  }

  Future<void> disconnectAi() async {
    await ref.read(securePreferencesProvider).writeApiKey('');
    state = AsyncData(_value.copyWith(aiConnection: AiConnection.disconnected));
  }

  Future<void> saveTransaction(MoneyTransaction value) async {
    await ref.read(storeProvider).saveTransaction(value);
    state = AsyncData(
      _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
      ),
    );
  }

  Future<void> confirmTransaction(MoneyTransaction value) => saveTransaction(
    value.copyWith(reviewState: ReviewState.confirmed, confidence: 1),
  );
  Future<void> deleteTransaction(int id) async {
    await ref.read(storeProvider).deleteTransaction(id);
    state = AsyncData(
      _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
      ),
    );
  }

  Future<void> clearConversation() async {
    await ref.read(storeProvider).clearConversation();
    state = AsyncData(_value.copyWith(conversation: const []));
  }

  Future<void> importMessages() async {
    _stopImportRequested = false;
    int? auditRunId;
    var current = _value;
    final apiKey = await ref.read(securePreferencesProvider).apiKey();
    if (apiKey.isEmpty) {
      state = AsyncData(
        current.copyWith(
          importStatus: const ImportStatus(
            phase: ImportPhase.error,
            message: 'Connect intelligence before analyzing messages.',
          ),
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(
        importStatus: const ImportStatus(
          phase: ImportPhase.requestingPermission,
        ),
        clearError: true,
      ),
    );
    final source = ref.read(smsSourceProvider);
    final permission = await source.permission(request: true);
    if (_stopImportRequested) {
      _setImportStopped(permission: permission);
      return;
    }
    if (permission != MessagePermission.granted) {
      state = AsyncData(
        _value.copyWith(
          importStatus: ImportStatus(
            phase: ImportPhase.error,
            permission: permission,
            message: permission == MessagePermission.permanentlyDenied
                ? 'Message permission is disabled in Android settings.'
                : 'Message permission was not granted.',
          ),
        ),
      );
      return;
    }
    state = AsyncData(
      _value.copyWith(
        importStatus: ImportStatus(
          phase: ImportPhase.reading,
          permission: permission,
        ),
      ),
    );
    try {
      final candidates = await source.recent(
        _value.preferences.messageLookbackDays,
      );
      if (_stopImportRequested) {
        _setImportStopped(permission: permission);
        return;
      }
      final seen = await ref
          .read(storeProvider)
          .seenImportFingerprints(candidates.map((item) => item.fingerprint));
      final unseen = candidates
          .where((item) => !seen.contains(item.fingerprint))
          .toList();
      auditRunId = await ref
          .read(storeProvider)
          .beginImportRun(
            source: TransactionSource.message.name,
            model: _value.preferences.aiModel,
            endpoint: _value.preferences.aiEndpoint,
            candidates: candidates,
            alreadySeen: seen,
          );
      final activeRunId = auditRunId;
      var imported = 0;
      var checked = 0;
      var skipped = seen.length;
      final batches = _ingestionBatches(unseen, (item) => item);
      for (var wave = 0; wave < batches.length; wave += 2) {
        if (_stopImportRequested) {
          await ref
              .read(storeProvider)
              .finishImportRun(auditRunId, state: ImportRunState.stopped);
          state = AsyncData(
            _value.copyWith(
              transactions: await ref.read(storeProvider).transactions(),
              importStatus: ImportStatus(
                phase: ImportPhase.stopped,
                permission: permission,
                checked: checked,
                imported: imported,
                skipped: skipped,
                message: 'Stopped. Completed batches are safely saved.',
              ),
            ),
          );
          return;
        }
        state = AsyncData(
          _value.copyWith(
            importStatus: ImportStatus(
              phase: ImportPhase.understanding,
              permission: permission,
              checked: checked,
              imported: imported,
              skipped: skipped,
            ),
          ),
        );
        final end = (wave + 2).clamp(0, batches.length);
        await Future.wait([
          for (var batchPosition = wave; batchPosition < end; batchPosition++)
            () async {
              final batch = batches[batchPosition];
              final batchId = await ref
                  .read(storeProvider)
                  .beginImportBatch(
                    runId: activeRunId,
                    position: batchPosition,
                  );
              await ref
                  .read(storeProvider)
                  .assignImportBatch(
                    activeRunId,
                    batchId,
                    batch.map((item) => item.fingerprint),
                  );
              final requests = <String>[];
              final responses = <String>[];
              late AiIngestionBatch analysis;
              try {
                analysis = await ref
                    .read(aiClientProvider)
                    .analyzeMessages(
                      endpoint: _value.preferences.aiEndpoint,
                      apiKey: apiKey,
                      model: _value.preferences.aiModel,
                      candidates: batch,
                      source: TransactionSource.message,
                      now: DateTime.now(),
                      onRequest: requests.add,
                      onResponse: responses.add,
                    );
                await ref
                    .read(storeProvider)
                    .recordImportBatchRequest(
                      batchId,
                      _auditExchanges(requests),
                    );
                await ref
                    .read(storeProvider)
                    .recordImportBatchResponse(
                      batchId,
                      _auditExchanges(responses),
                    );
                imported += await ref
                    .read(storeProvider)
                    .commitIngestionBatch(
                      analysis,
                      runId: activeRunId,
                      batchId: batchId,
                    );
              } catch (error) {
                if (requests.isNotEmpty) {
                  await ref
                      .read(storeProvider)
                      .recordImportBatchRequest(
                        batchId,
                        _auditExchanges(requests),
                      );
                }
                if (responses.isNotEmpty) {
                  await ref
                      .read(storeProvider)
                      .recordImportBatchResponse(
                        batchId,
                        _auditExchanges(responses),
                      );
                }
                await ref
                    .read(storeProvider)
                    .failImportBatch(batchId, _importFailureDetail(error));
                rethrow;
              }
              checked += batch.length;
              skipped += analysis.results
                  .where((item) => item.transaction == null)
                  .length;
              state = AsyncData(
                _value.copyWith(
                  transactions: await ref.read(storeProvider).transactions(),
                  importStatus: ImportStatus(
                    phase: ImportPhase.understanding,
                    permission: permission,
                    checked: checked,
                    imported: imported,
                    skipped: skipped,
                    message: 'Saved batch ${batchPosition + 1}',
                  ),
                ),
              );
            }(),
        ]);
      }
      await ref
          .read(storeProvider)
          .finishImportRun(auditRunId, state: ImportRunState.completed);
      current = _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
        importStatus: ImportStatus(
          phase: ImportPhase.complete,
          permission: permission,
          checked: candidates.length,
          imported: imported,
          skipped: skipped,
        ),
      );
      state = AsyncData(current);
    } on AiRequestFailure catch (error) {
      final message = switch (error.statusCode) {
        401 || 403 => 'Reconnect intelligence before analyzing messages.',
        429 =>
          'The provider is rate limited. Imported batches are safe; try again later.',
        _ =>
          'The provider could not analyze messages. Imported batches are safe.',
      };
      state = AsyncData(
        _value.copyWith(
          importStatus: ImportStatus(
            phase: switch (error.statusCode) {
              401 || 403 => ImportPhase.providerDisconnected,
              429 => ImportPhase.rateLimited,
              _ => ImportPhase.error,
            },
            permission: permission,
            message: message,
          ),
        ),
      );
      if (auditRunId != null) {
        await ref
            .read(storeProvider)
            .finishImportRun(
              auditRunId,
              state: ImportRunState.failed,
              error: message,
            );
      }
    } catch (error) {
      final detail = _importFailureDetail(error);
      state = AsyncData(
        _value.copyWith(
          importStatus: ImportStatus(
            phase: ImportPhase.invalidResponse,
            permission: permission,
            message:
                'The AI response could not be used. Completed batches are safe. $detail',
          ),
        ),
      );
      if (auditRunId != null) {
        await ref
            .read(storeProvider)
            .finishImportRun(
              auditRunId,
              state: ImportRunState.failed,
              error: detail,
            );
      }
    }
  }

  String _importFailureDetail(Object error) => switch (error) {
    AiRequestFailure(:final statusCode) => 'Provider HTTP $statusCode.',
    IngestionSchemaException(:final message) => message,
    _ => error.toString(),
  };

  String _auditExchanges(List<String> values) {
    if (values.length == 1) return values.single;
    return jsonEncode([
      for (var index = 0; index < values.length; index++)
        {'attempt': index + 1, 'payload': _decodedOrText(values[index])},
    ]);
  }

  Object _decodedOrText(String value) {
    try {
      return jsonDecode(value) as Object;
    } catch (_) {
      return value;
    }
  }

  void stopMessageImport() {
    if (!_value.importStatus.working) return;
    _stopImportRequested = true;
    state = AsyncData(
      _value.copyWith(
        importStatus: ImportStatus(
          phase: ImportPhase.stopped,
          permission: _value.importStatus.permission,
          checked: _value.importStatus.checked,
          imported: _value.importStatus.imported,
          skipped: _value.importStatus.skipped,
          message: 'Stopping after the current AI batch…',
        ),
      ),
    );
  }

  void _setImportStopped({MessagePermission? permission}) {
    state = AsyncData(
      _value.copyWith(
        importStatus: ImportStatus(
          phase: ImportPhase.stopped,
          permission: permission ?? _value.importStatus.permission,
          checked: _value.importStatus.checked,
          imported: _value.importStatus.imported,
          skipped: _value.importStatus.skipped,
          message: 'Stopped. Completed batches are safely saved.',
        ),
      ),
    );
  }

  Future<void> ask(String question) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty || _value.asking) return;
    final user = ConversationMessage(
      author: MessageAuthor.person,
      text: trimmed,
      createdAt: DateTime.now(),
    );
    await ref.read(storeProvider).addMessage(user);
    state = AsyncData(
      _value.copyWith(
        conversation: await ref.read(storeProvider).conversation(),
        asking: true,
        askStage: 'Checking your activity',
        clearError: true,
      ),
    );
    try {
      final key = await ref.read(securePreferencesProvider).apiKey();
      if (key.isEmpty) throw const AiRequestFailure(401);
      final server = LocalMcpServer(
        transactions: () => _value.transactions,
        preferences: () => _value.preferences,
        conversation: () => _value.conversation,
        financialMemory: () => ref.read(storeProvider).financialMemory(),
        agentTelemetry: (limit) =>
            ref.read(storeProvider).recentAgentRuns(limit: limit),
        updateStatus: () async {
          final updater = AppUpdater();
          try {
            final update = await updater.check();
            return {
              'supportedOnThisBuild':
                  update.availability != UpdateAvailability.unsupported,
              'status': update.availability.name,
              'installedBuildNumber': update.installedBuildNumber,
              'latestBuildNumber': update.buildNumber,
              'latestVersion': update.versionName,
              'releaseNotes': update.releaseNotes,
              'mandatory': update.mandatory,
              'channel': 'GitHub development releases',
              'userAction': update.availability == UpdateAvailability.available
                  ? 'Open You > App updates to download, verify, and install.'
                  : null,
            };
          } finally {
            updater.close();
          }
        },
      );
      final client = ref.read(aiClientProvider);
      final runner = AgentRunner(
        provider: client.configured(
          endpoint: _value.preferences.aiEndpoint,
          apiKey: key,
          model: _value.preferences.aiModel,
        ),
        server: server,
      );
      final token = AgentCancellationToken();
      _activeRun = token;
      final history = _value.conversation
          .where((message) => message.text.trim().isNotEmpty)
          .toList()
          .reversed
          // Keep the hot prompt small. Older turns remain available through
          // the local conversation_search MCP capability when they matter.
          .take(4)
          .toList()
          .reversed
          .map(
            (message) => <String, Object?>{
              'role': message.author == MessageAuthor.person
                  ? 'user'
                  : 'assistant',
              'content': message.text,
            },
          )
          .toList();
      final draft = StringBuffer();
      var structuredDraft = false;
      var lastDraftPaint = DateTime.fromMillisecondsSinceEpoch(0);
      final runStartedAt = DateTime.now();
      final result = await runner.run(
        question: trimmed,
        now: DateTime.now(),
        locale: Platform.localeName,
        timeZone: DateTime.now().timeZoneName,
        history: history,
        cancellation: token,
        onStage: (stage) {
          // Each stage begins a fresh reasoning turn; drop the prior draft.
          draft.clear();
          structuredDraft = false;
          lastDraftPaint = DateTime.fromMillisecondsSinceEpoch(0);
          if (state.hasValue) {
            state = AsyncData(
              _value.copyWith(askStage: stage, clearAskDraft: true),
            );
          }
        },
        onContentDelta: (delta) {
          draft.write(delta);
          final visible = draft.toString().trimLeft();
          final becameStructured =
              !structuredDraft &&
              (visible.startsWith('{') || visible.startsWith('```'));
          structuredDraft = structuredDraft || becameStructured;
          final now = DateTime.now();
          if (state.hasValue &&
              (becameStructured ||
                  (!structuredDraft &&
                      now.difference(lastDraftPaint) >=
                          const Duration(milliseconds: 50)))) {
            lastDraftPaint = now;
            state = AsyncData(
              _value.copyWith(
                askDraft: structuredDraft ? null : draft.toString(),
                clearAskDraft: structuredDraft,
              ),
            );
          }
        },
      );
      _activeRun = null;
      final supportingIds = <int>{};
      for (final part in result.presentation.parts) {
        final raw = part.data['transactionIds'];
        if (raw is List) supportingIds.addAll(raw.whereType<int>());
      }
      final assistant = ConversationMessage(
        author: MessageAuthor.assistant,
        text: result.presentation.plainText,
        createdAt: DateTime.now(),
        verified: !result.presentation.unstructured,
        supportingTransactionIds: supportingIds.toList(),
        parts: result.presentation.parts,
        unstructured: result.presentation.unstructured,
      );
      final messageId = await ref.read(storeProvider).addMessage(assistant);
      await ref.read(storeProvider).recordToolEvents(messageId, result.events);
      await ref
          .read(storeProvider)
          .recordAgentRun(
            conversationId: messageId,
            model: _value.preferences.aiModel,
            startedAt: runStartedAt,
            result: result,
          );
      AgentProposal? proposal;
      if (result.proposal != null) {
        proposal = await ref.read(storeProvider).saveProposal(result.proposal!);
      }
      state = AsyncData(
        _value.copyWith(
          conversation: await ref.read(storeProvider).conversation(),
          asking: false,
          askStage: null,
          clearAskDraft: true,
          pendingAgentProposal: proposal,
          clearPendingAgentProposal: proposal == null,
        ),
      );
    } on AgentRunCancelled {
      _activeRun = null;
      state = AsyncData(
        _value.copyWith(
          asking: false,
          askStage: null,
          clearAskDraft: true,
          error: 'The answer was stopped. Nothing was changed.',
        ),
      );
    } catch (error) {
      _activeRun = null;
      final message = switch (error) {
        AiRequestFailure(statusCode: 401 || 403) =>
          'Reconnect intelligence in You.',
        AiRequestFailure(statusCode: 429) =>
          'The provider is busy. Try again shortly.',
        _ =>
          'The answer could not be completed. Your activity was not changed.',
      };
      state = AsyncData(
        _value.copyWith(
          asking: false,
          askStage: null,
          clearAskDraft: true,
          error: message,
        ),
      );
    }
  }

  void stopAgent() => _activeRun?.cancel();

  Future<void> rejectAgentProposal() async {
    final proposal = _value.pendingAgentProposal;
    if (proposal?.id != null) {
      await ref
          .read(storeProvider)
          .setProposalStatus(proposal!.id!, AgentProposalStatus.rejected);
    }
    state = AsyncData(_value.copyWith(clearPendingAgentProposal: true));
  }

  Future<void> approveAgentProposal() async {
    final proposal = _value.pendingAgentProposal;
    if (proposal == null || proposal.id == null) return;
    if (DateTime.now().isAfter(proposal.expiresAt)) {
      await ref
          .read(storeProvider)
          .setProposalStatus(proposal.id!, AgentProposalStatus.expired);
      state = AsyncData(
        _value.copyWith(
          clearPendingAgentProposal: true,
          error: 'That proposal expired. Ask Fund Flow to prepare it again.',
        ),
      );
      return;
    }
    final applied = await _applyAgentProposal(proposal);
    if (!applied) {
      await ref
          .read(storeProvider)
          .setProposalStatus(proposal.id!, AgentProposalStatus.stale);
      state = AsyncData(
        _value.copyWith(
          clearPendingAgentProposal: true,
          error: 'The affected data changed. Nothing was applied.',
        ),
      );
      return;
    }
    await ref
        .read(storeProvider)
        .setProposalStatus(proposal.id!, AgentProposalStatus.approved);
    state = AsyncData(
      _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
        conversation: await ref.read(storeProvider).conversation(),
        preferences: _value.preferences,
        clearPendingAgentProposal: true,
        lastAgentAction: proposal.title,
        clearError: true,
      ),
    );
  }

  Future<bool> _applyAgentProposal(AgentProposal proposal) async {
    final arguments = proposal.arguments;
    switch (proposal.kind) {
      case AgentProposalKind.createTransaction:
        final value = _transactionFromArguments(arguments);
        await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: [value],
              deletes: const [],
              undoKind: 'delete_created_transaction',
              undoPayload: {'createdAt': DateTime.now().toIso8601String()},
            );
        return true;
      case AgentProposalKind.updateTransaction:
        final id = arguments['id'] as int;
        final matches = _value.transactions.where((item) => item.id == id);
        if (matches.length != 1) return false;
        final before = matches.single;
        final after = _transactionFromArguments(arguments, existing: before);
        await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: [after],
              deletes: const [],
              undoKind: 'restore_transaction',
              undoPayload: {'transaction': before.toMap()},
            );
        return true;
      case AgentProposalKind.deleteTransaction:
        final id = arguments['id'] as int;
        final matches = _value.transactions.where((item) => item.id == id);
        if (matches.length != 1) return false;
        await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: const [],
              deletes: [id],
              undoKind: 'restore_transaction',
              undoPayload: {'transaction': matches.single.toMap()},
            );
        return true;
      case AgentProposalKind.bulkCategory:
        final ids = (arguments['ids'] as List).cast<int>();
        final category = arguments['category'].toString().trim();
        final matches = _value.transactions
            .where((item) => ids.contains(item.id))
            .toList();
        if (matches.length != ids.toSet().length || category.isEmpty) {
          return false;
        }
        await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: matches.map((item) => item.copyWith(category: category)),
              deletes: const [],
              undoKind: 'restore_transactions',
              undoPayload: {
                'transactions': matches.map((item) => item.toMap()).toList(),
              },
            );
        return true;
      case AgentProposalKind.updateSettings:
        var preferences = _value.preferences;
        final appearance = arguments['appearance']?.toString();
        if (appearance != null) {
          preferences = preferences.copyWith(
            appearance: AppearancePreference.values.byName(appearance),
          );
        }
        if (arguments['currency'] != null) {
          preferences = preferences.copyWith(
            currency: arguments['currency'].toString().toUpperCase(),
          );
        }
        if (arguments['hideAmounts'] is bool) {
          preferences = preferences.copyWith(
            hideAmounts: arguments['hideAmounts'] as bool,
          );
        }
        if (arguments['messageLookbackDays'] is int) {
          preferences = preferences.copyWith(
            messageLookbackDays: arguments['messageLookbackDays'] as int,
          );
        }
        await ref.read(storeProvider).saveUndo('restore_settings', {
          'appearance': _value.preferences.appearance.name,
          'currency': _value.preferences.currency,
          'hideAmounts': _value.preferences.hideAmounts,
          'messageLookbackDays': _value.preferences.messageLookbackDays,
          'captureNotifications': _value.preferences.captureNotifications,
        });
        await updatePreferences(preferences);
        if (arguments['captureNotifications'] is bool) {
          return setNotificationCapture(
            arguments['captureNotifications'] as bool,
          );
        }
        return true;
      case AgentProposalKind.setAppLock:
        await ref.read(storeProvider).saveUndo('restore_app_lock', {
          'enabled': _value.preferences.lockApp,
        });
        return setAppLock(arguments['enabled'] as bool);
      case AgentProposalKind.clearConversation:
        await clearConversation();
        return true;
      case AgentProposalKind.setMemory:
        final key = arguments['key']?.toString().trim() ?? '';
        final value = arguments['value']?.toString().trim() ?? '';
        if (key.isEmpty ||
            value.isEmpty ||
            key.length > 80 ||
            value.length > 240) {
          return false;
        }
        final existing = await ref.read(storeProvider).financialMemory();
        final previous = existing
            .where((item) => item['key'] == key)
            .map((item) => item['value'])
            .firstOrNull;
        await ref.read(storeProvider).saveUndo('restore_memory', {
          'key': key,
          'value': previous,
        });
        await ref.read(storeProvider).setFinancialMemory(key, value);
        return true;
      case AgentProposalKind.deleteMemory:
        final key = arguments['key']?.toString().trim() ?? '';
        if (key.isEmpty) return false;
        final existing = await ref.read(storeProvider).financialMemory();
        final previous = existing
            .where((item) => item['key'] == key)
            .map((item) => item['value'])
            .firstOrNull;
        if (previous == null) return false;
        await ref.read(storeProvider).saveUndo('restore_memory', {
          'key': key,
          'value': previous,
        });
        await ref.read(storeProvider).deleteFinancialMemory(key);
        return true;
    }
  }

  Future<void> undoLastAgentAction() async {
    final record = await ref.read(storeProvider).latestUndo();
    if (record == null) return;
    if (record.kind == 'restore_settings') {
      final payload = record.payload;
      final preferences = _value.preferences.copyWith(
        appearance: AppearancePreference.values.byName(
          payload['appearance'].toString(),
        ),
        currency: payload['currency'].toString(),
        hideAmounts: payload['hideAmounts'] as bool,
        messageLookbackDays: payload['messageLookbackDays'] as int,
      );
      await updatePreferences(preferences);
      final capture = payload['captureNotifications'] as bool;
      if (capture != preferences.captureNotifications) {
        await setNotificationCapture(capture);
      }
      await ref.read(storeProvider).consumeUndo(record.id);
    } else if (record.kind == 'restore_app_lock') {
      await setAppLock(record.payload['enabled'] as bool);
      await ref.read(storeProvider).consumeUndo(record.id);
    } else if (record.kind == 'restore_memory') {
      final key = record.payload['key'].toString();
      final value = record.payload['value'];
      if (value == null) {
        await ref.read(storeProvider).deleteFinancialMemory(key);
      } else {
        await ref.read(storeProvider).setFinancialMemory(key, value.toString());
      }
      await ref.read(storeProvider).consumeUndo(record.id);
    } else {
      await ref.read(storeProvider).applyTransactionUndo(record);
    }
    state = AsyncData(
      _value.copyWith(
        transactions: await ref.read(storeProvider).transactions(),
        clearLastAgentAction: true,
        clearError: true,
      ),
    );
  }

  MoneyTransaction _transactionFromArguments(
    Map<String, Object?> arguments, {
    MoneyTransaction? existing,
  }) {
    final occurredAt = arguments['occurredAt'] == null
        ? existing?.occurredAt ?? DateTime.now()
        : DateTime.parse(arguments['occurredAt'].toString()).toLocal();
    return MoneyTransaction(
      id: existing?.id,
      amountMinor:
          arguments['amountMinor'] as int? ?? existing?.amountMinor ?? 0,
      currency:
          arguments['currency']?.toString().toUpperCase() ??
          existing?.currency ??
          _value.preferences.currency,
      direction: arguments['direction'] == null
          ? existing?.direction ?? TransactionDirection.outgoing
          : TransactionDirection.values.byName(
              arguments['direction'].toString(),
            ),
      merchant:
          arguments['merchant']?.toString().trim() ??
          existing?.merchant ??
          'Transaction',
      category:
          arguments['category']?.toString().trim() ??
          existing?.category ??
          'Other',
      occurredAt: occurredAt,
      source: existing?.source ?? TransactionSource.manual,
      reviewState: existing?.reviewState ?? ReviewState.confirmed,
      confidence: existing?.confidence ?? 1,
      account: arguments['account']?.toString() ?? existing?.account,
      note: arguments['note']?.toString() ?? existing?.note,
      sourceText: existing?.sourceText,
    );
  }
}
