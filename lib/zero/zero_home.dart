import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../agent/agent_presentation.dart';
import '../agent/agent_proposal.dart';
import '../app/app_controller.dart';
import '../app/app_state.dart';
import '../domain/conversation.dart';
import '../domain/insight_engine.dart';
import '../domain/money_format.dart';
import '../domain/preferences.dart';
import '../domain/transaction.dart';
import 'zero_editor.dart';
import 'zero_analysis.dart';
import 'zero_automation.dart';
import 'zero_intelligence.dart';
import 'zero_theme.dart';

enum _Place { overview, transactions }

class ZeroHome extends ConsumerStatefulWidget {
  const ZeroHome({super.key});

  @override
  ConsumerState<ZeroHome> createState() => _ZeroHomeState();
}

class _ZeroHomeState extends ConsumerState<ZeroHome> {
  _Place _place = _Place.overview;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 760;
        final content = IndexedStack(
          index: _place.index,
          children: [
            ZeroOverview(
              onTransactions: () =>
                  setState(() => _place = _Place.transactions),
              onAsk: _openAsk,
              onSettings: _openSettings,
              onReview: _openReview,
            ),
            ZeroTransactions(onAsk: _openAsk, onSettings: _openSettings),
          ],
        );
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                _Rail(
                  place: _place,
                  onChanged: (value) => setState(() => _place = value),
                  onAsk: _openAsk,
                ),
                Expanded(child: SafeArea(child: content)),
              ],
            ),
          );
        }
        return Scaffold(
          body: SafeArea(bottom: false, child: content),
          bottomNavigationBar: _Dock(
            place: _place,
            busy: app.asking,
            onChanged: (value) => setState(() => _place = value),
            onAsk: _openAsk,
          ),
        );
      },
    );
  }

  Future<void> _openAsk([String? question]) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ZeroAsk(seed: question)));
  }

  Future<void> _openReview() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ZeroReview()));

  Future<void> _openSettings() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const ZeroSettings()));
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.place,
    required this.busy,
    required this.onChanged,
    required this.onAsk,
  });
  final _Place place;
  final bool busy;
  final ValueChanged<_Place> onChanged;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(24, 4, 24, 10),
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: z.surface,
          border: Border.all(color: z.line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: _Destination(
                label: 'Overview',
                icon: Icons.space_dashboard_outlined,
                selected: place == _Place.overview,
                onTap: () => onChanged(_Place.overview),
              ),
            ),
            Expanded(
              child: _Destination(
                label: busy ? 'Working' : 'Ask',
                icon: Icons.auto_awesome_outlined,
                selected: false,
                emphasized: true,
                onTap: onAsk,
              ),
            ),
            Expanded(
              child: _Destination(
                label: 'Records',
                icon: Icons.format_list_bulleted_rounded,
                selected: place == _Place.transactions,
                onTap: () => onChanged(_Place.transactions),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.emphasized = false,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected || emphasized ? z.accent : z.faint,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected || emphasized ? z.text : z.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.place,
    required this.onChanged,
    required this.onAsk,
  });
  final _Place place;
  final ValueChanged<_Place> onChanged;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return Container(
      width: 92,
      decoration: BoxDecoration(
        color: z.surface,
        border: Border(right: BorderSide(color: z.line)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            Text('F', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 32),
            _RailButton(
              icon: Icons.space_dashboard_outlined,
              label: 'Overview',
              selected: place == _Place.overview,
              onTap: () => onChanged(_Place.overview),
            ),
            _RailButton(
              icon: Icons.format_list_bulleted_rounded,
              label: 'Records',
              selected: place == _Place.transactions,
              onTap: () => onChanged(_Place.transactions),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: IconButton.filled(
                tooltip: 'Ask your money',
                onPressed: onAsk,
                icon: const Icon(Icons.arrow_outward_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 76,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? z.accent : z.faint),
            const SizedBox(height: 5),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: selected ? z.text : z.faint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ZeroOverview extends ConsumerStatefulWidget {
  const ZeroOverview({
    super.key,
    required this.onTransactions,
    required this.onAsk,
    required this.onSettings,
    required this.onReview,
  });
  final VoidCallback onTransactions;
  final ValueChanged<String?> onAsk;
  final VoidCallback onSettings;
  final VoidCallback onReview;

  @override
  ConsumerState<ZeroOverview> createState() => _ZeroOverviewState();
}

class _ZeroOverviewState extends ConsumerState<ZeroOverview> {
  int monthOffset = 0;

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final today = DateTime.now();
    final target = DateTime(today.year, today.month + monthOffset);
    final now = DateTime(
      target.year,
      target.month,
      monthOffset == 0
          ? today.day
          : DateUtils.getDaysInMonth(target.year, target.month),
      today.hour,
      today.minute,
    );
    final month = app.transactions
        .where(
          (t) =>
              t.occurredAt.year == now.year && t.occurredAt.month == now.month,
        )
        .toList();
    final currency = _currency(month, app.preferences.currency);
    final outgoing = _sum(month, TransactionDirection.outgoing, currency);
    final incoming = _sum(month, TransactionDirection.incoming, currency);
    final review = app.transactions
        .where((t) => t.reviewState == ReviewState.needsReview)
        .length;
    final insights = InsightEngine.insights(app.transactions, now, limit: 2);
    final recent = [...app.transactions]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final hidden = app.preferences.hideAmounts;
    final previous = _previousComparable(app.transactions, now, currency);
    final change = previous == 0 ? null : (outgoing - previous) / previous;
    final z = context.zero;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => setState(() => monthOffset--),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          DateFormat('MMMM yyyy').format(now),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: monthOffset >= 0
                          ? null
                          : () => setState(() => monthOffset++),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                    IconButton(
                      tooltip: hidden ? 'Show amounts' : 'Hide amounts',
                      onPressed: () => ref
                          .read(appControllerProvider.notifier)
                          .updatePreferences(
                            app.preferences.copyWith(hideAmounts: !hidden),
                          ),
                      icon: Icon(
                        hidden
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: widget.onSettings,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Spent',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: z.muted),
                    ),
                    const SizedBox(height: 7),
                    _Money(
                      minor: outgoing,
                      currency: currency,
                      hidden: hidden,
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 13),
                    if (change != null)
                      Text(
                        '${change > 0 ? '↑' : '↓'} ${(change.abs() * 100).round()}% '
                        '${change > 0 ? 'more' : 'less'} than this point last month',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: change > 0 ? z.warning : z.positive,
                        ),
                      )
                    else
                      Text(
                        '${month.length} automatically captured transactions',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: z.muted),
                      ),
                    const SizedBox(height: 28),
                    _MiniTrend(
                      values: _daily(month, currency),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ZeroAnalysis(period: now),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: _QuietMetric(
                            label: 'Money in',
                            value: hidden
                                ? '••••'
                                : formatMoney(incoming, currency),
                          ),
                        ),
                        Container(width: 1, height: 38, color: z.line),
                        Expanded(
                          child: _QuietMetric(
                            label: 'Net',
                            value: hidden
                                ? '••••'
                                : formatMoney(incoming - outgoing, currency),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (insights.isNotEmpty || change != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 36, 24, 0),
                  child: _Briefing(
                    insights: insights,
                    change: change,
                    onAsk: widget.onAsk,
                  ),
                ),
              ),
            if (review > 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                  child: _Attention(count: review, onTap: widget.onReview),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        recent.isEmpty ? 'Start your record' : 'Recent',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (recent.isNotEmpty)
                      TextButton(
                        onPressed: widget.onTransactions,
                        child: const Text('View all'),
                      ),
                  ],
                ),
              ),
            ),
            if (recent.isEmpty)
              SliverToBoxAdapter(
                child: _EmptyLedger(
                  onImport: () =>
                      ref.read(appControllerProvider.notifier).importMessages(),
                  onAdd: () => showZeroTransactionEditor(context),
                ),
              )
            else
              SliverList.builder(
                itemCount: recent.take(6).length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _TransactionLine(
                    item: recent[index],
                    hidden: hidden,
                    onTap: () => _openDetail(context, recent[index]),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

class _QuietMetric extends StatelessWidget {
  const _QuietMetric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
          ),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _Briefing extends StatelessWidget {
  const _Briefing({
    required this.insights,
    required this.change,
    required this.onAsk,
  });
  final List<Insight> insights;
  final double? change;
  final ValueChanged<String?> onAsk;

  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    final text = insights.isNotEmpty
        ? '${insights.first.title}. ${insights.first.detail}'
        : change == null
        ? 'Your record is up to date. I’ll surface meaningful changes here as they emerge.'
        : change! > 0
        ? 'Spending is running ahead of last month. Ask for a breakdown to see what changed.'
        : 'Spending remains below the same point last month.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Briefing', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(text, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => onAsk(
            insights.isEmpty
                ? 'What changed this month?'
                : insights.first.question,
          ),
          icon: const Icon(Icons.arrow_outward_rounded, size: 17),
          label: const Text('Understand this'),
          style: TextButton.styleFrom(foregroundColor: z.accent),
        ),
      ],
    );
  }
}

class _Attention extends StatelessWidget {
  const _Attention({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return Semantics(
      button: true,
      label: '$count transactions need confirmation',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          color: z.subtle,
          child: Row(
            children: [
              Icon(Icons.error_outline_rounded, color: z.warning),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '$count ${count == 1 ? 'record needs' : 'records need'} confirmation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Icon(Icons.arrow_forward_rounded, size: 19),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTrend extends StatelessWidget {
  const _MiniTrend({required this.values, required this.onTap});
  final List<int> values;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    if (values.length < 2) return const SizedBox(height: 2);
    return Semantics(
      button: true,
      label: 'Open detailed spending analysis',
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 66,
          width: double.infinity,
          child: CustomPaint(
            painter: _TrendPainter(
              values: values,
              color: context.zero.accent,
              line: context.zero.line,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.color,
    required this.line,
  });
  final List<int> values;
  final Color color;
  final Color line;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()..color = line,
    );
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max <= 0) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        size.width * i / (values.length - 1),
        size.height - 4 - (size.height - 10) * values[i] / max,
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}

class ZeroTransactions extends ConsumerStatefulWidget {
  const ZeroTransactions({
    super.key,
    required this.onAsk,
    required this.onSettings,
  });
  final ValueChanged<String?> onAsk;
  final VoidCallback onSettings;
  @override
  ConsumerState<ZeroTransactions> createState() => _ZeroTransactionsState();
}

class _ZeroTransactionsState extends ConsumerState<ZeroTransactions> {
  final _search = TextEditingController();
  bool _searching = false;
  TransactionDirection? _direction;
  bool _reviewOnly = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final hidden = app.preferences.hideAmounts;
    final query = _search.text.trim().toLowerCase();
    final items = app.transactions.where((t) {
      if (_direction != null && t.direction != _direction) return false;
      if (_reviewOnly && t.reviewState != ReviewState.needsReview) return false;
      if (query.isNotEmpty &&
          !'${t.merchant} ${t.category} ${t.note ?? ''}'.toLowerCase().contains(
            query,
          )) {
        return false;
      }
      return true;
    }).toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    final groups = <DateTime, List<MoneyTransaction>>{};
    for (final item in items) {
      groups
          .putIfAbsent(
            DateTime(
              item.occurredAt.year,
              item.occurredAt.month,
              item.occurredAt.day,
            ),
            () => [],
          )
          .add(item);
    }
    final z = context.zero;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Transactions',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Search',
                    onPressed: () => setState(() => _searching = !_searching),
                    icon: const Icon(Icons.search_rounded),
                  ),
                  IconButton(
                    tooltip: 'Filters',
                    onPressed: _showFilters,
                    icon: Badge(
                      isLabelVisible: _direction != null || _reviewOnly,
                      smallSize: 7,
                      child: const Icon(Icons.tune_rounded),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Add transaction',
                    onPressed: () => showZeroTransactionEditor(context),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Merchant, category or note',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${items.length} ${items.length == 1 ? 'record' : 'records'}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: z.muted),
                    ),
                  ),
                  if (_direction != null || _reviewOnly)
                    TextButton(
                      onPressed: () => setState(() {
                        _direction = null;
                        _reviewOnly = false;
                      }),
                      child: const Text('Clear filters'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        app.transactions.isEmpty
                            ? 'No transactions yet'
                            : 'No matching transactions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final entry = groups.entries.elementAt(index);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                top: index == 0 ? 0 : 28,
                                bottom: 6,
                              ),
                              child: Text(
                                _dayLabel(entry.key),
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(color: z.muted),
                              ),
                            ),
                            for (final item in entry.value)
                              _TransactionLine(
                                item: item,
                                hidden: hidden,
                                onTap: () => _openDetail(context, item),
                              ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFilters() async {
    var direction = _direction;
    var review = _reviewOnly;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter transactions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                SegmentedButton<TransactionDirection?>(
                  segments: const [
                    ButtonSegment(value: null, label: Text('All')),
                    ButtonSegment(
                      value: TransactionDirection.outgoing,
                      label: Text('Money out'),
                    ),
                    ButtonSegment(
                      value: TransactionDirection.incoming,
                      label: Text('Money in'),
                    ),
                  ],
                  selected: {direction},
                  onSelectionChanged: (value) =>
                      setSheet(() => direction = value.first),
                ),
                const SizedBox(height: 16),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Needs confirmation'),
                  value: review,
                  onChanged: (value) => setSheet(() => review = value),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _direction = direction;
                      _reviewOnly = review;
                    });
                    Navigator.pop(sheet);
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TransactionLine extends StatelessWidget {
  const _TransactionLine({
    required this.item,
    required this.hidden,
    required this.onTap,
  });
  final MoneyTransaction item;
  final bool hidden;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    final incoming = item.direction == TransactionDirection.incoming;
    return Semantics(
      button: true,
      label:
          '${item.merchant}, ${item.category}, ${item.amountMinor} ${item.currency}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: z.line.withValues(alpha: .75)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: item.reviewState == ReviewState.needsReview
                      ? z.warning
                      : z.faint,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _readableMerchant(item.merchant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.reviewState == ReviewState.needsReview
                          ? '${item.category} · Review'
                          : '${item.category} · ${DateFormat.jm().format(item.occurredAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: item.reviewState == ReviewState.needsReview
                            ? z.warning
                            : z.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                hidden
                    ? '••••'
                    : '${incoming ? '+' : '−'}${formatMoney(item.amountMinor, item.currency)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: incoming ? z.positive : z.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.onImport, required this.onAdd});
  final VoidCallback onImport;
  final VoidCallback onAdd;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Turn payment messages into a useful record automatically.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: context.zero.muted),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onImport,
            child: const Text('Import payment messages'),
          ),
          const SizedBox(height: 2),
          TextButton(
            onPressed: onAdd,
            child: const Text('Or add a transaction manually'),
          ),
        ],
      ),
    );
  }
}

class ZeroReview extends ConsumerStatefulWidget {
  const ZeroReview({super.key});
  @override
  ConsumerState<ZeroReview> createState() => _ZeroReviewState();
}

class _ZeroReviewState extends ConsumerState<ZeroReview> {
  final Set<int?> _skipped = {};
  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final pending = app.transactions
        .where(
          (t) =>
              t.reviewState == ReviewState.needsReview &&
              !_skipped.contains(t.id),
        )
        .toList();
    if (pending.isEmpty) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_rounded, size: 38),
              const SizedBox(height: 16),
              Text(
                'Everything is clear',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'There is nothing waiting for your attention.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: context.zero.muted),
              ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Return to overview'),
              ),
            ],
          ),
        ),
      );
    }
    final item = pending.first;
    final z = context.zero;
    return Scaffold(
      appBar: AppBar(
        title: Text('${pending.length} remaining'),
        centerTitle: false,
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                LinearProgressIndicator(
                  value: _skipped.isEmpty
                      ? 0
                      : _skipped.length / (_skipped.length + pending.length),
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 30),
                Text(
                  item.reviewState == ReviewState.needsReview
                      ? 'Please confirm this record'
                      : 'Review this transaction',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'It was captured automatically, but one or more details are worth checking.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: z.muted),
                ),
                const SizedBox(height: 42),
                _Money(
                  minor: item.amountMinor,
                  currency: item.currency,
                  hidden: app.preferences.hideAmounts,
                  style: Theme.of(context).textTheme.displayLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _readableMerchant(item.merchant),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 28),
                _Fact(label: 'Category', value: item.category),
                _Fact(
                  label: 'Date',
                  value: DateFormat('d MMMM, h:mm a').format(item.occurredAt),
                ),
                _Fact(
                  label: 'Direction',
                  value: item.direction == TransactionDirection.incoming
                      ? 'Money in'
                      : 'Money out',
                ),
                if ((item.account ?? '').isNotEmpty)
                  _Fact(label: 'Account', value: item.account!),
                if ((item.sourceText ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 30),
                  Text(
                    'Original message',
                    style: Theme.of(
                      context,
                    ).textTheme.labelMedium?.copyWith(color: z.muted),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    item.sourceText!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: z.muted),
                  ),
                ],
                const SizedBox(height: 34),
                OutlinedButton(
                  onPressed: () =>
                      showZeroTransactionEditor(context, transaction: item),
                  child: const Text('Correct details'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => ref
                      .read(appControllerProvider.notifier)
                      .confirmTransaction(
                        item.copyWith(reviewState: ReviewState.confirmed),
                      ),
                  child: const Text('Confirm'),
                ),
                TextButton(
                  onPressed: () => setState(() => _skipped.add(item.id)),
                  child: const Text('Skip for now'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ZeroDetail extends ConsumerWidget {
  const ZeroDetail({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    final item = app.transactions.where((t) => t.id == id).firstOrNull;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This transaction no longer exists.')),
      );
    }
    final z = context.zero;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Edit',
            onPressed: () =>
                showZeroTransactionEditor(context, transaction: item),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: () async {
              final approved = await _confirm(
                context,
                title: 'Delete this transaction?',
                body:
                    'This record will be removed from totals, analysis and AI answers. This cannot be undone.',
                destructiveLabel: 'Delete transaction',
              );
              if (!approved) return;
              await ref
                  .read(appControllerProvider.notifier)
                  .deleteTransaction(id);
              if (context.mounted) Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              Text(
                item.direction == TransactionDirection.incoming
                    ? 'Money in'
                    : 'Money out',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: z.muted),
              ),
              const SizedBox(height: 10),
              _Money(
                minor: item.amountMinor,
                currency: item.currency,
                hidden: app.preferences.hideAmounts,
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 12),
              Text(
                _readableMerchant(item.merchant),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 40),
              _Fact(
                label: 'Date',
                value: DateFormat(
                  'd MMMM yyyy, h:mm a',
                ).format(item.occurredAt),
              ),
              _Fact(label: 'Category', value: item.category),
              if ((item.account ?? '').isNotEmpty)
                _Fact(label: 'Account', value: item.account!),
              _Fact(
                label: 'Source',
                value: switch (item.source) {
                  TransactionSource.message => 'Transaction message',
                  TransactionSource.notification => 'Payment notification',
                  TransactionSource.manual => 'Added manually',
                },
              ),
              if ((item.note ?? '').isNotEmpty)
                _Fact(label: 'Note', value: item.note!),
              if ((item.sourceText ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 34),
                Text(
                  'Source and reasoning',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  'Automatically extracted from the message below. '
                  '${item.confidence >= .9 ? 'The extraction was high confidence.' : 'The extraction may need confirmation.'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: z.muted),
                ),
                const SizedBox(height: 16),
                SelectableText(
                  item.sourceText!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: z.muted),
                ),
              ],
              const SizedBox(height: 34),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ZeroAsk(
                      seed:
                          'Tell me about the ${item.merchant} transaction for ${formatMoney(item.amountMinor, item.currency)}.',
                    ),
                  ),
                ),
                icon: const Icon(Icons.arrow_outward_rounded),
                label: const Text('Ask about this transaction'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: z.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: z.muted),
            ),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class ZeroAsk extends ConsumerStatefulWidget {
  const ZeroAsk({super.key, this.seed});
  final String? seed;
  @override
  ConsumerState<ZeroAsk> createState() => _ZeroAskState();
}

class _ZeroAskState extends ConsumerState<ZeroAsk> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _seedSent = false;

  @override
  void initState() {
    super.initState();
    if ((widget.seed ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(widget.seed!));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String value) async {
    if (value.trim().isEmpty || _seedSent && value == widget.seed) return;
    if (value == widget.seed) _seedSent = true;
    _input.clear();
    await ref.read(appControllerProvider.notifier).ask(value.trim());
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider).requireValue;
    final connected = app.aiConnection == AiConnection.connected;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask your money'),
        actions: [
          if (app.threads.isNotEmpty)
            IconButton(
              tooltip: 'Conversation history',
              onPressed: () => _showHistory(context, app),
              icon: const Icon(Icons.history_rounded),
            ),
          if (app.conversation.isNotEmpty)
            IconButton(
              tooltip: 'New question',
              onPressed: () =>
                  ref.read(appControllerProvider.notifier).startNewChat(),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Expanded(
                  child: app.conversation.isEmpty && !app.asking
                      ? _AskStart(onAsk: _ask)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                          itemCount:
                              app.conversation.length +
                              (app.asking || app.error != null ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index < app.conversation.length) {
                              return _AnswerTurn(
                                message: app.conversation[index],
                                transactions: app.transactions,
                                onAsk: _ask,
                              );
                            }
                            return _Working(
                              app: app,
                              onRetry: app.retryQuestion == null
                                  ? null
                                  : () => _ask(app.retryQuestion!),
                            );
                          },
                        ),
                ),
                if (app.pendingAgentProposal case final proposal?)
                  _ProposalDecision(proposal: proposal),
                if (app.lastAgentAction case final action?)
                  _ActionResult(
                    message: action,
                    canUndo: app.lastAgentUndoId != null,
                  ),
                if (!connected)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: OutlinedButton(
                      onPressed: () => showZeroIntelligence(context),
                      child: const Text('Connect intelligence'),
                    ),
                  ),
                _AskComposer(
                  controller: _input,
                  enabled: connected && !app.asking,
                  busy: app.asking,
                  onSend: () => _ask(_input.text),
                  onStop: () =>
                      ref.read(appControllerProvider.notifier).stopAgent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showHistory(BuildContext context, AppState app) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ConversationHistory(
          threads: app.threads,
          activeId: app.activeThreadId,
        ),
      );
}

