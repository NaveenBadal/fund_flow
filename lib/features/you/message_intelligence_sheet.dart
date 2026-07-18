import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_controller.dart';
import '../../domain/import_audit.dart';
import '../../ui/components/current_button.dart';
import '../../ui/foundation/current_colors.dart';

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
    super.dispose();
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
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .92,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.current.rule,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Message intelligence',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          app.importStatus.working
                              ? '${app.importStatus.checked} analyzed · ${app.importStatus.imported} added'
                              : 'Every local message decision and Ollama exchange',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: context.current.muted),
                        ),
                      ],
                    ),
                  ),
                  CurrentButton(
                    label: app.importStatus.working ? 'Stop' : 'Check',
                    icon: app.importStatus.working
                        ? Icons.stop_rounded
                        : Icons.refresh_rounded,
                    compact: true,
                    style: CurrentButtonStyle.tonal,
                    onPressed: app.importStatus.working
                        ? controller.stopMessageImport
                        : controller.importMessages,
                  ),
                ],
              ),
              if (app.importStatus.working) ...[
                const SizedBox(height: 14),
                LinearProgressIndicator(
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
              const SizedBox(height: 18),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading && _runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_runs.isEmpty) {
      return _Empty(
        onCheck: ref.read(appControllerProvider.notifier).importMessages,
      );
    }
    final selected = _runs.where((run) => run.id == _selectedRun).firstOrNull;
    return ListView(
      children: [
        SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _runs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final run = _runs[index];
              final active = run.id == _selectedRun;
              return InkWell(
                onTap: () => _select(run.id),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 142,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: active
                        ? context.current.subtle
                        : context.current.surface,
                    border: Border.all(
                      color: active
                          ? context.current.intelligence
                          : context.current.rule,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _when(run.startedAt),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${run.imported} added · ${run.state.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.current.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 14),
          _RunSummary(run: selected),
        ],
        const SizedBox(height: 22),
        Text('Messages', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        for (final item in _items) ...[
          _MessageCard(item: item),
          const SizedBox(height: 9),
        ],
        if (_batches.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Ollama exchanges',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Stored only on this device. API credentials are never included.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.current.muted),
          ),
          const SizedBox(height: 10),
          for (final batch in _batches) _BatchCard(batch: batch),
        ],
      ],
    );
  }

  String _when(DateTime value) =>
      '${value.day}/${value.month} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _RunSummary extends StatelessWidget {
  const _RunSummary({required this.run});
  final ImportRunRecord run;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.current.surface,
      border: Border.all(color: context.current.rule),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _Dot(state: run.state),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${run.processed} of ${run.total} processed',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text('${run.imported} added'),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${run.model} · ${run.endpoint}',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.current.muted),
        ),
        if (run.error != null) ...[
          const SizedBox(height: 8),
          Text(run.error!, style: TextStyle(color: context.current.expense)),
        ],
      ],
    ),
  );
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.item});
  final ImportItemRecord item;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
    childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    collapsedShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
    ),
    backgroundColor: context.current.surface,
    collapsedBackgroundColor: context.current.surface,
    leading: Icon(_icon(item.state), color: _color(context, item.state)),
    title: Text(
      item.sender?.trim().isNotEmpty == true ? item.sender! : 'Unknown sender',
    ),
    subtitle: Text(
      '${_label(item.state)}${item.reason == null ? '' : ' · ${item.reason}'}',
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    children: [
      Align(alignment: Alignment.centerLeft, child: SelectableText(item.body)),
      if (item.transactionId != null) ...[
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Created transaction #${item.transactionId}'),
        ),
      ],
    ],
  );

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
  Color _color(BuildContext context, ImportItemState value) => switch (value) {
    ImportItemState.transaction => context.current.income,
    ImportItemState.failed => context.current.expense,
    ImportItemState.uncertain => context.current.review,
    _ => context.current.muted,
  };
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch});
  final ImportBatchRecord batch;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 9),
    elevation: 0,
    color: context.current.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: context.current.rule),
    ),
    child: ExpansionTile(
      title: Text('Request ${batch.position + 1} · ${batch.state}'),
      subtitle: batch.error == null ? null : Text(batch.error!),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      children: [
        _JsonBlock(title: 'Sent to Ollama', value: batch.requestJson),
        const SizedBox(height: 10),
        _JsonBlock(
          title: 'Returned by Ollama',
          value: batch.responseJson ?? 'No response was received.',
        ),
      ],
    ),
  );
}

class _JsonBlock extends StatelessWidget {
  const _JsonBlock({required this.title, required this.value});
  final String title;
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
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 260),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.current.subtle,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(child: SelectableText(shown)),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.state});
  final ImportRunState state;
  @override
  Widget build(BuildContext context) => Container(
    width: 9,
    height: 9,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: switch (state) {
        ImportRunState.completed => context.current.income,
        ImportRunState.running => context.current.intelligence,
        ImportRunState.stopped => context.current.review,
        ImportRunState.failed => context.current.expense,
      },
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onCheck});
  final VoidCallback onCheck;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.sms_outlined, size: 34, color: context.current.intelligence),
        const SizedBox(height: 14),
        Text(
          'No message checks yet',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Start a check to see every message and AI decision here.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.current.muted),
        ),
        const SizedBox(height: 18),
        CurrentButton(label: 'Check messages', onPressed: onCheck),
      ],
    ),
  );
}
