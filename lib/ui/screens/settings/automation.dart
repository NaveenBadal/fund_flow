import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_state.dart';
import '../../../domain/ai_provider.dart';
import '../../../domain/import_audit.dart';
import '../../../domain/preferences.dart';
import '../../theme/ff_theme.dart';
import '../../widgets/ff_controls.dart';
import '../../widgets/ff_group.dart';
import '../../widgets/ff_notice.dart';
import '../../widgets/ff_screen.dart';
import '../../widgets/ff_sheet.dart';
import 'intelligence.dart';

/// Reading messages.
///
/// The one screen that explains what the app does without being asked, so it
/// says plainly what is read, when, and what leaves the device — above the
/// button that starts it, not in a policy somewhere.
class AutomationScreen extends ConsumerWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final controller = ref.read(appControllerProvider.notifier);
    final status = app.importStatus;
    final connected = app.aiConnection == AiConnection.connected;
    final c = context.ff;

    return FFScreen(
      title: 'Message capture',
      large: false,
      slivers: [
        SliverToBoxAdapter(
          child: FFNotice(
            busy: status.working,
            icon: switch (status.phase) {
              ImportPhase.complete => Icons.check_circle_rounded,
              ImportPhase.error ||
              ImportPhase.invalidResponse ||
              ImportPhase.providerDisconnected => Icons.error_rounded,
              ImportPhase.rateLimited ||
              ImportPhase.stopped => Icons.pause_circle_rounded,
              _ => Icons.sms_rounded,
            },
            tone: switch (status.phase) {
              ImportPhase.complete => FFNoticeTone.positive,
              ImportPhase.error ||
              ImportPhase.invalidResponse ||
              ImportPhase.providerDisconnected => FFNoticeTone.problem,
              ImportPhase.rateLimited ||
              ImportPhase.stopped => FFNoticeTone.attention,
              _ => FFNoticeTone.neutral,
            },
            title: _statusTitle(status),
            message: _statusDetail(status, connected),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              0,
              FFSpace.gutter,
              FFSpace.xl,
            ),
            child: connected
                ? FFButton(
                    status.working
                        ? 'Stop safely'
                        : status.retryable
                        ? 'Try again'
                        : 'Check my messages',
                    icon: status.working
                        ? Icons.stop_rounded
                        : Icons.search_rounded,
                    style: status.working
                        ? FFButtonStyle.tinted
                        : FFButtonStyle.filled,
                    onTap: status.working
                        ? controller.stopMessageImport
                        : controller.importMessages,
                  )
                : FFButton(
                    'Connect a provider first',
                    icon: Icons.link_rounded,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const IntelligenceScreen(),
                      ),
                    ),
                  ),
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Settings',
            footer:
                'A check reads only messages inside the history window, and '
                'only when you start it. Live capture adds payment '
                'notifications as they arrive.',
            children: [
              FFRow(
                title: 'Live notification capture',
                chevron: false,
                trailing: FFSwitch(
                  value: app.preferences.captureNotifications,
                  onChanged: (value) =>
                      controller.setNotificationCapture(value),
                ),
              ),
              FFRow(
                title: 'History window',
                value: '${app.preferences.messageLookbackDays} days',
                onTap: () async {
                  final choice = await showFFPicker<int>(
                    context,
                    title: 'History window',
                    current: app.preferences.messageLookbackDays,
                    options: const [
                      (7, 'Last 7 days'),
                      (14, 'Last 14 days'),
                      (maximumLookbackDays, 'Last 30 days'),
                    ],
                    footer:
                        'How far back a check looks. A wider window takes '
                        'longer and sends more message text to your provider.',
                  );
                  if (choice == null) return;
                  await controller.updatePreferences(
                    app.preferences.copyWith(messageLookbackDays: choice),
                  );
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Evidence',
            footer:
                'Every message a check looked at, what was decided about it, '
                'and the exact request sent to ${providerInfo(app.preferences.aiProvider).label}.',
            children: [
              FFRow(
                title: 'Decision history',
                icon: Icons.fact_check_rounded,
                iconColor: c.tint,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AuditScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _statusTitle(ImportStatus status) => switch (status.phase) {
  ImportPhase.idle => 'Ready when you are',
  ImportPhase.requestingPermission => 'Waiting for permission',
  ImportPhase.reading => 'Reading recent messages',
  ImportPhase.understanding => 'Understanding messages',
  ImportPhase.paused => 'Paused in the background',
  ImportPhase.stopped => 'Stopped safely',
  ImportPhase.rateLimited => 'Slowing down',
  ImportPhase.providerDisconnected => 'Lost the provider',
  ImportPhase.invalidResponse => 'Unusable response',
  ImportPhase.complete => 'Check complete',
  ImportPhase.error => 'The check could not finish',
};

String _statusDetail(ImportStatus status, bool connected) =>
    switch (status.phase) {
      ImportPhase.idle => connected
          ? 'Nothing is read until you start a check.'
          : 'Connect a provider and nothing is read until you start a check.',
      ImportPhase.understanding =>
        '${status.checked} checked · ${status.imported} added',
      ImportPhase.complete =>
        '${status.checked} checked · ${status.imported} added · '
            '${status.skipped} skipped',
      ImportPhase.rateLimited =>
        'Your provider asked for fewer requests. Try again shortly.',
      _ => status.message ?? 'Progress is kept, so nothing is read twice.',
    };

/// What the last checks decided, message by message.
class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  Timer? _timer;
  List<ImportRunRecord> _runs = const [];
  List<ImportItemRecord> _items = const [];
  List<ImportBatchRecord> _batches = const [];
  final _search = TextEditingController();
  int? _run;
  ImportItemState? _filter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = ref.read(storeProvider);
    final runs = await store.importRuns();
    final id = _run ?? runs.firstOrNull?.id;
    final results = id == null
        ? const <List<Object>>[[], []]
        : await Future.wait<List<Object>>([
            store.importItems(id),
            store.importBatches(id),
          ]);
    if (!mounted) return;
    setState(() {
      _runs = runs;
      _run = id;
      _items = results[0].cast<ImportItemRecord>();
      _batches = results[1].cast<ImportBatchRecord>();
      _loading = false;
    });
  }

  List<ImportItemRecord> get _visible {
    final query = _search.text.toLowerCase().trim();
    return _items.where((item) {
      if (_filter != null && item.state != _filter) return false;
      if (query.isEmpty) return true;
      return '${item.sender ?? ''} ${item.body} ${item.reason ?? ''}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final run = _runs.where((r) => r.id == _run).firstOrNull;
    final visible = _visible;

    if (_loading) {
      return const FFScreen(
        title: 'Decision history',
        large: false,
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: FFSpinner()),
          ),
        ],
      );
    }

    if (_runs.isEmpty) {
      return const FFScreen(
        title: 'Decision history',
        large: false,
        slivers: [
          SliverToBoxAdapter(
            child: FFEmpty(
              icon: Icons.fact_check_rounded,
              title: 'No checks yet',
              message:
                  'Start a message check and every decision it makes will be '
                  'listed here.',
            ),
          ),
        ],
      );
    }

    return FFScreen(
      title: 'Decision history',
      large: false,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: FFSpace.gutter),
              itemCount: _runs.length,
              separatorBuilder: (_, _) => const SizedBox(width: FFSpace.sm),
              itemBuilder: (context, index) => FFChip(
                label: DateFormat('d MMM, HH:mm').format(_runs[index].startedAt),
                selected: _runs[index].id == _run,
                onTap: () {
                  setState(() {
                    _run = _runs[index].id;
                    _loading = true;
                  });
                  _load();
                },
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: FFSpace.lg)),
        if (run != null)
          SliverToBoxAdapter(
            child: FFGroup(
              footer: run.error,
              children: [
                FFRow(
                  title: '${run.processed} of ${run.total} checked',
                  subtitle:
                      '${run.source == 'notification' ? 'Notifications' : 'SMS inbox'} · ${run.model}',
                  chevron: false,
                  icon: switch (run.state) {
                    ImportRunState.completed => Icons.check_rounded,
                    ImportRunState.running => Icons.sync_rounded,
                    ImportRunState.stopped => Icons.pause_rounded,
                    ImportRunState.failed => Icons.error_rounded,
                  },
                  iconColor: switch (run.state) {
                    ImportRunState.completed => c.greenFill,
                    ImportRunState.running => c.tint,
                    ImportRunState.stopped => c.orangeFill,
                    ImportRunState.failed => c.redFill,
                  },
                  value: '${run.imported} added',
                ),
                if (_batches.isNotEmpty)
                  FFRow(
                    title: 'Provider exchanges',
                    value: '${_batches.length}',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _ExchangesScreen(batches: _batches),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              0,
              FFSpace.gutter,
              FFSpace.md,
            ),
            child: FFSearchField(
              controller: _search,
              placeholder: 'Sender, message or reason',
              onChanged: (_) => setState(() {}),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.gutter,
              0,
              FFSpace.gutter,
              FFSpace.lg,
            ),
            child: Wrap(
              spacing: FFSpace.sm,
              runSpacing: FFSpace.sm,
              children: [
                for (final state in <ImportItemState?>[
                  null,
                  ImportItemState.failed,
                  ImportItemState.uncertain,
                  ImportItemState.transaction,
                  ImportItemState.notTransaction,
                  ImportItemState.alreadySeen,
                ])
                  if (state == null ||
                      _items.any((item) => item.state == state))
                    FFChip(
                      label:
                          '${_itemLabel(state)} '
                          '${state == null ? _items.length : _items.where((i) => i.state == state).length}',
                      selected: _filter == state,
                      onTap: () => setState(
                        () => _filter = _filter == state ? null : state,
                      ),
                    ),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: FFEmpty(
              icon: Icons.filter_alt_off_rounded,
              title: _items.isEmpty
                  ? 'Nothing in this run'
                  : 'Nothing matches this view',
            ),
          )
        else
          SliverToBoxAdapter(
            child: FFGroup(
              separatorIndent: 57,
              children: [
                for (final item in visible)
                  FFRow(
                    title: item.sender?.trim().isNotEmpty == true
                        ? item.sender!
                        : 'Unknown sender',
                    subtitle:
                        '${_itemLabel(item.state)}'
                        '${item.reason == null ? '' : ' · ${item.reason}'}',
                    icon: _itemIcon(item.state),
                    iconColor: _itemColor(context, item.state),
                    onTap: () => _showItem(item),
                  ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: FFGroup(
            footer:
                'Removes stored message bodies and provider logs. Transactions '
                'and duplicate detection are unaffected.',
            children: [
              FFRow(
                title: 'Clear evidence',
                destructive: true,
                centered: true,
                chevron: false,
                onTap: () async {
                  final approved = await ffConfirm(
                    context,
                    title: 'Clear the evidence?',
                    message:
                        'Stored message text and provider logs are removed.',
                    confirm: 'Clear',
                  );
                  if (!approved) return;
                  await ref.read(storeProvider).clearImportAudit();
                  _run = null;
                  await _load();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showItem(ImportItemRecord item) => showFFSheet<void>(
    context,
    builder: (sheet) => FFSheetScaffold(
      title: _itemLabel(item.state),
      leading: FFSheetAction(
        label: 'Done',
        onTap: () => Navigator.of(sheet).pop(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FFGroup(
            margin: const EdgeInsets.all(FFSpace.gutter),
            header: item.sender?.trim().isNotEmpty == true
                ? item.sender
                : 'Unknown sender',
            footer: item.reason,
            children: [
              Padding(
                padding: const EdgeInsets.all(FFSpace.lg),
                child: SelectableText(item.body, style: FFText.footnote),
              ),
            ],
          ),
          if (item.transactionId != null)
            FFGroup(
              margin: const EdgeInsets.fromLTRB(
                FFSpace.gutter,
                0,
                FFSpace.gutter,
                FFSpace.gutter,
              ),
              children: [
                FFRow(
                  title: 'Created transaction',
                  value: '#${item.transactionId}',
                  chevron: false,
                ),
              ],
            ),
        ],
      ),
    ),
  );
}

class _ExchangesScreen extends StatelessWidget {
  const _ExchangesScreen({required this.batches});
  final List<ImportBatchRecord> batches;

  @override
  Widget build(BuildContext context) => FFScreen(
    title: 'Provider exchanges',
    large: false,
    slivers: [
      for (final batch in batches)
        SliverToBoxAdapter(
          child: FFGroup(
            header: 'Request ${batch.position + 1} · ${batch.state}',
            footer: batch.error,
            children: [
              _Json(label: 'Sent', value: batch.requestJson),
              _Json(label: 'Returned', value: batch.responseJson ?? '—'),
            ],
          ),
        ),
    ],
  );
}

class _Json extends StatelessWidget {
  const _Json({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    var shown = value;
    try {
      shown = const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
    } catch (_) {}
    return Padding(
      padding: const EdgeInsets.all(FFSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: FFText.caption2.copyWith(
              color: context.ff.secondaryLabel,
              letterSpacing: .6,
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: SelectableText(
                shown,
                style: FFText.caption.copyWith(
                  fontFamily: 'monospace',
                  color: context.ff.secondaryLabel,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _itemLabel(ImportItemState? value) => switch (value) {
  null => 'All',
  ImportItemState.queued => 'Queued',
  ImportItemState.alreadySeen => 'Seen before',
  ImportItemState.transaction => 'Added',
  ImportItemState.notTransaction => 'Not money',
  ImportItemState.uncertain => 'Needs review',
  ImportItemState.failed => 'Failed',
};

IconData _itemIcon(ImportItemState value) => switch (value) {
  ImportItemState.queued => Icons.hourglass_top_rounded,
  ImportItemState.alreadySeen => Icons.history_rounded,
  ImportItemState.transaction => Icons.check_rounded,
  ImportItemState.notTransaction => Icons.remove_rounded,
  ImportItemState.uncertain => Icons.question_mark_rounded,
  ImportItemState.failed => Icons.priority_high_rounded,
};

Color _itemColor(BuildContext context, ImportItemState value) => switch (value) {
  ImportItemState.transaction => context.ff.greenFill,
  ImportItemState.uncertain => context.ff.orangeFill,
  ImportItemState.failed => context.ff.redFill,
  _ => const Color(0xff8e8e93),
};
