import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/import_audit.dart';
import '../components/flow_field.dart';
import '../tokens/flow_metrics.dart';
import '../tokens/flow_palette.dart';

/// Every message decision, auditable.
///
/// The app's claim is "I read your messages correctly", and this sheet is
/// where that claim can be checked: each run, each message, what the model
/// decided and why, down to the raw provider exchanges. Outcomes filter
/// first because the visit is almost always about the handful that went
/// wrong, not the hundreds that didn't.
class MessageIntelligenceSheet extends ConsumerStatefulWidget {
  const MessageIntelligenceSheet({super.key});

  @override
  ConsumerState<MessageIntelligenceSheet> createState() => _State();
}

class _State extends ConsumerState<MessageIntelligenceSheet> {
  Timer? _timer;
  List<ImportRunRecord> _runs = const [];
  List<ImportItemRecord> _items = const [];
  List<ImportBatchRecord> _batches = const [];
  int? _selectedRun;
  bool _loading = true;

  /// Outcome being shown. Null means everything.
  ImportItemState? _filter;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _load(quiet: true),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Items matching the active outcome filter and search text.
  List<ImportItemRecord> get _visibleItems {
    final query = _search.text.trim().toLowerCase();
    return _items.where((item) {
      if (_filter != null && item.state != _filter) return false;
      if (query.isEmpty) return true;
      return item.body.toLowerCase().contains(query) ||
          (item.sender?.toLowerCase().contains(query) ?? false) ||
          (item.reason?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Map<ImportItemState, int> get _counts {
    final counts = <ImportItemState, int>{};
    for (final item in _items) {
      counts[item.state] = (counts[item.state] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _load({bool quiet = false}) async {
    final store = ref.read(storeProvider);
    final runs = await store.importRuns();
    final selected = _selectedRun ?? (runs.isEmpty ? null : runs.first.id);
    final results = selected == null
        ? const <List<Object>>[[], []]
        : await Future.wait<List<Object>>([
            store.importItems(selected),
            store.importBatches(selected),
          ]);
    if (!mounted) return;
    setState(() {
      _runs = runs;
      _selectedRun = selected;
      _items = results[0].cast<ImportItemRecord>();
      _batches = results[1].cast<ImportBatchRecord>();
      _loading = false;
    });
  }

  Future<void> _select(int id) async {
    setState(() {
      _selectedRun = id;
      _loading = true;
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .92,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            FlowSpace.xl,
            FlowSpace.md,
            FlowSpace.xl,
            FlowSpace.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final information = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Message intelligence', style: text.headlineMedium),
                      const SizedBox(height: FlowSpace.xs),
                      Text(
                        app.importStatus.working
                            ? '${app.importStatus.checked} analyzed · '
                                  '${app.importStatus.imported} added'
                            : 'Every local message decision and Ollama '
                                  'exchange',
                        style: text.bodySmall?.copyWith(color: flow.inkSoft),
                      ),
                    ],
                  );
                  final action = OutlinedButton.icon(
                    onPressed: app.importStatus.working
                        ? controller.stopMessageImport
                        : controller.importMessages,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: flow.line),
                      foregroundColor: flow.ink,
                      shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadius.sm,
                      ),
                    ),
                    icon: Icon(
                      app.importStatus.working
                          ? Icons.stop_rounded
                          : Icons.refresh_rounded,
                      size: 18,
                    ),
                    label: Text(app.importStatus.working ? 'Stop' : 'Check'),
                  );
                  final stacked =
                      box.maxWidth < 390 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.3;
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        information,
                        const SizedBox(height: FlowSpace.md),
                        action,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: information),
                      const SizedBox(width: FlowSpace.md),
                      action,
                    ],
                  );
                },
              ),
              if (app.importStatus.working) ...[
                const SizedBox(height: FlowSpace.md),
                LinearProgressIndicator(
                  minHeight: 5,
                  color: flow.accent,
                  backgroundColor: flow.sunken,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
              const SizedBox(height: FlowSpace.lg),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    if (_loading && _runs.isEmpty) {
      return Center(child: CircularProgressIndicator(color: flow.accent));
    }
    if (_runs.isEmpty) {
      return _Empty(
        onCheck: ref.read(appControllerProvider.notifier).importMessages,
      );
    }
    final selected = _runs.where((run) => run.id == _selectedRun).firstOrNull;
    final counts = _counts;
    final visible = _visibleItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _runs.length,
            separatorBuilder: (_, _) => const SizedBox(width: FlowSpace.sm),
            itemBuilder: (context, index) {
              final run = _runs[index];
              final active = run.id == _selectedRun;
              return InkWell(
                onTap: () => _select(run.id),
                borderRadius: FlowRadius.sm,
                child: Container(
                  width: 148,
                  padding: const EdgeInsets.all(FlowSpace.md),
                  decoration: BoxDecoration(
                    color: active ? flow.sunken : flow.raised,
                    border: Border.all(color: active ? flow.accent : flow.line),
                    borderRadius: FlowRadius.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_when(run.startedAt), style: text.labelLarge),
                      const SizedBox(height: FlowSpace.xxs),
                      Text(
                        '${run.source} · ${run.imported} added · '
                        '${run.state.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: flow.inkSoft),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: FlowSpace.md),
          _RunSummary(run: selected),
        ],
        const SizedBox(height: FlowSpace.lg),
        // Outcomes first: the handful that did not become a transaction is
        // reachable in one tap rather than by scrolling past every success.
        _OutcomeFilters(
          counts: counts,
          total: _items.length,
          selected: _filter,
          onChanged: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: FlowSpace.md),
        FlowField(
          controller: _search,
          label: 'Search',
          hint: 'Message text or sender',
          prefixIcon: Icons.search_rounded,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: FlowSpace.md),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(
                    _items.isEmpty
                        ? 'No messages in this run.'
                        : 'No messages match this view.',
                    style: text.bodyMedium?.copyWith(color: flow.inkSoft),
                  ),
                )
              // Built lazily: a run holds hundreds of messages, and building
              // every card up front made opening this screen the slow part.
              : ListView.builder(
                  itemCount: visible.length + 1,
                  itemBuilder: (context, index) {
                    if (index == visible.length) {
                      return _TechnicalSection(
                        batches: _batches,
                        onClear: _clearHistory,
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: FlowSpace.sm),
                      child: _MessageCard(item: visible[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheet) => const _ClearHistorySheet(),
    );
    if (confirmed != true) return;
    await ref.read(storeProvider).clearImportAudit();
    _selectedRun = null;
    await _load();
  }

  String _when(DateTime value) =>
      '${value.day}/${value.month} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

class _ClearHistorySheet extends StatelessWidget {
  const _ClearHistorySheet();

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FlowSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Clear intelligence history?', style: text.titleLarge),
            const SizedBox(height: FlowSpace.sm),
            Text(
              'This removes stored message bodies and Ollama '
              'request/response logs. Transactions and deduplication '
              'fingerprints remain.',
              style: text.bodyMedium?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        FlowDensity.minimumTarget,
                      ),
                      side: BorderSide(color: flow.line),
                      foregroundColor: flow.ink,
                      shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadius.sm,
                      ),
                    ),
                    child: const Text('Keep history'),
                  ),
                ),
                const SizedBox(width: FlowSpace.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        FlowDensity.minimumTarget,
                      ),
                      backgroundColor: flow.expense,
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                        borderRadius: FlowRadius.sm,
                      ),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.run});
  final ImportRunRecord run;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(FlowSpace.lg),
      decoration: BoxDecoration(
        color: flow.raised,
        border: Border.all(color: flow.line),
        borderRadius: FlowRadius.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Dot(state: run.state),
              const SizedBox(width: FlowSpace.sm),
              Expanded(
                child: Text(
                  '${run.processed} of ${run.total} processed',
                  style: text.titleMedium,
                ),
              ),
              Text('${run.imported} added', style: text.labelMedium),
            ],
          ),
          const SizedBox(height: FlowSpace.sm),
          Text(
            '${run.source == 'notification' ? 'Notification capture' : 'SMS inbox'}'
            ' · ${run.model} · ${run.endpoint}',
            style: text.bodySmall?.copyWith(color: flow.inkSoft),
          ),
          if (run.error != null) ...[
            const SizedBox(height: FlowSpace.sm),
            Text(
              run.error!,
              style: text.bodySmall?.copyWith(color: flow.expense),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.item});
  final ImportItemRecord item;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Theme(
      // ExpansionTile draws its own dividers from the surrounding theme;
      // suppressed so the card's border is the only line.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: flow.raised,
          border: Border.all(color: flow.line),
          borderRadius: FlowRadius.md,
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(
            horizontal: FlowSpace.md,
            vertical: FlowSpace.xxs,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            FlowSpace.md,
            0,
            FlowSpace.md,
            FlowSpace.md,
          ),
          leading: Icon(
            _icon(item.state),
            size: 20,
            color: _color(flow, item.state),
          ),
          iconColor: flow.inkSoft,
          collapsedIconColor: flow.inkFaint,
          title: Text(
            item.sender?.trim().isNotEmpty == true
                ? item.sender!
                : 'Unknown sender',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: Text(
            '${_label(item.state)}'
            '${item.reason == null ? '' : ' · ${item.reason}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: flow.inkSoft),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(item.body),
            ),
            if (item.transactionId != null) ...[
              const SizedBox(height: FlowSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Created transaction #${item.transactionId}'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _label(ImportItemState value) => switch (value) {
    ImportItemState.queued => 'Waiting for AI',
    ImportItemState.alreadySeen => 'Already analyzed',
    ImportItemState.transaction => 'Transaction added',
    ImportItemState.notTransaction => 'Not a transaction',
    ImportItemState.uncertain => 'Needs review',
    ImportItemState.failed => 'Could not analyze',
  };
  IconData _icon(ImportItemState value) => switch (value) {
    ImportItemState.transaction => Icons.add_chart_rounded,
    ImportItemState.notTransaction => Icons.do_not_disturb_alt_rounded,
    ImportItemState.uncertain => Icons.help_outline_rounded,
    ImportItemState.failed => Icons.error_outline_rounded,
    ImportItemState.alreadySeen => Icons.history_rounded,
    ImportItemState.queued => Icons.hourglass_top_rounded,
  };
  Color _color(FlowColors flow, ImportItemState value) => switch (value) {
    ImportItemState.transaction => flow.income,
    ImportItemState.failed => flow.expense,
    ImportItemState.uncertain => flow.attention,
    _ => flow.inkSoft,
  };
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch});
  final ImportBatchRecord batch;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: FlowSpace.sm),
        decoration: BoxDecoration(
          color: flow.raised,
          border: Border.all(color: flow.line),
          borderRadius: FlowRadius.md,
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: Text(
            'Request ${batch.position + 1} · ${batch.state}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          subtitle: batch.error == null
              ? null
              : Text(
                  batch.error!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: flow.expense),
                ),
          iconColor: flow.inkSoft,
          collapsedIconColor: flow.inkFaint,
          childrenPadding: const EdgeInsets.fromLTRB(
            FlowSpace.md,
            0,
            FlowSpace.md,
            FlowSpace.lg,
          ),
          children: [
            _JsonBlock(title: 'Sent to Ollama', value: batch.requestJson),
            const SizedBox(height: FlowSpace.sm),
            _JsonBlock(
              title: 'Returned by Ollama',
              value: batch.responseJson ?? 'No response was received.',
            ),
          ],
        ),
      ),
    );
  }
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    var shown = value;
    try {
      shown = const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: FlowSpace.xs),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(FlowSpace.md),
          decoration: BoxDecoration(
            color: flow.sunken,
            borderRadius: FlowRadius.sm,
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              shown,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});
  final ImportRunState state;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: switch (state) {
          ImportRunState.completed => flow.income,
          ImportRunState.running => flow.accent,
          ImportRunState.stopped => flow.attention,
          ImportRunState.failed => flow.expense,
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCheck});
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sms_outlined, size: 30, color: flow.accent),
          const SizedBox(height: FlowSpace.md),
          Text('No message checks yet', style: text.titleLarge),
          const SizedBox(height: FlowSpace.sm),
          Text(
            'Start a check to see every message and AI decision here.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: flow.inkSoft),
          ),
          const SizedBox(height: FlowSpace.lg),
          FilledButton(
            onPressed: onCheck,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, FlowDensity.minimumTarget),
              backgroundColor: flow.accent,
              foregroundColor: flow.onAccent,
              shape: const RoundedRectangleBorder(borderRadius: FlowRadius.sm),
            ),
            child: const Text('Check messages'),
          ),
        ],
      ),
    );
  }
}

