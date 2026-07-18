import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/expense.dart';
import '../flow_os/proof/proof_masthead.dart';
import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../flow_os/primitives/loom_mark.dart';
import '../flow_os/ingestion/evidence_consent_sheet.dart';
import '../flow_os/agent/decision_sheet.dart';
import '../providers/expense_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../utils/category_utils.dart';
import '../utils/currency_utils.dart';
import '../widgets/development_update_ui.dart';
import '../widgets/expense_form_sheet.dart';
import '../widgets/money_chat_sheet.dart';
import 'settings_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.onOpenSettings});

  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _direction = 'all';
  DateTimeRange? _dateRange;
  String? _category;
  bool _reviewOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expenseListProvider);
    final hidden = ref.watch(privateModeProvider);
    final sync = ref.watch(syncProvider);
    return Scaffold(
      body: Column(
        children: [
          ProofMasthead(
            hidden: hidden,
            onPrivacy: () => ref.read(privateModeProvider.notifier).toggle(),
            onManualEntry: _add,
          ),
          Expanded(
            child: async.when(
              loading: () => const _ActivityLoading(),
              error: (error, _) => _EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Transactions unavailable',
                message: '$error',
                action: 'Try again',
                onAction: () => ref.invalidate(expenseListProvider),
              ),
              data: (all) => _content(all, hidden, sync),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(List<Expense> all, bool hidden, SyncState sync) {
    final visible = all.where(_matches).toList();
    final groups = <DateTime, List<Expense>>{};
    for (final item in visible) {
      groups.putIfAbsent(DateUtils.dateOnly(item.date), () => []).add(item);
    }
    final categories = all.map((item) => item.category).toSet().toList()
      ..sort();
    final importSetupRequired = ref.watch(ollamaApiKeyProvider).trim().isEmpty;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final contentInset = screenWidth > AppBreakpoint.contentMax + 40
        ? (screenWidth - AppBreakpoint.contentMax) / 2
        : AppSpacing.lg;
    final filtersActive =
        _direction != 'all' ||
        _dateRange != null ||
        _category != null ||
        _reviewOnly;

    if (all.isEmpty) {
      return CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: DevelopmentUpdateBanner()),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              contentInset,
              AppSpacing.md,
              contentInset,
              104,
            ),
            sliver: SliverList.list(
              children: [
                const _FirstRunOverview(),
                const SizedBox(height: 16),
                _SmsSyncCard(
                  state: sync,
                  onSync: _startSmsSync,
                  onStop: () => ref.read(syncProvider.notifier).cancel(),
                  onSetup: _openSettings,
                  setupRequired: importSetupRequired,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        const SliverToBoxAdapter(child: DevelopmentUpdateBanner()),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(contentInset, 8, contentInset, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EvidencePulse(events: all),
                const SizedBox(height: AppSpacing.lg),
                _SearchField(
                  controller: _search,
                  query: _query,
                  filtersActive: filtersActive,
                  onFilter: () => _showFilters(categories),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
                if (filtersActive) ...[
                  const SizedBox(height: 10),
                  _FilterSummary(
                    direction: _direction,
                    dateRange: _dateRange,
                    category: _category,
                    onClear: _clearFilters,
                  ),
                ],
                if (all.any((item) => item.status == 'needs_review')) ...[
                  const SizedBox(height: AppSpacing.md),
                  _FilterPort(
                    selected: _reviewOnly,
                    label:
                        '${all.where((item) => item.status == 'needs_review').length} TO REVIEW',
                    onTap: () => setState(() => _reviewOnly = !_reviewOnly),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (sync.phase != SyncPhase.idle) ...[
                  _SmsSyncCard(
                    state: sync,
                    onSync: _startSmsSync,
                    onStop: () => ref.read(syncProvider.notifier).cancel(),
                    onSetup: _openSettings,
                    setupRequired: importSetupRequired,
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching evidence',
              message: 'Adjust your search or filters to inspect other events.',
              action: 'Clear filters',
              onAction: _clearFilters,
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(contentInset, 0, contentInset, 104),
            sliver: SliverList.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups.entries.elementAt(index);
                return _StaggeredReveal(
                  child: _TransactionGroup(
                    day: group.key,
                    transactions: group.value,
                    hidden: hidden,
                    onTap: _showDetails,
                    onEdit: _edit,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  bool _matches(Expense item) {
    final direction =
        _direction == 'all' ||
        (_direction == 'in' ? item.isIncome : !item.isIncome);
    final words =
        '${item.displayMerchant} ${item.category} ${item.tags} '
                '${item.amount.toStringAsFixed(2)}'
            .toLowerCase();
    final inRange =
        _dateRange == null ||
        (!item.date.isBefore(_dateRange!.start) &&
            item.date.isBefore(_dateRange!.end.add(const Duration(days: 1))));
    return direction &&
        inRange &&
        (!_reviewOnly || item.status == 'needs_review') &&
        (_category == null || item.category == _category) &&
        words.contains(_query);
  }

  void _clearFilters() => setState(() {
    _query = '';
    _search.clear();
    _direction = 'all';
    _dateRange = null;
    _category = null;
    _reviewOnly = false;
  });

  Future<void> _showFilters(List<String> categories) async {
    var direction = _direction;
    var dateRange = _dateRange;
    var category = _category;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColor.canvas(context),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CoordinateLabel('PROOF / QUERY BOUNDARY'),
                          SizedBox(height: 4),
                          Text(
                            'QUERY EVIDENCE',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (direction != 'all' ||
                        dateRange != null ||
                        category != null)
                      _ProofTextAction(
                        label: 'RESET',
                        onTap: () => setSheetState(() {
                          direction = 'all';
                          dateRange = null;
                          category = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                const CoordinateLabel('AXIS / DIRECTION'),
                const SizedBox(height: 9),
                _DirectionFilter(
                  value: direction,
                  onChanged: (value) => setSheetState(() => direction = value),
                ),
                const SizedBox(height: 22),
                const CoordinateLabel('AXIS / TIME'),
                const SizedBox(height: 9),
                _FilterPort(
                  selected: dateRange != null,
                  label: dateRange == null
                      ? 'ANY DATE'
                      : '${DateFormat('d MMM').format(dateRange!.start)} — ${DateFormat('d MMM').format(dateRange!.end)}',
                  onTap: () async {
                    final now = DateTime.now();
                    final value = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(now.year - 10),
                      lastDate: now.add(const Duration(days: 1)),
                      initialDateRange: dateRange,
                      helpText: 'Choose date range',
                    );
                    if (value != null) setSheetState(() => dateRange = value);
                  },
                ),
                const SizedBox(height: 22),
                const CoordinateLabel('AXIS / CATEGORY'),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _FilterPort(
                      compact: true,
                      selected: category == null,
                      label: 'ANY',
                      onTap: () => setSheetState(() => category = null),
                    ),
                    for (final value in categories)
                      _FilterPort(
                        compact: true,
                        selected: category == value,
                        label: value.toUpperCase(),
                        onTap: () => setSheetState(() => category = value),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _ProofPrimaryAction(
                  label: 'SHOW RESULTS',
                  onTap: () {
                    setState(() {
                      _direction = direction;
                      _dateRange = dateRange;
                      _category = category;
                    });
                    Navigator.pop(sheetContext);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    await HapticFeedback.mediumImpact();
    await _openForm();
  }

  Future<void> _startSmsSync() async {
    final status = await Permission.sms.status;
    if (!status.isGranted && mounted) {
      final proceed =
          await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: FlowColor.canvas(context),
            builder: (_) => const EvidenceConsentSheet(),
          ) ??
          false;
      if (!proceed) return;
    }
    await ref.read(syncProvider.notifier).sync();
  }

  void _openSettings() {
    final callback = widget.onOpenSettings;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _edit(Expense expense) => _openForm(expense);

  Future<void> _openForm([Expense? expense]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.medium,
        reverseDuration: AppMotion.fast,
        curve: AppMotion.emphasizedDecelerate,
      ),
      builder: (sheetContext) => ExpenseFormSheet(
        initialExpense: expense,
        onSave: (value) async {
          if (expense == null) {
            await ref.read(expenseListProvider.notifier).addExpense(value);
          } else {
            await ref.read(expenseListProvider.notifier).updateExpense(value);
          }
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
        onDelete: expense?.id == null
            ? null
            : () async {
                await ref
                    .read(expenseListProvider.notifier)
                    .deleteExpense(expense!.id!);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
      ),
    );
  }

  Future<void> _showDetails(Expense item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        duration: AppMotion.medium,
        reverseDuration: AppMotion.fast,
        curve: AppMotion.emphasizedDecelerate,
      ),
      builder: (sheetContext) => _TransactionDetails(
        item: item,
        onConfirm: item.status == 'needs_review'
            ? () async {
                await ref
                    .read(expenseListProvider.notifier)
                    .updateExpense(
                      item.copyWith(status: 'settled', confidence: 1),
                    );
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              }
            : null,
        onReject: item.status == 'needs_review' && item.id != null
            ? () async {
                final remove =
                    await showModalBottomSheet<bool>(
                      context: sheetContext,
                      backgroundColor: FlowColor.canvas(sheetContext),
                      showDragHandle: false,
                      builder: (_) => const AgentDecisionSheet(
                        title: 'Not a transaction?',
                        description:
                            'Remove this extracted record from the trusted ledger?',
                        notice:
                            'The source message remains in import history and Flow will not add it again.',
                        confirmLabel: 'Remove record',
                        destructive: true,
                      ),
                    ) ??
                    false;
                if (!remove) return;
                await ref
                    .read(expenseListProvider.notifier)
                    .deleteExpense(item.id!);
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              }
            : null,
        onEdit: () {
          Navigator.pop(sheetContext);
          _edit(item);
        },
        onReanalyze: item.originalSms.isEmpty
            ? null
            : () {
                Navigator.pop(sheetContext);
                Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MoneyChatSheet(
                      fullScreen: true,
                      initialPrompt:
                          'Re-analyze transaction ${item.id} from its original SMS and propose any source, destination, or category corrections.',
                    ),
                  ),
                );
              },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.query,
    required this.filtersActive,
    required this.onFilter,
    required this.onChanged,
  });
  final TextEditingController controller;
  final String query;
  final bool filtersActive;
  final VoidCallback onFilter;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => CutSurface(
    cut: 10,
    color: FlowColor.plane(context),
    accent: filtersActive ? FlowColor.proof : FlowColor.rule(context),
    padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
    child: Row(
      children: [
        Container(width: 7, height: 7, color: FlowColor.proof),
        const SizedBox(width: 11),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Query the evidence field',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 11),
              hintStyle: TextStyle(color: FlowColor.quiet(context)),
            ),
          ),
        ),
        if (query.isNotEmpty)
          IconButton(
            tooltip: 'Clear search',
            onPressed: () {
              controller.clear();
              onChanged('');
            },
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        Semantics(
          button: true,
          label: filtersActive ? 'Change active filters' : 'Filter activity',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onFilter,
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              alignment: Alignment.center,
              color: filtersActive ? FlowColor.loom : FlowColor.raised(context),
              child: Text(
                filtersActive ? 'FILTER\nON' : 'FILTER',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: filtersActive
                      ? Colors.white
                      : FlowColor.quiet(context),
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .6,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _SmsSyncCard extends StatelessWidget {
  const _SmsSyncCard({
    required this.state,
    required this.onSync,
    required this.onStop,
    required this.onSetup,
    required this.setupRequired,
  });

  final SyncState state;
  final VoidCallback onSync;
  final VoidCallback onStop;
  final VoidCallback onSetup;
  final bool setupRequired;

  bool get _active =>
      state.phase == SyncPhase.requestingPermissions ||
      state.phase == SyncPhase.fetchingSms ||
      state.phase == SyncPhase.analyzing;

  @override
  Widget build(BuildContext context) {
    final idle = state.phase == SyncPhase.idle;
    return idle
        ? _CompactSync(
            onSync: setupRequired ? onSetup : onSync,
            setupRequired: setupRequired,
          )
        : _ActiveSync(
            state: state,
            active: _active,
            onSync: onSync,
            onStop: onStop,
            onSetup: onSetup,
          );
  }
}

class _FirstRunOverview extends StatelessWidget {
  const _FirstRunOverview();

  @override
  Widget build(BuildContext context) {
    return CutSurface(
      cut: 18,
      color: FlowColor.plane(context),
      accent: FlowColor.proof,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LoomMark(size: 52, state: LoomState.offline),
          const SizedBox(height: 20),
          const CoordinateLabel('PROOF / UNCOMMISSIONED'),
          const SizedBox(height: 8),
          Text(
            'NO EVIDENCE\nFIELD YET.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: FlowColor.content(context),
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Open the transaction-message channel. Flow will turn supported signals into a local, reviewable proof timeline.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: FlowColor.quiet(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slim, unobtrusive sync affordance shown when no sync is running.
class _CompactSync extends StatelessWidget {
  const _CompactSync({required this.onSync, required this.setupRequired});
  final VoidCallback onSync;
  final bool setupRequired;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: setupRequired ? 'Set up SMS evidence' : 'Sync SMS evidence',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSync,
        child: CutSurface(
          cut: 10,
          color: FlowColor.plane(context),
          accent: FlowColor.proof,
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            children: [
              const LoomMark(size: 34, state: LoomState.offline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CoordinateLabel('INGEST / SMS'),
                    const SizedBox(height: 3),
                    Text(
                      setupRequired
                          ? 'Attach intelligence first'
                          : 'Refresh the evidence field',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: FlowColor.content(context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'OPEN →',
                style: TextStyle(
                  color: FlowColor.proof,
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full expressive card shown while syncing, or after completion / error.
class _ActiveSync extends StatelessWidget {
  const _ActiveSync({
    required this.state,
    required this.active,
    required this.onSync,
    required this.onStop,
    required this.onSetup,
  });
  final SyncState state;
  final bool active;
  final VoidCallback onSync;
  final VoidCallback onStop;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final error = state.phase == SyncPhase.error;
    final complete = state.phase == SyncPhase.complete;
    final progress = state.total > 0
        ? (state.current / state.total).clamp(0.0, 1.0)
        : null;
    final title = switch (state.phase) {
      SyncPhase.requestingPermissions => 'Getting SMS access',
      SyncPhase.fetchingSms => 'Reading bank messages',
      SyncPhase.analyzing => 'Understanding transactions',
      SyncPhase.complete => 'SMS sync complete',
      SyncPhase.error => 'Finish SMS import setup',
      SyncPhase.idle => 'Sync bank SMS',
    };
    final detail = error
        ? state.errorMessage ?? 'Could not sync messages.'
        : state.detail ?? 'Working through your recent messages.';

    final signal = error
        ? FlowColor.amber
        : complete
        ? FlowColor.mint
        : FlowColor.proof;
    return CutSurface(
      cut: 11,
      color: FlowColor.plane(context),
      accent: signal,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              LoomMark(
                size: 38,
                state: error
                    ? LoomState.review
                    : complete
                    ? LoomState.proven
                    : LoomState.checking,
                progress: progress,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CoordinateLabel(
                      active ? 'INGEST / ACTIVE' : 'INGEST / RESULT',
                      color: signal,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: FlowColor.content(context),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: FlowColor.quiet(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ProofTextAction(
                label: active
                    ? 'STOP'
                    : error
                    ? 'SET UP'
                    : 'AGAIN',
                onTap: active
                    ? onStop
                    : error
                    ? onSetup
                    : onSync,
              ),
            ],
          ),
          if (active && progress != null) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Container(height: 5, color: FlowColor.raised(context)),
                  Container(
                    width: constraints.maxWidth * progress,
                    height: 5,
                    color: FlowColor.proof,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DirectionFilter extends StatelessWidget {
  const _DirectionFilter({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('all', 'All'),
    ('out', 'Money out'),
    ('in', 'Money in'),
  ];

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < _options.length; index++) ...[
        Expanded(
          child: _FilterPort(
            selected: value == _options[index].$1,
            label: _options[index].$2.toUpperCase(),
            onTap: () => onChanged(_options[index].$1),
          ),
        ),
        if (index != _options.length - 1) const SizedBox(width: 6),
      ],
    ],
  );
}

class _FilterPort extends StatelessWidget {
  const _FilterPort({
    required this.selected,
    required this.label,
    required this.onTap,
    this.compact = false,
  });
  final bool selected;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(
          minWidth: compact ? 54 : 72,
          minHeight: compact ? 40 : 48,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? FlowColor.loom : FlowColor.plane(context),
          border: Border.all(
            color: selected ? FlowColor.proof : FlowColor.rule(context),
          ),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.fade,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : FlowColor.quiet(context),
            fontSize: 8,
            fontWeight: FontWeight.w900,
            letterSpacing: .6,
          ),
        ),
      ),
    ),
  );
}

class _ProofTextAction extends StatelessWidget {
  const _ProofTextAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        label,
        style: TextStyle(
          color: FlowColor.quiet(context),
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: .7,
        ),
      ),
    ),
  );
}

class _ProofPrimaryAction extends StatelessWidget {
  const _ProofPrimaryAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    excludeSemantics: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: CutSurface(
        cut: 9,
        color: FlowColor.loom,
        accent: FlowColor.proof,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        child: Center(
          child: Text(
            '$label →',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: .7,
            ),
          ),
        ),
      ),
    ),
  );
}

class _FilterSummary extends StatelessWidget {
  const _FilterSummary({
    required this.direction,
    required this.dateRange,
    required this.category,
    required this.onClear,
  });
  final String direction;
  final DateTimeRange? dateRange;
  final String? category;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final labels = <String>[
      if (direction == 'out') 'Money out',
      if (direction == 'in') 'Money in',
      if (dateRange != null)
        '${DateFormat('d MMM').format(dateRange!.start)}–${DateFormat('d MMM').format(dateRange!.end)}',
    ];
    if (category != null) labels.add(category!);
    return CutSurface(
      cut: 6,
      color: FlowColor.plane(context),
      border: false,
      padding: const EdgeInsets.fromLTRB(12, 7, 5, 7),
      child: Row(
        children: [
          Container(width: 6, height: 6, color: FlowColor.proof),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              labels.join(' / ').toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: FlowColor.quiet(context),
                fontSize: 8,
                fontWeight: FontWeight.w900,
                letterSpacing: .55,
              ),
            ),
          ),
          _ProofTextAction(label: 'CLEAR', onTap: onClear),
        ],
      ),
    );
  }
}

class _EvidencePulse extends StatelessWidget {
  const _EvidencePulse({required this.events});

  final List<Expense> events;

  @override
  Widget build(BuildContext context) {
    final needsReview = events
        .where((item) => item.status == 'needs_review')
        .length;
    final fromMessages = events
        .where((item) => item.originalSms.isNotEmpty)
        .length;
    return CutSurface(
      cut: 18,
      color: FlowColor.plane(context),
      accent: needsReview > 0 ? FlowColor.amber : FlowColor.proof,
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 430 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final intro = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoomMark(
                size: 42,
                state: needsReview > 0 ? LoomState.review : LoomState.proven,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CoordinateLabel('MATRIX / CURRENT STATE'),
                  const SizedBox(height: 4),
                  Text(
                    needsReview == 0
                        ? 'Evidence resolved'
                        : '$needsReview signals unresolved',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: FlowColor.content(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          );
          final stats = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _EvidenceMetric(value: '${events.length}', label: 'UNDERSTOOD'),
              const SizedBox(width: 22),
              _EvidenceMetric(value: '$fromMessages', label: 'FROM SMS'),
            ],
          );
          return compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [intro, const SizedBox(height: 20), stats],
                )
              : Row(children: [intro, const Spacer(), stats]);
        },
      ),
    );
  }
}

class _EvidenceMetric extends StatelessWidget {
  const _EvidenceMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: AppTheme.money(
          Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: FlowColor.content(context),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: FlowColor.quiet(context),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .8,
        ),
      ),
    ],
  );
}

class _TransactionGroup extends StatelessWidget {
  const _TransactionGroup({
    required this.day,
    required this.transactions,
    required this.hidden,
    required this.onTap,
    required this.onEdit,
  });
  final DateTime day;
  final List<Expense> transactions;
  final bool hidden;
  final ValueChanged<Expense> onTap;
  final ValueChanged<Expense> onEdit;

  String _label() {
    final today = DateUtils.dateOnly(DateTime.now());
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEEE, d MMMM').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final item in transactions) {
      final signed = item.isIncome ? item.amount : -item.amount;
      totals.update(
        item.currency,
        (value) => value + signed,
        ifAbsent: () => signed,
      );
    }
    final summary = hidden
        ? 'Amounts hidden'
        : totals.entries
              .map(
                (entry) =>
                    '${entry.value >= 0 ? '+' : '−'}${formatAmount(entry.value.abs(), entry.key)}',
              )
              .join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _label(),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                summary,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        for (var index = 0; index < transactions.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _TransactionRow(
              index: index,
              item: transactions[index],
              hidden: hidden,
              onTap: () => onTap(transactions[index]),
              onEdit: () => onEdit(transactions[index]),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.index,
    required this.item,
    required this.hidden,
    required this.onTap,
    required this.onEdit,
  });
  final int index;
  final Expense item;
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  bool get needsReview =>
      item.status == 'needs_review' ||
      item.confidence < 0.7 ||
      item.displayMerchant.trim().isEmpty ||
      item.displayMerchant.toLowerCase() == 'unknown';

  @override
  Widget build(BuildContext context) {
    final amount = hidden
        ? maskAmount(item.currency)
        : '${item.isIncome ? '+' : '−'}${formatAmount(item.amount, item.currency)}';
    final signalColor = needsReview
        ? FlowColor.amber
        : item.isIncome
        ? FlowColor.mint
        : categoryColor(item.category);
    final source = item.originalSms.isEmpty ? 'MANUAL' : 'SMS EVIDENCE';
    return Semantics(
      button: true,
      label:
          '${needsReview ? 'Needs review' : item.displayMerchant}, $amount, ${item.category}, ${DateFormat('d MMMM, h:mm a').format(item.date)}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onEdit,
        child: CutSurface(
          cut: index.isEven ? 11 : 7,
          color: FlowColor.plane(context),
          accent: signalColor.withValues(alpha: needsReview ? .8 : .35),
          padding: EdgeInsets.zero,
          child: IntrinsicHeight(
            child: Row(
              children: [
                SizedBox(width: 9, child: ColoredBox(color: signalColor)),
                Container(
                  width: 46,
                  alignment: Alignment.center,
                  color: FlowColor.raised(context),
                  child: Text(
                    needsReview
                        ? '!'
                        : item.isIncome
                        ? '↙'
                        : '↗',
                    style: TextStyle(
                      color: signalColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(13, 13, 14, 13),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                needsReview
                                    ? 'Needs review'
                                    : item.displayMerchant,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: FlowColor.content(context),
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                needsReview
                                    ? 'CHECK SIGNAL / MISSING DETAIL'
                                    : '$source / ${item.category.toUpperCase()} / ${DateFormat('HH:mm').format(item.date)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: signalColor.withValues(alpha: .86),
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: .55,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .34,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              amount,
                              style: AppTheme.money(
                                Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  color: item.isIncome
                                      ? FlowColor.mint
                                      : FlowColor.content(context),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidenceTag extends StatelessWidget {
  const _EvidenceTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: 9,
        letterSpacing: .55,
      ),
    ),
  );
}

class _TransactionDetails extends StatelessWidget {
  const _TransactionDetails({
    required this.item,
    required this.onEdit,
    required this.onReanalyze,
    required this.onConfirm,
    required this.onReject,
  });
  final Expense item;
  final VoidCallback onEdit;
  final VoidCallback? onReanalyze;
  final VoidCallback? onConfirm;
  final VoidCallback? onReject;

  bool get needsReview =>
      item.status == 'needs_review' ||
      item.confidence < 0.7 ||
      item.displayMerchant.trim().isEmpty ||
      item.displayMerchant.toLowerCase() == 'unknown';

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        4,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CutSurface(
            cut: 18,
            color: FlowColor.plane(context),
            accent: needsReview
                ? FlowColor.amber
                : item.isIncome
                ? FlowColor.mint
                : FlowColor.proof,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LoomMark(
                      size: 38,
                      state: needsReview ? LoomState.review : LoomState.proven,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.originalSms.isEmpty
                            ? 'MANUAL EVIDENCE'
                            : needsReview
                            ? 'UNDERSTANDING NEEDS REVIEW'
                            : 'AI-UNDERSTOOD EVENT',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: needsReview
                              ? FlowColor.amber
                              : FlowColor.proof,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    if (item.originalSms.isNotEmpty)
                      _EvidenceTag(
                        label: '${(item.confidence * 100).round()}% SIGNAL',
                        color: FlowColor.proof,
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Text(
                  item.isIncome ? 'MONEY RECEIVED' : 'MONEY SENT',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: FlowColor.quiet(context),
                    fontWeight: FontWeight.w800,
                    letterSpacing: .8,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${item.isIncome ? '+' : '−'}${formatAmount(item.amount, item.currency)}',
                  style: AppTheme.money(
                    Theme.of(context).textTheme.headlineLarge?.copyWith(
                      color: item.isIncome
                          ? FlowColor.mint
                          : FlowColor.content(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _DetailLine(
            label: item.isIncome ? 'From' : 'To',
            value: needsReview ? 'Unknown' : item.displayMerchant,
            warning: needsReview,
          ),
          _DetailLine(label: 'Category', value: item.category),
          _DetailLine(
            label: 'Date',
            value: DateFormat('d MMMM yyyy, h:mm a').format(item.date),
          ),
          _DetailLine(
            label: 'Added from',
            value: item.originalSms.isEmpty ? 'Manual entry' : 'Bank SMS',
          ),
          if (item.originalSms.isNotEmpty)
            _DetailLine(
              label: 'Flow confidence',
              value:
                  '${(item.confidence * 100).round()}%${needsReview ? ' · Check this' : ''}',
              warning: needsReview,
            ),
          if (item.tags.trim().isNotEmpty)
            _DetailLine(label: 'Tags', value: item.tags),
          const SizedBox(height: 20),
          if (needsReview && onConfirm != null) ...[
            Row(
              children: [
                Expanded(
                  child: _ProofPrimaryAction(
                    label: 'CONFIRM',
                    onTap: onConfirm!,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _FilterPort(
                    selected: false,
                    label: 'CORRECT',
                    onTap: onEdit,
                  ),
                ),
              ],
            ),
            if (onReject != null)
              Center(
                child: _ProofTextAction(
                  label: 'NOT A TRANSACTION',
                  onTap: onReject!,
                ),
              ),
            if (onReanalyze != null)
              Center(
                child: _ProofTextAction(
                  label: 'RE-ANALYZE SOURCE WITH FLOW',
                  onTap: onReanalyze!,
                ),
              ),
          ],
          const SizedBox(height: 8),
          if (!needsReview)
            _FilterPort(
              selected: false,
              label: 'CORRECT DETAILS',
              onTap: onEdit,
            ),
        ],
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.label,
    required this.value,
    this.warning = false,
  });
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 104,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          color: FlowColor.raised(context),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: FlowColor.quiet(context),
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: .6,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: FlowColor.plane(context),
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: warning ? FlowColor.amber : FlowColor.content(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CoordinateLabel('PROOF / NO MATCHING SIGNAL'),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  color: FlowColor.plane(context),
                  child: Icon(icon, size: 22, color: FlowColor.proof),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: FlowColor.content(context),
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: FlowColor.quiet(context),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              button: true,
              label: action,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: CutSurface(
                  cut: 8,
                  color: FlowColor.loom,
                  accent: FlowColor.proof,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  child: Text(
                    '${action.toUpperCase()} →',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .7,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityLoading extends StatelessWidget {
  const _ActivityLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
      children: [
        Row(
          children: [
            const LoomMark(size: 44, state: LoomState.checking),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CoordinateLabel('PROOF / ASSEMBLING'),
                  const SizedBox(height: 3),
                  Text(
                    'Preparing local evidence',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: FlowColor.content(context),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Records appear as soon as each group is ready.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: FlowColor.quiet(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        for (var index = 0; index < 5; index++) ...[
          CutSurface(
            cut: index.isEven ? 10 : 6,
            color: FlowColor.plane(context).withValues(alpha: 1 - index * .12),
            border: false,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  color: FlowColor.raised(context),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 130,
                        height: 8,
                        color: FlowColor.rule(context),
                      ),
                      const SizedBox(height: 9),
                      Container(
                        width: 84,
                        height: 5,
                        color: FlowColor.rule(context).withValues(alpha: .6),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StaggeredReveal extends StatelessWidget {
  const _StaggeredReveal({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