class _ConversationHistory extends ConsumerWidget {
  const _ConversationHistory({required this.threads, required this.activeId});
  final List<ConversationThread> threads;
  final int? activeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .72,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Conversations',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'New conversation',
                onPressed: () async {
                  await ref.read(appControllerProvider.notifier).startNewChat();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            itemCount: threads.length,
            itemBuilder: (context, index) {
              final thread = threads[index];
              return Dismissible(
                key: ValueKey(thread.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirm(
                  context,
                  title: 'Delete this conversation?',
                  body:
                      'Its questions and answers will be removed. Transactions are unaffected.',
                  destructiveLabel: 'Delete',
                ),
                onDismissed: (_) => ref
                    .read(appControllerProvider.notifier)
                    .deleteConversationThread(thread.id),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: context.zero.negative,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                child: InkWell(
                  onTap: () async {
                    await ref
                        .read(appControllerProvider.notifier)
                        .openConversationThread(thread.id);
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 76),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: context.zero.line),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                thread.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${thread.messageCount} messages · ${DateFormat.MMMd().format(thread.updatedAt)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: context.zero.muted),
                              ),
                            ],
                          ),
                        ),
                        if (thread.id == activeId)
                          Icon(
                            Icons.check_rounded,
                            color: context.zero.positive,
                            size: 19,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _ProposalDecision extends ConsumerWidget {
  const _ProposalDecision({required this.proposal});
  final AgentProposal proposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final z = context.zero;
    final destructive =
        proposal.kind == AgentProposalKind.deleteTransaction ||
        proposal.kind == AgentProposalKind.clearConversation ||
        proposal.kind == AgentProposalKind.deleteMemory;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: z.surface,
        border: Border.all(color: destructive ? z.negative : z.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(proposal.title, style: Theme.of(context).textTheme.titleMedium),
          if (destructive)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'This removes data',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: z.negative),
              ),
            ),
          const SizedBox(height: 5),
          Text(
            proposal.explanation,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: z.muted),
          ),
          for (final detail in proposal.details.take(3))
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text('• $detail'),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => ref
                    .read(appControllerProvider.notifier)
                    .rejectAgentProposal(),
                child: const Text('Not now'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => ref
                    .read(appControllerProvider.notifier)
                    .approveAgentProposal(),
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: z.negative)
                    : null,
                child: Text(destructive ? 'Approve removal' : 'Approve change'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionResult extends ConsumerWidget {
  const _ActionResult({required this.message, required this.canUndo});
  final String message;
  final bool canUndo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.fromLTRB(24, 0, 24, 10),
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: context.zero.subtle,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.check_circle_outline_rounded, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
        if (canUndo)
          TextButton(
            onPressed: () =>
                ref.read(appControllerProvider.notifier).undoLastAgentAction(),
            child: const Text('Undo'),
          ),
      ],
    ),
  );
}

