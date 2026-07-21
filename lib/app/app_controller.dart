import 'dart:async';
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
import '../ingestion/notification_source.dart';
import '../ingestion/sms_source.dart';
import '../intelligence/ai_client.dart';
import '../update/app_updater.dart';
import 'app_state.dart';

const _maximumIngestionMessages = 12;

/// Batches analyzed concurrently.
///
/// Output-token generation dominates import wall clock, and total output
/// tokens are roughly fixed regardless of batch size, so parallelism is the
/// only lever that actually shortens the import. Unlike dropping messages
/// before they reach the model, it cannot cost recall. Held at five to stay
/// under provider rate limits, above which retries erase the gain.
const _ingestionConcurrency = 5;

List<List<T>> _ingestionBatches<T>(List<T> values) {
  final batches = <List<T>>[];
  for (
    var start = 0;
    start < values.length;
    start += _maximumIngestionMessages
  ) {
    final count = (values.length - start).clamp(0, _maximumIngestionMessages);
    batches.add(values.sublist(start, start + count));
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
  bool _lifecycleImportPaused = false;
  bool _refreshingNotifications = false;
  Completer<void>? _importResumeSignal;
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
      store.conversationThreads(),
    ]);
    final initial = AppState(
      preferences: prefs,
      transactions: values[0] as List<MoneyTransaction>,
      // Launch lands on an empty chat rather than resuming the last one.
      // Reopening mid-thread makes the previous answer look like a reply to
      // whatever gets asked next; earlier threads stay one tap away.
      conversation: const [],
      activeThreadId: null,
      threads: values[1] as List<ConversationThread>,
      aiConnection: key.isEmpty
          ? AiConnection.disconnected
          : AiConnection.connected,
      locked: prefs.lockApp,
    );
    if (prefs.captureNotifications && !prefs.lockApp && key.isNotEmpty) {
      unawaited(Future<void>(() => _refreshPendingNotifications()));
    }
    // Reading new messages on launch, unawaited so the UI paints first — the
    // ledger is already in [initial] and fresh transactions stream in behind
    // it. Rate-limited and permission-gated inside, so a relaunch seconds
    // later does not re-scan or spend tokens.
    if (!prefs.lockApp && key.isNotEmpty) {
      unawaited(Future<void>(_maybeAutoSync));
    }
    return initial;
  }

  /// How recently a sync must have run for launch to skip starting another.
  static const _autoSyncCooldown = Duration(minutes: 30);

  /// Starts a background message sync on launch unless one ran recently.
  ///
  /// Gated on message permission being already granted: launch is the wrong
  /// moment to raise a permission dialog nobody asked for, so a first run
  /// with no permission stays silent and the manual button or onboarding
  /// prompts for it instead.
  Future<void> _maybeAutoSync() async {
    if (!state.hasValue || _value.locked) return;
    if (_value.importStatus.working) return;
    final source = ref.read(smsSourceProvider);
    if (await source.permission(request: false) != MessagePermission.granted) {
      return;
    }
    final runs = await ref.read(storeProvider).importRuns(limit: 1);
    final last = runs.isEmpty ? null : runs.first.startedAt;
    if (last != null && DateTime.now().difference(last) < _autoSyncCooldown) {
      return;
    }
    await importMessages();
  }

  Future<void> _refreshPendingNotifications() async {
    if (_refreshingNotifications || !state.hasValue || _value.locked) return;
    final preferences = _value.preferences;
    if (!preferences.captureNotifications) return;
    _refreshingNotifications = true;
    try {
      final key = await ref.read(securePreferencesProvider).apiKey();
      final transactions = await _drainNotifications(
        _value.transactions,
        key,
        preferences,
      );
      if (state.hasValue) {
        state = AsyncData(_value.copyWith(transactions: transactions));
      }
    } finally {
      _refreshingNotifications = false;
    }
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
      final batches = _ingestionBatches(unseen);
      for (var wave = 0; wave < batches.length; wave += _ingestionConcurrency) {
        final end = (wave + _ingestionConcurrency).clamp(0, batches.length);
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
                // Notifications arrive one at a time while someone is using
                // the app, so this path is the most latency sensitive of the
                // two. Audit payloads are written after the fact.
                unawaited(_recordBatchExchanges(batchId, requests, responses));
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
    if (ok) {
      state = AsyncData(_value.copyWith(locked: false, clearError: true));
      resumeMessageImportForLifecycle();
      unawaited(_refreshPendingNotifications());
    }
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
    String? chatModel,
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
      aiChatModel: chatModel,
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

  /// Leaves the current thread for a fresh one.
  ///
  /// Any run in flight is cancelled first: an answer that arrived after the
  /// move would be written to a thread the person is no longer reading, and
  /// a pending proposal belongs to the exchange that produced it.
  Future<void> startNewChat() async {
    _activeRun?.cancel();
    _activeRun = null;
    state = AsyncData(
      _value.copyWith(
        conversation: const [],
        clearActiveThreadId: true,
        threads: await ref.read(storeProvider).conversationThreads(),
        asking: false,
        askStage: null,
        clearAskDraft: true,
        clearError: true,
        clearPendingAgentProposal: true,
        clearLastAgentAction: true,
      ),
    );
  }

  Future<void> openConversationThread(int threadId) async {
    _activeRun?.cancel();
    _activeRun = null;
    final store = ref.read(storeProvider);
    state = AsyncData(
      _value.copyWith(
        activeThreadId: threadId,
        conversation: await store.conversation(threadId: threadId),
        threads: await store.conversationThreads(),
        asking: false,
        askStage: null,
        clearAskDraft: true,
        clearError: true,
        clearPendingAgentProposal: true,
        clearLastAgentAction: true,
      ),
    );
  }

  Future<void> deleteConversationThread(int threadId) async {
    await ref.read(storeProvider).deleteConversationThread(threadId);
    // Deleting the thread being read leaves nowhere to return to, so it
    // becomes a new chat rather than an empty view of something gone.
    if (_value.activeThreadId == threadId) {
      await startNewChat();
      return;
    }
    state = AsyncData(
      _value.copyWith(
        threads: await ref.read(storeProvider).conversationThreads(),
      ),
    );
  }

  /// Clears the thread being read, which is what the agent proposal offers.
  Future<void> clearConversation() async {
    final threadId = _value.activeThreadId;
    if (threadId == null) {
      await startNewChat();
      return;
    }
    await deleteConversationThread(threadId);
  }

  Future<void> importMessages() async {
    _stopImportRequested = false;
    _clearLifecycleImportPause();
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
    await _waitWhileLifecyclePaused(
      permission: permission,
      checked: 0,
      imported: 0,
      skipped: 0,
    );
    if (_stopImportRequested) {
      _setImportStopped(permission: permission);
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
      await _waitWhileLifecyclePaused(
        permission: permission,
        checked: 0,
        imported: 0,
        skipped: 0,
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
      // Held across the run and extended per batch, so each finished batch
      // reaches the ledger immediately without re-reading the table.
      var ledger = _value.transactions;
      final batches = _ingestionBatches(unseen);
      for (var wave = 0; wave < batches.length; wave += _ingestionConcurrency) {
        await _waitWhileLifecyclePaused(
          permission: permission,
          checked: checked,
          imported: imported,
          skipped: skipped,
        );
        if (_stopImportRequested) {
          await ref
              .read(storeProvider)
              .finishImportRun(auditRunId, state: ImportRunState.stopped);
          state = AsyncData(
            _value.copyWith(
              transactions: ledger,
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
        final end = (wave + _ingestionConcurrency).clamp(0, batches.length);
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
                // Audit payloads carry the whole request and response, several
                // kilobytes per batch. They are for later inspection, so they
                // are written off the critical path rather than delaying the
                // transactions this batch just produced.
                unawaited(_recordBatchExchanges(batchId, requests, responses));
                final created = await ref
                    .read(storeProvider)
                    .commitIngestionBatch(
                      analysis,
                      runId: activeRunId,
                      batchId: batchId,
                    );
                imported += created.length;
                // Extend the list already held instead of re-reading every
                // transaction. Re-querying cost grew with each batch, so a
                // late batch paid for everything the earlier ones inserted.
                if (created.isNotEmpty) {
                  ledger = [...created, ...ledger]
                    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
                }
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
                  transactions: ledger,
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
      _clearLifecycleImportPause();
      current = _value.copyWith(
        transactions: ledger,
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
      _clearLifecycleImportPause();
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
      _clearLifecycleImportPause();
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

  /// Writes the request and response payloads for later inspection.
  ///
  /// Failures are swallowed: an audit record is diagnostic, and losing one
  /// must never surface as an import error over transactions that were
  /// committed successfully.
  Future<void> _recordBatchExchanges(
    int batchId,
    List<String> requests,
    List<String> responses,
  ) async {
    try {
      final store = ref.read(storeProvider);
      if (requests.isNotEmpty) {
        await store.recordImportBatchRequest(
          batchId,
          _auditExchanges(requests),
        );
      }
      if (responses.isNotEmpty) {
        await store.recordImportBatchResponse(
          batchId,
          _auditExchanges(responses),
        );
      }
    } catch (_) {
      // Diagnostic only.
    }
  }

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
    _clearLifecycleImportPause();
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

  void pauseMessageImportForLifecycle() {
    if (!_value.importStatus.working || _lifecycleImportPaused) return;
    _lifecycleImportPaused = true;
    state = AsyncData(
      _value.copyWith(
        importStatus: ImportStatus(
          phase: ImportPhase.paused,
          permission: _value.importStatus.permission,
          checked: _value.importStatus.checked,
          imported: _value.importStatus.imported,
          skipped: _value.importStatus.skipped,
          message: 'Pausing safely after the current AI batch…',
        ),
      ),
    );
  }

  void resumeMessageImportForLifecycle() {
    if (!_lifecycleImportPaused || _value.locked) return;
    _lifecycleImportPaused = false;
    final signal = _importResumeSignal;
    _importResumeSignal = null;
    if (signal != null && !signal.isCompleted) signal.complete();
    if (_value.importStatus.phase == ImportPhase.paused) {
      state = AsyncData(
        _value.copyWith(
          importStatus: ImportStatus(
            phase: ImportPhase.understanding,
            permission: _value.importStatus.permission,
            checked: _value.importStatus.checked,
            imported: _value.importStatus.imported,
            skipped: _value.importStatus.skipped,
            message: 'Resuming message analysis…',
          ),
        ),
      );
    }
  }

  Future<void> _waitWhileLifecyclePaused({
    required MessagePermission permission,
    required int checked,
    required int imported,
    required int skipped,
  }) async {
    if (!_lifecycleImportPaused) return;
    state = AsyncData(
      _value.copyWith(
        importStatus: ImportStatus(
          phase: ImportPhase.paused,
          permission: permission,
          checked: checked,
          imported: imported,
          skipped: skipped,
          message: _value.locked
              ? 'Paused · unlock Fund Flow to continue safely'
              : 'Paused · return to Fund Flow to continue safely',
        ),
      ),
    );
    _importResumeSignal ??= Completer<void>();
    await _importResumeSignal!.future;
  }

  void _clearLifecycleImportPause() {
    _lifecycleImportPaused = false;
    final signal = _importResumeSignal;
    _importResumeSignal = null;
    if (signal != null && !signal.isCompleted) signal.complete();
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
    final store = ref.read(storeProvider);
    // Created on the first question, so an opened and abandoned chat never
    // leaves an empty row in history.
    final threadId =
        _value.activeThreadId ??
        await store.createConversationThread(
          ConversationThread.titleFrom(trimmed),
        );
    // Retrying asks the same question again, and the failed attempt already
    // left it in the thread. Writing it a second time makes the transcript
    // read as though the person asked twice.
    final last = _value.conversation.lastOrNull;
    final alreadyAsked =
        _value.retryQuestion == trimmed &&
        last != null &&
        last.author == MessageAuthor.person &&
        last.text.trim() == trimmed;
    if (!alreadyAsked) await store.addMessage(user, threadId: threadId);
    state = AsyncData(
      _value.copyWith(
        activeThreadId: threadId,
        conversation: await store.conversation(threadId: threadId),
        threads: await store.conversationThreads(),
        asking: true,
        askStage: 'Checking your activity',
        clearError: true,
        clearRetryQuestion: true,
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
          // The agent orchestrates tools across turns; the parsing model is
          // tuned for single-pass structured extraction instead.
          model: _value.preferences.aiChatModel,
        ),
        server: server,
      );
      final token = AgentCancellationToken();
      _activeRun = token;
      final history = _value.conversation
          .where((message) => message.providerContent.trim().isNotEmpty)
          .toList()
          .reversed
          // Keep the hot prompt small. Older turns remain available through
          // the local conversation_search MCP capability when they matter.
          .take(6)
          .toList()
          .reversed
          .map(
            (message) => <String, Object?>{
              'role': message.author == MessageAuthor.person
                  ? 'user'
                  : 'assistant',
              // Replay figures, not just prose, so follow-up questions can
              // build on what was already reported.
              'content': message.providerContent,
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
      // Everything the run actually checked, not just what the answer cites:
      // a briefing reads the whole ledger without listing a single row, and
      // "checked against 0" under it reads as an unverified answer.
      final supportingIds = <int>{...result.evidenceTransactionIds};
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
      final messageId = await ref
          .read(storeProvider)
          .addMessage(assistant, threadId: _value.activeThreadId);
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
          conversation: await ref
              .read(storeProvider)
              .conversation(threadId: _value.activeThreadId),
          threads: await ref.read(storeProvider).conversationThreads(),
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
          'Reconnect intelligence in settings.',
        AiRequestFailure(statusCode: 429) =>
          'The provider is busy. Try again shortly.',
        // A retired or unknown model answers 404 or 410 and names itself in
        // the body. Repeating that is the difference between someone
        // changing one setting and having no idea what went wrong.
        AiRequestFailure(statusCode: 404 || 410, :final detail?) =>
          'The chat model is unavailable: $detail Choose another in '
              'settings under Advanced options.',
        AiRequestFailure(:final detail?) => detail,
        AgentRunException(:final message) => message,
        // A phone loses signal mid-answer often enough that "could not be
        // completed" is a poor description of the most common failure.
        SocketException() || HttpException() =>
          'No connection reached the provider. Your records are all local '
              'and unchanged.',
        TimeoutException() =>
          'The provider stopped responding. Nothing was changed.',
        _ =>
          'The answer could not be completed. Your activity was not changed.',
      };
      state = AsyncData(
        _value.copyWith(
          asking: false,
          askStage: null,
          clearAskDraft: true,
          error: message,
          // Hold the question so a failure costs a tap rather than retyping
          // it. Losing what someone just asked is its own small insult on
          // top of the failure.
          retryQuestion: question,
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
    // The apply path reads model-supplied arguments and touches the database,
    // and both can fail after the person has already tapped Approve. Whatever
    // goes wrong, they get a refusal saying nothing changed rather than an
    // uncaught error: the store wraps each change in a transaction, so a
    // throw means it rolled back.
    ({bool applied, int? undoId}) outcome;
    try {
      outcome = await _applyAgentProposal(proposal);
    } catch (_) {
      outcome = (applied: false, undoId: null);
    }
    if (!outcome.applied) {
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
        conversation: await ref
            .read(storeProvider)
            .conversation(threadId: _value.activeThreadId),
        threads: await ref.read(storeProvider).conversationThreads(),
        preferences: _value.preferences,
        clearPendingAgentProposal: true,
        lastAgentAction: proposal.title,
        lastAgentUndoId: outcome.undoId,
        clearError: true,
      ),
    );
  }

  /// An integer argument, or null when the provider sent something else.
  ///
  /// These arrive from a language model, so `id` can be `7`, `7.0`, `"7"` or
  /// absent. A bare cast turned the last two into an uncaught error thrown
  /// after the person had already tapped Approve; reading them defensively
  /// turns the same input into a refusal they can act on.
  int? _intArgument(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is int) return value;
    if (value is num && value == value.roundToDouble()) return value.toInt();
    return null;
  }

  List<int>? _intListArgument(Map<String, Object?> arguments, String key) {
    final value = arguments[key];
    if (value is! List || value.isEmpty) return null;
    final ids = <int>[];
    for (final item in value) {
      if (item is int) {
        ids.add(item);
      } else if (item is num && item == item.roundToDouble()) {
        ids.add(item.toInt());
      } else {
        return null;
      }
    }
    return ids;
  }

  /// Whether the records still say what the proposal was written against.
  ///
  /// A proposal older than a moment can name a row that has since been
  /// recategorised or corrected by hand. Approving it would silently
  /// overwrite work the person did after the agent proposed the change.
  bool _matchesFingerprint(
    AgentProposal proposal,
    List<MoneyTransaction> current,
  ) {
    if (proposal.affectedFingerprint.isEmpty) return true;
    for (final item in current) {
      final expected = proposal.affectedFingerprint[item.id];
      if (expected == null) continue;
      final actual = AgentProposal.fingerprintOf(
        amountMinor: item.amountMinor,
        currency: item.currency,
        merchant: item.merchant,
        category: item.category,
        occurredAt: item.occurredAt,
      );
      if (actual != expected) return false;
    }
    return true;
  }

  /// Applies an approved proposal.
  ///
  /// [undoId] is the record that reverses this particular change, or null
  /// when the change cannot be reversed. Undo used to pop whichever record
  /// was newest, which reversed something unrelated whenever the action
  /// itself saved none.
  Future<({bool applied, int? undoId})> _applyAgentProposal(
    AgentProposal proposal,
  ) async {
    const refused = (applied: false, undoId: null);
    final arguments = proposal.arguments;
    switch (proposal.kind) {
      case AgentProposalKind.createTransaction:
        final value = _transactionFromArguments(arguments);
        if (value == null) return refused;
        final undoId = await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: [value],
              deletes: const [],
              undoKind: 'delete_created_transaction',
              undoPayload: {'createdAt': DateTime.now().toIso8601String()},
            );
        return (applied: true, undoId: undoId);
      case AgentProposalKind.updateTransaction:
        final id = _intArgument(arguments, 'id');
        if (id == null) return refused;
        final matches = _value.transactions.where((item) => item.id == id);
        if (matches.length != 1) return refused;
        final before = matches.single;
        if (!_matchesFingerprint(proposal, [before])) return refused;
        final after = _transactionFromArguments(arguments, existing: before);
        if (after == null) return refused;
        final undoId = await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: [after],
              deletes: const [],
              undoKind: 'restore_transaction',
              undoPayload: {'transaction': before.toMap()},
            );
        return (applied: true, undoId: undoId);
      case AgentProposalKind.deleteTransaction:
        final id = _intArgument(arguments, 'id');
        if (id == null) return refused;
        final matches = _value.transactions.where((item) => item.id == id);
        if (matches.length != 1) return refused;
        if (!_matchesFingerprint(proposal, [matches.single])) return refused;
        final undoId = await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: const [],
              deletes: [id],
              undoKind: 'restore_transaction',
              undoPayload: {'transaction': matches.single.toMap()},
            );
        return (applied: true, undoId: undoId);
      case AgentProposalKind.bulkCategory:
        final ids = _intListArgument(arguments, 'ids');
        if (ids == null) return refused;
        final category = arguments['category']?.toString().trim() ?? '';
        final matches = _value.transactions
            .where((item) => ids.contains(item.id))
            .toList();
        if (matches.length != ids.toSet().length || category.isEmpty) {
          return refused;
        }
        if (!_matchesFingerprint(proposal, matches)) return refused;
        final undoId = await ref
            .read(storeProvider)
            .applyTransactionChanges(
              upserts: matches.map((item) => item.copyWith(category: category)),
              deletes: const [],
              undoKind: 'restore_transactions',
              undoPayload: {
                'transactions': matches.map((item) => item.toMap()).toList(),
              },
            );
        return (applied: true, undoId: undoId);
      case AgentProposalKind.updateSettings:
        var preferences = _value.preferences;
        final appearance = arguments['appearance']?.toString();
        if (appearance != null) {
          // Schema validation rejects an unknown name before a proposal is
          // ever built, but proposals outlive the turn that made them and
          // are read back from storage, so this refuses rather than throws.
          final match = AppearancePreference.values.where(
            (value) => value.name == appearance,
          );
          if (match.length != 1) return refused;
          preferences = preferences.copyWith(appearance: match.single);
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
        final settingsUndoId = await ref
            .read(storeProvider)
            .saveUndo('restore_settings', {
              'appearance': _value.preferences.appearance.name,
              'currency': _value.preferences.currency,
              'hideAmounts': _value.preferences.hideAmounts,
              'messageLookbackDays': _value.preferences.messageLookbackDays,
              'captureNotifications': _value.preferences.captureNotifications,
            });
        await updatePreferences(preferences);
        if (arguments['captureNotifications'] is bool) {
          final capture = await setNotificationCapture(
            arguments['captureNotifications'] as bool,
          );
          return (applied: capture, undoId: capture ? settingsUndoId : null);
        }
        return (applied: true, undoId: settingsUndoId);
      case AgentProposalKind.setAppLock:
        final enabled = arguments['enabled'];
        if (enabled is! bool) return refused;
        final lockUndoId = await ref.read(storeProvider).saveUndo(
          'restore_app_lock',
          {'enabled': _value.preferences.lockApp},
        );
        final locked = await setAppLock(enabled);
        return (applied: locked, undoId: locked ? lockUndoId : null);
      case AgentProposalKind.clearConversation:
        await clearConversation();
        // Deliberately not reversible: there is no record to restore from,
        // which is why the proposal is marked irreversible and Undo is not
        // offered afterwards.
        return (applied: true, undoId: null);
      case AgentProposalKind.setMemory:
        final key = arguments['key']?.toString().trim() ?? '';
        final value = arguments['value']?.toString().trim() ?? '';
        if (key.isEmpty ||
            value.isEmpty ||
            key.length > 80 ||
            value.length > 240) {
          return refused;
        }
        final existing = await ref.read(storeProvider).financialMemory();
        final previous = existing
            .where((item) => item['key'] == key)
            .map((item) => item['value'])
            .firstOrNull;
        final memoryUndoId = await ref.read(storeProvider).saveUndo(
          'restore_memory',
          {'key': key, 'value': previous},
        );
        await ref.read(storeProvider).setFinancialMemory(key, value);
        return (applied: true, undoId: memoryUndoId);
      case AgentProposalKind.deleteMemory:
        final key = arguments['key']?.toString().trim() ?? '';
        if (key.isEmpty) return refused;
        final existing = await ref.read(storeProvider).financialMemory();
        final previous = existing
            .where((item) => item['key'] == key)
            .map((item) => item['value'])
            .firstOrNull;
        if (previous == null) return refused;
        final deleteUndoId = await ref.read(storeProvider).saveUndo(
          'restore_memory',
          {'key': key, 'value': previous},
        );
        await ref.read(storeProvider).deleteFinancialMemory(key);
        return (applied: true, undoId: deleteUndoId);
    }
  }

  Future<void> undoLastAgentAction() async {
    // The record this action wrote, not merely the newest one. Reaching for
    // the newest reversed whatever happened to be last whenever the action
    // itself saved nothing to reverse.
    final undoId = _value.lastAgentUndoId;
    if (undoId == null) return;
    final record = await ref.read(storeProvider).undoById(undoId);
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

  /// Builds a transaction from proposal arguments, or null when they do not
  /// describe one. An unparseable date or an unknown direction is a refusal,
  /// not an exception thrown after the person tapped Approve.
  MoneyTransaction? _transactionFromArguments(
    Map<String, Object?> arguments, {
    MoneyTransaction? existing,
  }) {
    final DateTime occurredAt;
    if (arguments['occurredAt'] == null) {
      occurredAt = existing?.occurredAt ?? DateTime.now();
    } else {
      final parsed = DateTime.tryParse(arguments['occurredAt'].toString());
      if (parsed == null) return null;
      occurredAt = parsed.toLocal();
    }
    final TransactionDirection direction;
    if (arguments['direction'] == null) {
      direction = existing?.direction ?? TransactionDirection.outgoing;
    } else {
      final match = TransactionDirection.values.where(
        (value) => value.name == arguments['direction'].toString(),
      );
      if (match.length != 1) return null;
      direction = match.single;
    }
    final amountMinor = _intArgument(arguments, 'amountMinor');
    if (arguments['amountMinor'] != null && amountMinor == null) return null;
    return MoneyTransaction(
      id: existing?.id,
      amountMinor: amountMinor ?? existing?.amountMinor ?? 0,
      currency:
          arguments['currency']?.toString().toUpperCase() ??
          existing?.currency ??
          _value.preferences.currency,
      direction: direction,
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
