import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../utils/currency_utils.dart';
import '../widgets/ui/command_ui.dart';
import 'budget_screen.dart';
import 'savings_goals_screen.dart';
import 'subscriptions_screen.dart';

class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});
  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  double _experiment = 0;

  @override
  Widget build(BuildContext context) {
    final balance =
        ref.watch(currentMonthBalanceProvider).asData?.value ??
        const <String, double>{};
    final budgets = ref.watch(budgetProgressProvider).asData?.value ?? const [];
    final goals = ref.watch(savingsGoalsProvider).asData?.value ?? const [];
    final briefing = ref.watch(moneyBriefingProvider);
    final detectedIncome = balance['income'] ?? 0;
    final expense = balance['expense'] ?? 0;
    final income = briefing?.income ?? detectedIncome;
    final free = (briefing?.safeToSpend ?? (income - expense))
        .clamp(0, double.infinity)
        .toDouble();
    final commitments = briefing?.commitmentsTotal ?? 0.0;
    final goalReserve = briefing?.goalReserve ?? 0.0;
    final currency = ref.watch(preferredCurrencyProvider);
    final hidden = ref.watch(privateModeProvider);
    final futureFree = (free - _experiment)
        .clamp(0, double.infinity)
        .toDouble();
    final maxExperiment = free <= 0 ? 1.0 : free;
    final pressure = budgets.where((b) {
      final limit = (b['limit_amount'] as num?)?.toDouble() ?? 0;
      final spent = (b['spent'] as num?)?.toDouble() ?? 0;
      return limit > 0 && spent / limit >= .8;
    }).length;
    String money(double value) =>
        hidden ? maskAmount(currency) : formatAmount(value, currency);

    return CommandScaffold(
      eyebrow: 'Touch a decision and watch the month bend',
      title: 'Possible futures',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _FutureField(
              current: money(free),
              future: money(futureFree),
              experiment: money(_experiment),
              ratio: free <= 0 ? 1 : (_experiment / free).clamp(0, 1),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SIMULATE AN UNPLANNED DECISION',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 1.25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Slider(
                  value: _experiment.clamp(0, maxExperiment).toDouble(),
                  min: 0,
                  max: maxExperiment,
                  onChanged: free <= 0
                      ? null
                      : (value) => setState(() => _experiment = value),
                ),
                Row(
                  children: [
                    const Text('No change'),
                    const Spacer(),
                    Text('Use ${money(_experiment)}'),
                  ],
                ),
                if (_experiment > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _experiment > free * .75
                          ? 'This collapses most of your flexible runway. Flow would ask you to pause.'
                          : _experiment > free * .4
                          ? 'Possible, but it materially narrows the rest of the month.'
                          : 'This future remains inside your current safety field.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: SectionLabel('Forces already shaping the outcome'),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
          sliver: SliverList.list(
            children: [
              _FutureBranch(
                index: '01',
                title: 'Inevitable money',
                value: money(commitments),
                statement: commitments > 0
                    ? 'Already protected before your flexible future is calculated.'
                    : 'No repeating movement is currently strong enough to protect.',
                color: const Color(0xFF8FA8FF),
                onTap: () => _push(const SubscriptionsScreen()),
              ),
              _FutureBranch(
                index: '02',
                title: 'Future anchors',
                value: money(goalReserve),
                statement:
                    '${goals.length} future destination${goals.length == 1 ? '' : 's'} influencing today.',
                color: const Color(0xFF65EAD1),
                onTap: () => _push(const SavingsGoalsScreen()),
              ),
              _FutureBranch(
                index: '03',
                title: 'Pressure boundaries',
                value: pressure == 0 ? 'CALM' : '$pressure HOT',
                statement: pressure == 0
                    ? 'No category is pressing hard against its boundary.'
                    : '$pressure categor${pressure == 1 ? 'y is' : 'ies are'} changing the recommended path.',
                color: const Color(0xFFFF8066),
                onTap: () => _push(const BudgetScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _push(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

class _FutureField extends StatelessWidget {
  const _FutureField({
    required this.current,
    required this.future,
    required this.experiment,
    required this.ratio,
  });
  final String current;
  final String future;
  final String experiment;
  final double ratio;

  @override
  Widget build(BuildContext context) => Container(
    height: 330,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFF090D16),
      borderRadius: BorderRadius.circular(38),
      border: Border.all(color: Colors.white12),
    ),
    child: Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _FuturePainter(ratio))),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LIVE COUNTERFACTUAL',
                style: TextStyle(
                  color: Color(0xFFC7FF4A),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              const Text(
                'After this imagined decision',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                future,
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -2,
                ),
              ),
              const Text(
                'would remain flexible',
                style: TextStyle(color: Colors.white54),
              ),
              const Spacer(),
              Row(
                children: [
                  _FutureDatum(label: 'NOW', value: current),
                  const SizedBox(width: 32),
                  _FutureDatum(label: 'IMAGINED', value: experiment),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FutureDatum extends StatelessWidget {
  const _FutureDatum({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: Colors.white30,
          fontSize: 9,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _FuturePainter extends CustomPainter {
  const _FuturePainter(this.ratio);
  final double ratio;
  @override
  void paint(Canvas canvas, Size size) {
    final safe = Paint()
      ..color = const Color(0xFF65EAD1).withValues(alpha: .18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final risk = Paint()
      ..color = const Color(0xFFFF8066).withValues(alpha: .28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final origin = Offset(size.width * .78, size.height * .34);
    canvas.drawCircle(origin, 88 - ratio * 34, safe);
    canvas.drawCircle(origin, 42 + ratio * 52, risk);
    canvas.drawLine(
      origin,
      Offset(size.width, size.height * (.7 + ratio * .2)),
      risk,
    );
  }

  @override
  bool shouldRepaint(covariant _FuturePainter old) => old.ratio != ratio;
}

class _FutureBranch extends StatelessWidget {
  const _FutureBranch({
    required this.index,
    required this.title,
    required this.value,
    required this.statement,
    required this.color,
    required this.onTap,
  });
  final String index;
  final String title;
  final String value;
  final String statement;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .35),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            index,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  statement,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_outward_rounded, size: 18),
        ],
      ),
    ),
  );
}