class _AskStart extends StatelessWidget {
  const _AskStart({required this.onAsk});
  final ValueChanged<String> onAsk;
  @override
  Widget build(BuildContext context) {
    final questions = [
      'What changed this month?',
      'Where did I overspend?',
      'Find unusual transactions',
      'Show subscriptions',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
      children: [
        Text(
          'What would you like\nto understand?',
          style: Theme.of(context).textTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Answers come from your own records and cite the transactions they rest on.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: context.zero.muted),
        ),
        const SizedBox(height: 36),
        for (final question in questions)
          InkWell(
            onTap: () => onAsk(question),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 17),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.zero.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      question,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _AnswerTurn extends StatelessWidget {
  const _AnswerTurn({
    required this.message,
    required this.transactions,
    required this.onAsk,
  });
  final ConversationMessage message;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onAsk;
  @override
  Widget build(BuildContext context) {
    if (message.author == MessageAuthor.person) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 26),
        child: Text(
          message.text,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.parts.isEmpty)
            Text(message.text, style: Theme.of(context).textTheme.bodyLarge)
          else
            for (final part in message.parts)
              _AgentDocumentPart(
                part: part,
                transactions: transactions,
                onAsk: onAsk,
              ),
          if (message.verified)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Verified against your local records',
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: context.zero.positive),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentDocumentPart extends StatelessWidget {
  const _AgentDocumentPart({
    required this.part,
    required this.transactions,
    required this.onAsk,
  });
  final AgentPart part;
  final List<MoneyTransaction> transactions;
  final ValueChanged<String> onAsk;
  @override
  Widget build(BuildContext context) {
    final data = part.data;
    final text = data['text']?.toString();
    if (part.kind == AgentPartKind.followUps) {
      final values = data['questions'];
      final questions = values is List
          ? values.map((e) => '$e').toList()
          : const <String>[];
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final q in questions)
              ActionChip(label: Text(q), onPressed: () => onAsk(q)),
          ],
        ),
      );
    }
    if (part.kind == AgentPartKind.transactionList) {
      final raw = data['transactionIds'];
      final ids = raw is List
          ? raw.whereType<num>().map((e) => e.toInt()).toSet()
          : <int>{};
      final rows = transactions.where((t) => ids.contains(t.id)).toList();
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(
          children: [
            for (final item in rows)
              _TransactionLine(
                item: item,
                hidden: false,
                onTap: () => _openDetail(context, item),
              ),
          ],
        ),
      );
    }
    if (part.kind == AgentPartKind.breakdown ||
        part.kind == AgentPartKind.metricRow) {
      final raw = data['rows'] ?? data['metrics'] ?? data['values'];
      final rows = raw is List ? raw : const [];
      return Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (data['title'] != null)
              Text(
                '${data['title']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            for (final row in rows)
              if (row is Map)
                _Fact(
                  label: '${row['label'] ?? row['title'] ?? ''}',
                  value: row['amountMinor'] is num
                      ? formatMoney(
                          (row['amountMinor'] as num).toInt(),
                          '${row['currency'] ?? 'INR'}',
                        )
                      : '${row['value'] ?? ''}',
                ),
          ],
        ),
      );
    }
    if (text == null || text.trim().isEmpty) return const SizedBox.shrink();
    final conclusion = part.kind == AgentPartKind.conclusion;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: conclusion
            ? Theme.of(context).textTheme.titleLarge
            : Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: part.kind == AgentPartKind.sourceNote
                    ? context.zero.muted
                    : context.zero.text,
              ),
      ),
    );
  }
}

