import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../app/app_controller.dart';
import '../app/app_state.dart';
import '../domain/ai_provider.dart';
import '../domain/import_audit.dart';
import 'zero_intelligence.dart';
import 'zero_theme.dart';

Future<void> showZeroAutomation(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ZeroAutomationSheet(),
    );

class ZeroAutomationSheet extends ConsumerStatefulWidget {
  const ZeroAutomationSheet({super.key});

  @override
  ConsumerState<ZeroAutomationSheet> createState() =>
      _ZeroAutomationSheetState();
}

class _ZeroAutomationSheetState extends ConsumerState<ZeroAutomationSheet> {
  Timer? timer;
  List<ImportRunRecord> runs = const [];
  List<ImportItemRecord> items = const [];
  List<ImportBatchRecord> batches = const [];
  int? selectedRun;
  bool loading = true;
  bool auditOpen = false;
  ImportItemState? filter;
  final search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _load(quiet: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final store = ref.read(storeProvider);
    final nextRuns = await store.importRuns();
    final id = selectedRun ?? nextRuns.firstOrNull?.id;
    final results = id == null
        ? const <List<Object>>[[], []]
        : await Future.wait<List<Object>>([
            store.importItems(id),
            store.importBatches(id),
          ]);
    if (!mounted) return;
    setState(() {
      runs = nextRuns;
      selectedRun = id;
      items = results[0].cast<ImportItemRecord>();
      batches = results[1].cast<ImportBatchRecord>();
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    final status = app.importStatus;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .94,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Message automation',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _statusText(status),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _statusColor(context, status),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          if (status.working) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                _Boundary(app: app),
                const SizedBox(height: 22),
                if (status.permission != null &&
                    status.permission!.name != 'granted')
                  _PermissionRecovery(status: status),
                FilledButton.icon(
                  onPressed: status.working
                      ? controller.stopMessageImport
                      : controller.importMessages,
                  icon: Icon(
                    status.working ? Icons.stop_rounded : Icons.sms_outlined,
                  ),
                  label: Text(
                    status.working
                        ? 'Stop safely'
                        : status.retryable
                        ? 'Try message check again'
                        : 'Check recent messages',
                  ),
                ),
                const SizedBox(height: 10),
                _CaptureRow(
                  value: app.preferences.captureNotifications,
                  onChanged: controller.setNotificationCapture,
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'What Fund Flow decided',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: runs.isEmpty
                          ? null
                          : () => setState(() => auditOpen = !auditOpen),
                      child: Text(auditOpen ? 'Hide audit' : 'Open audit'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (runs.isEmpty)
                  _AuditEmpty(
                    connected: app.aiConnection == AiConnection.connected,
                  )
                else ...[
                  _RunPicker(
                    runs: runs,
                    selected: selectedRun,
                    onChanged: (id) async {
                      setState(() {
                        selectedRun = id;
                        loading = true;
                      });
                      await _load();
                    },
                  ),
                  const SizedBox(height: 14),
                  if (runs.where((run) => run.id == selectedRun).firstOrNull
                      case final run?)
                    _RunSummary(run: run),
                  if (auditOpen) ...[
                    const SizedBox(height: 22),
                    _AuditFilters(
                      items: items,
                      value: filter,
                      onChanged: (value) => setState(() => filter = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Search sender, message or reason',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Center(child: CircularProgressIndicator())
                    else
                      for (final item in _visible) _DecisionRow(item: item),
                    if (!loading && _visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Text(
                          items.isEmpty
                              ? 'No messages belong to this run.'
                              : 'No decisions match this view.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: context.zero.muted),
                        ),
                      ),
                    if (batches.isNotEmpty) _ProviderEvidence(batches: batches),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _clear,
                      style: TextButton.styleFrom(
                        foregroundColor: context.zero.negative,
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Clear message audit history'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<ImportItemRecord> get _visible {
    final query = search.text.toLowerCase().trim();
    return items.where((item) {
      if (filter != null && item.state != filter) return false;
      if (query.isEmpty) return true;
      return '${item.sender ?? ''} ${item.body} ${item.reason ?? ''}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  Future<void> _clear() async {
    final accepted = await zeroConfirm(
      context,
      title: 'Clear message audit?',
      body:
          'Stored message bodies and provider request logs will be removed. Transactions and duplicate-detection records remain.',
      action: 'Clear audit',
    );
    if (!accepted) return;
    await ref.read(storeProvider).clearImportAudit();
    selectedRun = null;
    await _load();
  }
}

class _Boundary extends StatelessWidget {
  const _Boundary({required this.app});
  final AppState app;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.zero.subtle,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, color: context.zero.positive, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            app.aiConnection == AiConnection.connected
                ? 'Messages are read only when you start a check. Relevant text goes to ${providerInfo(app.preferences.aiProvider).label}; normalized transactions stay local.'
                : 'Connect intelligence before checking messages. No inbox content is read while disconnected.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _PermissionRecovery extends StatelessWidget {
  const _PermissionRecovery({required this.status});
  final ImportStatus status;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline_rounded,
          color: context.zero.warning,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            status.message ??
                'Message permission is needed for an inbox check.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

class _CaptureRow extends StatelessWidget {
  const _CaptureRow({required this.value, required this.onChanged});
  final bool value;
  final Future<bool> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => onChanged(!value),
    borderRadius: BorderRadius.circular(16),
    child: Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.zero.line)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_none_rounded),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Capture future payment notifications',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Android will ask for notification access.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
                ),
              ],
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class _RunPicker extends StatelessWidget {
  const _RunPicker({
    required this.runs,
    required this.selected,
    required this.onChanged,
  });
  final List<ImportRunRecord> runs;
  final int? selected;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 42,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: runs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final run = runs[index];
        final active = selected == run.id;
        return ChoiceChip(
          selected: active,
          onSelected: (_) => onChanged(run.id),
          label: Text(DateFormat('d MMM, HH:mm').format(run.startedAt)),
        );
      },
    ),
  );
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.run});
  final ImportRunRecord run;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          _StateMark(state: run.state),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${run.processed} of ${run.total} checked',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text('${run.imported} added'),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        '${run.source == 'notification' ? 'Notifications' : 'SMS inbox'} · ${run.model}',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
      ),
      if (run.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            run.error!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.zero.negative),
          ),
        ),
    ],
  );
}

