import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/expense.dart';
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
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Activity'),
            Text(
              'All transactions',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                letterSpacing: 0,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: hidden ? 'Show amounts' : 'Hide amounts',
            onPressed: () => ref.read(privateModeProvider.notifier).toggle(),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'More activity actions',
            onSelected: (value) {
              if (value == 'add_cash') _add();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'add_cash',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.add_rounded),
                  title: Text('Add cash transaction'),
                  subtitle: Text('Manual fallback'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: async.when(
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
                  FilterChip(
                    selected: _reviewOnly,
                    avatar: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(
                      '${all.where((item) => item.status == 'needs_review').length} to review',
                    ),
                    onSelected: (value) => setState(() => _reviewOnly = value),
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
              title: 'No matching transactions',
              message: 'Adjust your search or filters to see more activity.',
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
                  index: index,
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
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filter activity',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    if (direction != 'all' ||
                        dateRange != null ||
                        category != null)
                      TextButton(
                        onPressed: () => setSheetState(() {
                          direction = 'all';
                          dateRange = null;
                          category = null;
                        }),
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Direction',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  expandedInsets: EdgeInsets.zero,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('All')),
                    ButtonSegment(value: 'out', label: Text('Money out')),
                    ButtonSegment(value: 'in', label: Text('Money in')),
                  ],
                  selected: {direction},
                  onSelectionChanged: (value) =>
                      setSheetState(() => direction = value.first),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final now = DateTime.now();
                          final value = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(now.year - 10),
                            lastDate: now.add(const Duration(days: 1)),
                            initialDateRange: dateRange,
                            helpText: 'Choose date range',
                          );
                          if (value != null) {
                            setSheetState(() => dateRange = value);
                          }
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          dateRange == null
                              ? 'Any date'
                              : '${DateFormat('d MMM').format(dateRange!.start)}–${DateFormat('d MMM').format(dateRange!.end)}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          contentPadding: EdgeInsets.symmetric(horizontal: 14),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Any'),
                          ),
                          for (final value in categories)
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => category = value),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _direction = direction;
                        _dateRange = dateRange;
                        _category = category;
                      });
                      Navigator.pop(sheetContext);
                    },
                    child: const Text('Show results'),
                  ),
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
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.sms_outlined),
              title: const Text('Import bank messages?'),
              content: const Text(
                'Flow scans recent SMS on this device for supported transaction messages. Other conversations are ignored. Transaction messages are sent to your configured AI only when you start an import.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
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
                    await showDialog<bool>(
                      context: sheetContext,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Not a transaction?'),
                        content: const Text(
                          'This removes the extracted record. The source message remains in import history so Flow will not add it again.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: const Text('Remove record'),
                          ),
                        ],
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
  Widget build(BuildContext context) => SearchBar(
    controller: controller,
    hintText: 'Search transactions',
    leading: const Icon(Icons.search_rounded),
    trailing: [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Clear search',
          onPressed: () {
            controller.clear();
            onChanged('');
          },
          icon: const Icon(Icons.close_rounded),
        ),
      IconButton(
        tooltip: filtersActive ? 'Change active filters' : 'Filter activity',
        onPressed: onFilter,
        icon: Icon(
          filtersActive ? Icons.filter_alt_rounded : Icons.tune_rounded,
        ),
      ),
    ],
    elevation: const WidgetStatePropertyAll(0),
    backgroundColor: WidgetStatePropertyAll(
      Theme.of(context).colorScheme.surfaceContainerHigh,
    ),
    onChanged: onChanged,
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
    return AnimatedSwitcher(
      duration: AppMotion.medium,
      switchInCurve: AppMotion.emphasizedDecelerate,
      transitionBuilder: (child, animation) => SizeTransition(
        sizeFactor: animation,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: idle
          ? _CompactSync(
              key: const ValueKey('idle'),
              onSync: setupRequired ? onSetup : onSync,
              setupRequired: setupRequired,
            )
          : _ActiveSync(
              key: const ValueKey('active'),
              state: state,
              active: _active,
              onSync: onSync,
              onStop: onStop,
              onSetup: onSetup,
            ),
    );
  }
}