class _Working extends StatelessWidget {
  const _Working({required this.app, required this.onRetry});
  final AppState app;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          if (app.error == null)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(Icons.error_outline_rounded, color: context.zero.negative),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.error ?? app.askStage ?? 'Working with your records…',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: context.zero.muted),
                ),
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Try the same question again'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AskComposer extends StatelessWidget {
  const _AskComposer({
    required this.controller,
    required this.enabled,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });
  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: enabled
                    ? 'Ask about your money'
                    : 'Connect intelligence to ask',
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: busy ? 'Stop' : 'Send',
            onPressed: busy
                ? onStop
                : enabled
                ? onSend
                : null,
            icon: Icon(busy ? Icons.stop_rounded : Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class ZeroSettings extends ConsumerWidget {
  const ZeroSettings({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(appControllerProvider).requireValue;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
            children: [
              const _SettingsSection(
                title: 'Core',
                detail: 'How Fund Flow reads and understands money activity',
              ),
              _SettingsLink(
                title: 'Automation',
                detail: 'Messages and notifications',
                icon: Icons.bolt_outlined,
                highlighted: true,
                onTap: () => showZeroAutomation(context),
              ),
              _SettingsLink(
                title: 'Intelligence',
                detail: switch (app.aiConnection) {
                  AiConnection.connected =>
                    'Connected to ${app.preferences.aiProvider.name}',
                  AiConnection.checking => 'Checking connection',
                  AiConnection.rejected => 'Connection needs attention',
                  _ => 'Not connected',
                },
                icon: Icons.memory_outlined,
                highlighted: true,
                onTap: () => showZeroIntelligence(context),
              ),
              const SizedBox(height: 26),
              const _SettingsSection(
                title: 'Your experience',
                detail: 'Only the controls you are likely to revisit',
              ),
              _SettingsLink(
                title: 'Privacy',
                detail: 'App lock, hidden amounts and data sharing',
                icon: Icons.shield_outlined,
                onTap: () => _privacy(context, ref, app),
              ),
              _SettingsLink(
                title: 'Preferences',
                detail:
                    '${app.preferences.currency} · ${app.preferences.appearance.name}',
                icon: Icons.tune_rounded,
                onTap: () => _preferences(context, ref, app),
              ),
              const SizedBox(height: 26),
              const _SettingsSection(
                title: 'Ownership',
                detail: 'Your records stay under your control',
              ),
              _SettingsLink(
                title: 'Data',
                detail: 'Conversations and local records',
                icon: Icons.storage_outlined,
                onTap: () => _data(context, ref),
              ),
              const SizedBox(height: 26),
              _SettingsLink(
                title: 'About',
                detail: 'Fund Flow · private by design',
                icon: Icons.info_outline_rounded,
                onTap: () => _about(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _privacy(
    BuildContext context,
    WidgetRef ref,
    AppState app,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => _SimpleSettingsSheet(
      title: 'Privacy',
      children: [
        _SettingToggle(
          title: 'Hide amounts',
          detail: 'Conceal figures throughout the app',
          value: app.preferences.hideAmounts,
          onChanged: (value) => ref
              .read(appControllerProvider.notifier)
              .updatePreferences(app.preferences.copyWith(hideAmounts: value)),
        ),
        _SettingToggle(
          title: 'App lock',
          detail: 'Require device authentication',
          value: app.preferences.lockApp,
          onChanged: ref.read(appControllerProvider.notifier).setAppLock,
        ),
        const _SettingNote(
          icon: Icons.shield_outlined,
          title: 'Data boundary',
          detail:
              'Transactions stay local. Questions and opted-in message text go to your AI provider.',
        ),
      ],
    ),
  );

  Future<void> _preferences(
    BuildContext context,
    WidgetRef ref,
    AppState app,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => _SimpleSettingsSheet(
      title: 'Preferences',
      children: [
        _SheetRow(
          title: 'Appearance',
          detail: app.preferences.appearance.name,
          onTap: () async {
            final value = await showModalBottomSheet<AppearancePreference>(
              context: sheet,
              builder: (_) => _ChoiceSheet<AppearancePreference>(
                title: 'Appearance',
                current: app.preferences.appearance,
                choices: const [
                  (AppearancePreference.system, 'Follow this device'),
                  (AppearancePreference.light, 'Light'),
                  (AppearancePreference.dark, 'Dark'),
                ],
              ),
            );
            if (value != null) {
              await ref
                  .read(appControllerProvider.notifier)
                  .updatePreferences(
                    app.preferences.copyWith(appearance: value),
                  );
            }
          },
        ),
        _SheetRow(
          title: 'Primary currency',
          detail: app.preferences.currency,
          onTap: () async {
            final value = await showModalBottomSheet<String>(
              context: sheet,
              isScrollControlled: true,
              builder: (_) => _CurrencySheet(current: app.preferences.currency),
            );
            if (value != null) {
              await ref
                  .read(appControllerProvider.notifier)
                  .updatePreferences(app.preferences.copyWith(currency: value));
            }
          },
        ),
      ],
    ),
  );

  Future<void> _data(
    BuildContext context,
    WidgetRef ref,
  ) => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => _SimpleSettingsSheet(
      title: 'Data',
      children: [
        _SheetRow(
          title: 'Delete current conversation',
          detail: 'Questions and answers only; transactions stay',
          destructive: true,
          onTap: () async {
            final approved = await _confirm(
              sheet,
              title: 'Delete this conversation?',
              body:
                  'The current questions and answers will be removed. Your transactions and other conversations remain.',
              destructiveLabel: 'Delete conversation',
            );
            if (approved) {
              await ref
                  .read(appControllerProvider.notifier)
                  .clearConversation();
              if (sheet.mounted) Navigator.pop(sheet);
            }
          },
        ),
      ],
    ),
  );

  Future<void> _about(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    builder: (_) => _SimpleSettingsSheet(
      title: 'About Fund Flow',
      children: [
        const _SettingNote(
          icon: Icons.auto_awesome_outlined,
          title: 'AI-first, local-first',
          detail:
              'Fund Flow turns payment messages into a private financial record, then lets you ask questions grounded in that record.',
        ),
        const _SettingNote(
          icon: Icons.shield_outlined,
          title: 'Data boundary',
          detail:
              'Transactions stay on this device. Only questions and message text you explicitly analyze are sent to your chosen provider.',
        ),
        const _SheetRow(
          title: 'Version',
          detail: '0.0.1-dev.1',
          showArrow: false,
        ),
      ],
    ),
  );
}

class _SettingToggle extends StatelessWidget {
  const _SettingToggle({
    required this.title,
    required this.detail,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    child: Container(
      constraints: const BoxConstraints(minHeight: 74),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.zero.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class _SettingNote extends StatelessWidget {
  const _SettingNote({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.zero.subtle,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: context.zero.positive),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 5),
              Text(
                detail,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.title,
    required this.detail,
    this.onTap,
    this.destructive = false,
    this.showArrow = true,
  });
  final String title;
  final String detail;
  final VoidCallback? onTap;
  final bool destructive;
  final bool showArrow;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      constraints: const BoxConstraints(minHeight: 70),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.zero.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: destructive ? context.zero.negative : null,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
                ),
              ],
            ),
          ),
          if (showArrow && onTap != null)
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.zero.faint,
            ),
        ],
      ),
    ),
  );
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.current,
    required this.choices,
  });
  final String title;
  final T current;
  final List<(T, String)> choices;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          for (final choice in choices)
            InkWell(
              onTap: () => Navigator.pop(context, choice.$1),
              child: Container(
                constraints: const BoxConstraints(minHeight: 58),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: context.zero.line)),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(choice.$2)),
                    if (choice.$1 == current)
                      Icon(Icons.check_rounded, color: context.zero.positive),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _CurrencySheet extends StatefulWidget {
  const _CurrencySheet({required this.current});
  final String current;
  @override
  State<_CurrencySheet> createState() => _CurrencySheetState();
}