class _AuditFilters extends StatelessWidget {
  const _AuditFilters({
    required this.items,
    required this.value,
    required this.onChanged,
  });
  final List<ImportItemRecord> items;
  final ImportItemState? value;
  final ValueChanged<ImportItemState?> onChanged;
  @override
  Widget build(BuildContext context) {
    final values = <ImportItemState?>[
      null,
      ImportItemState.failed,
      ImportItemState.uncertain,
      ImportItemState.transaction,
      ImportItemState.notTransaction,
      ImportItemState.alreadySeen,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final state in values)
          if (state == null || items.any((item) => item.state == state))
            ChoiceChip(
              selected: value == state,
              onSelected: (_) => onChanged(value == state ? null : state),
              label: Text(
                '${_itemLabel(state)} ${state == null ? items.length : items.where((item) => item.state == state).length}',
              ),
            ),
      ],
    );
  }
}

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({required this.item});
  final ImportItemRecord item;
  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 16),
      leading: Icon(
        _itemIcon(item.state),
        color: _itemColor(context, item.state),
      ),
      title: Text(
        item.sender?.trim().isNotEmpty == true
            ? item.sender!
            : 'Unknown sender',
      ),
      subtitle: Text(
        '${_itemLabel(item.state)}${item.reason == null ? '' : ' · ${item.reason}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(item.body),
        ),
        if (item.transactionId != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Created transaction #${item.transactionId}'),
            ),
          ),
      ],
    ),
  );
}

class _ProviderEvidence extends StatefulWidget {
  const _ProviderEvidence({required this.batches});
  final List<ImportBatchRecord> batches;
  @override
  State<_ProviderEvidence> createState() => _ProviderEvidenceState();
}

class _ProviderEvidenceState extends State<_ProviderEvidence> {
  bool open = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      InkWell(
        onTap: () => setState(() => open = !open),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.code_rounded, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${widget.batches.length} provider exchanges'),
              ),
              Icon(
                open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
              ),
            ],
          ),
        ),
      ),
      if (open)
        for (final batch in widget.batches) _JsonEvidence(batch: batch),
    ],
  );
}