class _FirstRunOverview extends StatelessWidget {
  const _FirstRunOverview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(64),
          bottomLeft: Radius.circular(64),
          bottomRight: Radius.circular(36),
        ),
        boxShadow: PremiumShadows.ambient(context, color: scheme.primary),
      ),
      child: Material(
        color: scheme.primaryContainer,
        shape: ExpressiveShape.hero(),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: scheme.onPrimaryContainer.withValues(alpha: .1),
                  borderRadius: AppRadius.all(AppRadius.lg),
                ),
                child: Icon(
                  Icons.insights_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Your money,\none clear timeline',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Connect transaction SMS in Flow. Imported records and anything needing review will appear here as evidence.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onPrimaryContainer.withValues(alpha: .78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim, unobtrusive sync affordance shown when no sync is running.
class _CompactSync extends StatelessWidget {
  const _CompactSync({
    super.key,
    required this.onSync,
    required this.setupRequired,
  });
  final VoidCallback onSync;
  final bool setupRequired;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CalmPress(
      onTap: onSync,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Ink(
        color: scheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(Icons.sms_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  setupRequired
                      ? 'Set up bank SMS import'
                      : 'Sync bank SMS for new transactions',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: onSync,
                icon: Icon(
                  setupRequired
                      ? Icons.arrow_forward_rounded
                      : Icons.sync_rounded,
                  size: 18,
                ),
                label: Text(setupRequired ? 'Set up' : 'Sync'),
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
    super.key,
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
    final scheme = Theme.of(context).colorScheme;
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

    return Material(
      color: error
          ? context.finance.warningSurface
          : complete
          ? scheme.tertiaryContainer
          : scheme.secondaryContainer,
      shape: ExpressiveShape.card(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.surface.withValues(alpha: .75),
                  child: Icon(
                    complete
                        ? Icons.check_rounded
                        : error
                        ? Icons.sms_failed_outlined
                        : Icons.sms_outlined,
                    color: error ? context.finance.warning : scheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (active)
                  IconButton.filledTonal(
                    tooltip: 'Stop SMS sync',
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: error ? onSetup : onSync,
                    icon: Icon(
                      error ? Icons.arrow_forward_rounded : Icons.sync_rounded,
                    ),
                    label: Text(error ? 'Set up' : 'Again'),
                  ),
              ],
            ),
            if (active) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(value: progress, minHeight: 6),
              ),
            ],
          ],
        ),
      ),
    );
  }
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
    return Row(
      children: [
        Icon(
          Icons.filter_alt_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            labels.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Clear')),
      ],
    );
  }
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
    final avatarColor = needsReview
        ? context.finance.warningSurface
        : item.isIncome
        ? context.finance.incomeSurface
        : Theme.of(context).colorScheme.surfaceContainerHigh;
    final iconColor = needsReview
        ? context.finance.warning
        : item.isIncome
        ? context.finance.income
        : categoryColor(item.category);
    return Semantics(
      button: true,
      label:
          '${needsReview ? 'Needs review' : item.displayMerchant}, $amount, ${item.category}, ${DateFormat('d MMMM, h:mm a').format(item.date)}',
      child: CalmPress(
        onTap: onTap,
        onLongPress: onEdit,
        borderRadius: ExpressiveShape.playful(index),
        child: Ink(
          color: needsReview
              ? context.finance.warningSurface
              : Theme.of(context).colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: avatarColor,
                  child: Icon(
                    needsReview
                        ? Icons.priority_high_rounded
                        : item.isIncome
                        ? Icons.south_west_rounded
                        : categoryIcon(item.category),
                    color: iconColor,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        needsReview ? 'Needs review' : item.displayMerchant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        needsReview
                            ? 'Source or destination wasn’t detected'
                            : '${item.category} • ${item.originalSms.isEmpty ? 'Manual' : 'SMS'} • ${DateFormat('h:mm a').format(item.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: needsReview
                              ? context.finance.warning
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * .38,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amount,
                      style: AppTheme.money(
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: item.isIncome ? context.finance.income : null,
                        ),
                      ),
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
          Material(
            color: item.isIncome
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.primaryContainer,
            shape: ExpressiveShape.hero(),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 28,
                ),
                child: Column(
                  children: [
                    Icon(
                      item.isIncome
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      size: 30,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.isIncome ? 'Money received' : 'Money sent',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${item.isIncome ? '+' : '−'}${formatAmount(item.amount, item.currency)}',
                      style: AppTheme.money(
                        Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                  ],
                ),
              ),
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
                  child: FilledButton(
                    onPressed: onConfirm,
                    child: const Text('Confirm'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onEdit,
                    child: const Text('Correct'),
                  ),
                ),
              ],
            ),
            if (onReject != null)
              Center(
                child: TextButton(
                  onPressed: onReject,
                  child: const Text('Not a transaction'),
                ),
              ),
            if (onReanalyze != null)
              Center(
                child: TextButton.icon(
                  onPressed: onReanalyze,
                  icon: const Icon(Icons.blur_on_rounded),
                  label: const Text('Re-analyze source with Flow'),
                ),
              ),
          ],
          const SizedBox(height: 8),
          if (!needsReview)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Correct details'),
              ),
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
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: warning ? context.finance.warning : null,
              fontWeight: FontWeight.w500,
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
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .06),
                    shape: BoxShape.circle,
                  ),
                ),
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    shape: BoxShape.circle,
                  ),
                ),
                Icon(icon, size: 36, color: scheme.primary),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _ActivityLoading extends StatelessWidget {
  const _ActivityLoading();

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.all(16),
    itemCount: 7,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
    itemBuilder: (_, index) => Container(
      height: index == 0
          ? 56
          : index == 1
          ? 112
          : 72,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),
  );
}

class _StaggeredReveal extends StatefulWidget {
  const _StaggeredReveal({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_StaggeredReveal> createState() => _StaggeredRevealState();
}

class _StaggeredRevealState extends State<_StaggeredReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0.0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: AppMotion.emphasizedDecelerate,
          ),
        );

    Future.delayed(
      Duration(milliseconds: math.min(widget.index * 60, 300)),
      () {
        if (mounted) _controller.forward();
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