class _CurrencySheetState extends State<_CurrencySheet> {
  final search = TextEditingController();
  static const currencies = [
    ('INR', 'Indian rupee'),
    ('USD', 'US dollar'),
    ('EUR', 'Euro'),
    ('GBP', 'British pound'),
    ('AED', 'UAE dirham'),
    ('SGD', 'Singapore dollar'),
    ('AUD', 'Australian dollar'),
    ('CAD', 'Canadian dollar'),
    ('JPY', 'Japanese yen'),
    ('CHF', 'Swiss franc'),
  ];
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.toLowerCase().trim();
    final visible = currencies
        .where(
          (value) =>
              value.$1.toLowerCase().contains(query) ||
              value.$2.toLowerCase().contains(query),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
              child: Text(
                'Primary currency',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: TextField(
                controller: search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search currency',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final value = visible[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(value.$1),
                    subtitle: Text(value.$2),
                    trailing: value.$1 == widget.current
                        ? const Icon(Icons.check_rounded)
                        : null,
                    onTap: () => Navigator.pop(context, value.$1),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsLink extends StatelessWidget {
  const _SettingsLink({
    required this.title,
    required this.detail,
    required this.icon,
    this.onTap,
    this.highlighted = false,
  });
  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback? onTap;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final z = context.zero;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: EdgeInsets.only(bottom: highlighted ? 10 : 0),
        padding: EdgeInsets.symmetric(
          horizontal: highlighted ? 16 : 0,
          vertical: highlighted ? 17 : 20,
        ),
        decoration: BoxDecoration(
          color: highlighted ? z.subtle : null,
          border: highlighted
              ? null
              : Border(bottom: BorderSide(color: z.line)),
          borderRadius: highlighted ? BorderRadius.circular(18) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: z.muted, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: z.muted),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.arrow_forward_ios_rounded, size: 15),
          ],
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          detail,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.zero.muted),
        ),
      ],
    ),
  );
}