/// One-tap outcome filters carrying live counts.
class _OutcomeFilters extends StatelessWidget {
  const _OutcomeFilters({
    required this.counts,
    required this.total,
    required this.selected,
    required this.onChanged,
  });

  final Map<ImportItemState, int> counts;
  final int total;
  final ImportItemState? selected;
  final ValueChanged<ImportItemState?> onChanged;

  /// Ordered by how often someone needs them rather than by enum order:
  /// problems first, routine successes last.
  static const _order = [
    ImportItemState.failed,
    ImportItemState.uncertain,
    ImportItemState.transaction,
    ImportItemState.notTransaction,
    ImportItemState.alreadySeen,
    ImportItemState.queued,
  ];

  static String labelFor(ImportItemState state) => switch (state) {
    ImportItemState.failed => 'Failed',
    ImportItemState.uncertain => 'Held',
    ImportItemState.transaction => 'Added',
    ImportItemState.notTransaction => 'Not money',
    ImportItemState.alreadySeen => 'Seen before',
    ImportItemState.queued => 'Queued',
  };

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _Chip(
            label: 'All',
            count: total,
            active: selected == null,
            onTap: () => onChanged(null),
          ),
          for (final state in _order)
            if ((counts[state] ?? 0) > 0) ...[
              const SizedBox(width: FlowSpace.sm),
              _Chip(
                label: labelFor(state),
                count: counts[state]!,
                active: selected == state,
                // Tapping an active chip clears it, so a filter is never a
                // dead end that needs "All" to be found again.
                onTap: () => onChanged(selected == state ? null : state),
                accent: switch (state) {
                  ImportItemState.failed => flow.expense,
                  ImportItemState.uncertain => flow.attention,
                  _ => null,
                },
              ),
            ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    this.accent,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final color = accent ?? flow.accent;
    return Semantics(
      button: true,
      selected: active,
      label: '$label, $count messages',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: FlowRadius.pill,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: FlowSpace.md,
            vertical: FlowSpace.sm,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? color : flow.raised,
            borderRadius: FlowRadius.pill,
            border: Border.all(color: active ? color : flow.line),
          ),
          child: Text(
            '$label $count',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: active ? flow.onAccent : flow.ink,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// Raw provider exchanges, collapsed by default: useful when something is
/// genuinely wrong and noise the rest of the time.
class _TechnicalSection extends StatefulWidget {
  const _TechnicalSection({required this.batches, required this.onClear});
  final List<ImportBatchRecord> batches;
  final VoidCallback onClear;

  @override
  State<_TechnicalSection> createState() => _TechnicalSectionState();
}

class _TechnicalSectionState extends State<_TechnicalSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: FlowSpace.sm),
        if (widget.batches.isNotEmpty) ...[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: FlowRadius.sm,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FlowSpace.sm),
              child: Row(
                children: [
                  Icon(Icons.code_rounded, size: 17, color: flow.inkSoft),
                  const SizedBox(width: FlowSpace.sm),
                  Expanded(
                    child: Text(
                      'Provider exchanges (${widget.batches.length})',
                      style: text.bodyMedium,
                    ),
                  ),
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: flow.inkSoft,
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            Text(
              'Stored only on this device. API credentials are never '
              'included.',
              style: text.bodySmall?.copyWith(color: flow.inkSoft),
            ),
            const SizedBox(height: FlowSpace.sm),
            for (final batch in widget.batches) _BatchCard(batch: batch),
          ],
        ],
        const SizedBox(height: FlowSpace.sm),
        TextButton.icon(
          onPressed: widget.onClear,
          style: TextButton.styleFrom(foregroundColor: flow.expense),
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Clear message intelligence history'),
        ),
        const SizedBox(height: FlowSpace.lg),
      ],
    );
  }
}