class _JsonEvidence extends StatelessWidget {
  const _JsonEvidence({required this.batch});
  final ImportBatchRecord batch;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text('Request ${batch.position + 1} · ${batch.state}'),
    subtitle: batch.error == null ? null : Text(batch.error!),
    children: [
      _JsonBlock(label: 'Sent', value: batch.requestJson),
      const SizedBox(height: 10),
      _JsonBlock(label: 'Returned', value: batch.responseJson ?? 'No response'),
      const SizedBox(height: 14),
    ],
  );
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    var shown = value;
    try {
      shown = const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 240),
          padding: const EdgeInsets.all(12),
          color: context.zero.subtle,
          child: SingleChildScrollView(child: SelectableText(shown)),
        ),
      ],
    );
  }
}

class _AuditEmpty extends StatelessWidget {
  const _AuditEmpty({required this.connected});
  final bool connected;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      connected
          ? 'No checks yet. Start one to see every message decision here.'
          : 'Connect intelligence first, then start a message check.',
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.zero.muted),
    ),
  );
}

class _StateMark extends StatelessWidget {
  const _StateMark({required this.state});
  final ImportRunState state;
  @override
  Widget build(BuildContext context) => Icon(
    switch (state) {
      ImportRunState.completed => Icons.check_circle_outline_rounded,
      ImportRunState.running => Icons.sync_rounded,
      ImportRunState.stopped => Icons.pause_circle_outline_rounded,
      ImportRunState.failed => Icons.error_outline_rounded,
    },
    size: 19,
    color: switch (state) {
      ImportRunState.completed => context.zero.positive,
      ImportRunState.running => context.zero.accent,
      ImportRunState.stopped => context.zero.warning,
      ImportRunState.failed => context.zero.negative,
    },
  );
}

String _statusText(ImportStatus status) => switch (status.phase) {
  ImportPhase.idle => 'Ready when you are',
  ImportPhase.requestingPermission => 'Waiting for message permission',
  ImportPhase.reading => 'Reading recent payment messages',
  ImportPhase.understanding =>
    '${status.checked} checked · ${status.imported} added',
  ImportPhase.paused => 'Paused while Fund Flow is in the background',
  ImportPhase.stopped => 'Stopped safely',
  ImportPhase.rateLimited => 'Provider asked Fund Flow to slow down',
  ImportPhase.providerDisconnected => 'Intelligence connection was lost',
  ImportPhase.invalidResponse => 'The provider returned an invalid response',
  ImportPhase.complete =>
    '${status.checked} checked · ${status.imported} added · ${status.skipped} skipped',
  ImportPhase.error => status.message ?? 'The check could not finish',
};

Color _statusColor(BuildContext context, ImportStatus status) =>
    switch (status.phase) {
      ImportPhase.complete => context.zero.positive,
      ImportPhase.error ||
      ImportPhase.invalidResponse ||
      ImportPhase.providerDisconnected => context.zero.negative,
      ImportPhase.rateLimited || ImportPhase.stopped => context.zero.warning,
      _ => context.zero.muted,
    };

String _itemLabel(ImportItemState? value) => switch (value) {
  null => 'All',
  ImportItemState.queued => 'Queued',
  ImportItemState.alreadySeen => 'Seen',
  ImportItemState.transaction => 'Added',
  ImportItemState.notTransaction => 'Not money',
  ImportItemState.uncertain => 'Review',
  ImportItemState.failed => 'Failed',
};

IconData _itemIcon(ImportItemState value) => switch (value) {
  ImportItemState.queued => Icons.hourglass_top_rounded,
  ImportItemState.alreadySeen => Icons.history_rounded,
  ImportItemState.transaction => Icons.check_circle_outline_rounded,
  ImportItemState.notTransaction => Icons.remove_circle_outline_rounded,
  ImportItemState.uncertain => Icons.help_outline_rounded,
  ImportItemState.failed => Icons.error_outline_rounded,
};

Color _itemColor(BuildContext context, ImportItemState value) =>
    switch (value) {
      ImportItemState.transaction => context.zero.positive,
      ImportItemState.uncertain => context.zero.warning,
      ImportItemState.failed => context.zero.negative,
      _ => context.zero.muted,
    };