class _SimpleSettingsSheet extends StatelessWidget {
  const _SimpleSettingsSheet({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}

class _Money extends StatelessWidget {
  const _Money({
    required this.minor,
    required this.currency,
    required this.hidden,
    this.style,
  });
  final int minor;
  final String currency;
  final bool hidden;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final value = hidden ? 'Amount hidden' : formatMoney(minor, currency);
    return Semantics(
      label: value,
      excludeSemantics: true,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            hidden ? '••••••' : value,
            maxLines: 1,
            style: style?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

String _currency(List<MoneyTransaction> values, String fallback) {
  if (values.isEmpty) return fallback;
  final counts = <String, int>{};
  for (final value in values) {
    counts[value.currency] = (counts[value.currency] ?? 0) + 1;
  }
  return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
}

int _sum(
  Iterable<MoneyTransaction> values,
  TransactionDirection direction,
  String currency,
) => values
    .where((t) => t.direction == direction && t.currency == currency)
    .fold(0, (sum, t) => sum + t.amountMinor);

int _previousComparable(
  Iterable<MoneyTransaction> values,
  DateTime now,
  String currency,
) {
  final previousStart = DateTime(now.year, now.month - 1);
  final previousEnd = previousStart.add(
    now.difference(DateTime(now.year, now.month)),
  );
  return values
      .where(
        (t) =>
            t.currency == currency &&
            t.direction == TransactionDirection.outgoing &&
            !t.occurredAt.isBefore(previousStart) &&
            t.occurredAt.isBefore(previousEnd),
      )
      .fold(0, (sum, t) => sum + t.amountMinor);
}

List<int> _daily(List<MoneyTransaction> values, String currency) {
  if (values.isEmpty) return const [];
  final maxDay = values
      .map((t) => t.occurredAt.day)
      .reduce((a, b) => a > b ? a : b);
  return List.generate(
    maxDay,
    (i) => values
        .where(
          (t) =>
              t.currency == currency &&
              t.direction == TransactionDirection.outgoing &&
              t.occurredAt.day == i + 1,
        )
        .fold(0, (sum, t) => sum + t.amountMinor),
  );
}

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormat('EEEE, d MMMM').format(day);
}

String _readableMerchant(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'Unknown merchant';
  if (trimmed != trimmed.toUpperCase()) return trimmed;
  return trimmed
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

void _openDetail(BuildContext context, MoneyTransaction item) {
  if (item.id == null) return;
  Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => ZeroDetail(id: item.id!)),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String destructiveLabel,
}) async =>
    await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.delete_outline_rounded,
              color: sheet.zero.negative,
              size: 28,
            ),
            const SizedBox(height: 18),
            Text(title, style: Theme.of(sheet).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(
              body,
              style: Theme.of(
                sheet,
              ).textTheme.bodyMedium?.copyWith(color: sheet.zero.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(sheet, true),
              style: FilledButton.styleFrom(
                backgroundColor: sheet.zero.negative,
                minimumSize: const Size.fromHeight(52),
              ),
              child: Text(destructiveLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheet, false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Center(child: Text('Keep it')),
            ),
          ],
        ),
      ),
    ) ??
    false;
