import 'dart:ui';

import 'package:expense_manager/flow_os/foundation/flow_color.dart';
import 'package:expense_manager/flow_os/primitives/coordinate_label.dart';
import 'package:expense_manager/flow_os/primitives/cut_surface.dart';
import 'package:expense_manager/flow_os/primitives/loom_mark.dart';
import 'package:expense_manager/flow_os/shell/command_rail.dart';
import 'package:expense_manager/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Flow evidence scroll and navigation meet profile frame budget', (
    tester,
  ) async {
    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> values) => timings.addAll(values);

    await tester.pumpWidget(const _PerformanceHarness());
    await tester.pumpAndSettle();
    WidgetsBinding.instance.addTimingsCallback(collect);
    addTearDown(() => WidgetsBinding.instance.removeTimingsCallback(collect));

    final ledger = find.byKey(const ValueKey('performance-ledger'));
    for (var index = 0; index < 6; index++) {
      await tester.fling(ledger, const Offset(0, -900), 5000);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.bySemanticsLabel('Proof and evidence'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('System controls'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    WidgetsBinding.instance.removeTimingsCallback(collect);
    expect(timings.length, greaterThan(30));
    final build =
        timings.map((value) => value.buildDuration.inMicroseconds).toList()
          ..sort();
    final raster =
        timings.map((value) => value.rasterDuration.inMicroseconds).toList()
          ..sort();
    final total =
        timings.map((value) => value.totalSpan.inMicroseconds).toList()..sort();
    int percentile(List<int> values, double fraction) =>
        values[((values.length - 1) * fraction).round()];
    final p90Build = percentile(build, .90);
    final p90Raster = percentile(raster, .90);
    final p90Total = percentile(total, .90);
    final overBudget = total.where((value) => value > 33334).length;

    // ignore: avoid_print
    print(
      'FLOW_PERF frames=${timings.length} p90_build_us=$p90Build p90_raster_us=$p90Raster p90_total_us=$p90Total over_33ms=$overBudget',
    );
    expect(p90Build, lessThan(16667));
    expect(p90Raster, lessThan(16667));
    expect(p90Total, lessThan(33334));
    expect(overBudget / timings.length, lessThan(.05));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}

class _PerformanceHarness extends StatefulWidget {
  const _PerformanceHarness();
  @override
  State<_PerformanceHarness> createState() => _PerformanceHarnessState();
}

class _PerformanceHarnessState extends State<_PerformanceHarness> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.dark(null),
    home: Scaffold(
      body: CustomScrollView(
        key: const ValueKey('performance-ledger'),
        slivers: [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 28, 20, 18),
              child: Row(
                children: [
                  LoomMark(size: 44, state: LoomState.proven),
                  SizedBox(width: 14),
                  Expanded(
                    child: CoordinateLabel(
                      'Proof / performance ledger',
                      line: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            sliver: SliverList.builder(
              itemCount: 320,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RepaintBoundary(
                  child: CutSurface(
                    cut: 10,
                    accent: index % 9 == 0 ? FlowColor.amber : FlowColor.proof,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          child: CoordinateLabel('EV ${index + 1}'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Verified transaction signal ${index + 1}',
                            maxLines: 1,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '₹${(index + 1) * 137}',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: CommandRail(
        selectedIndex: _selected,
        onSelected: (value) => setState(() => _selected = value),
      ),
    ),
  );
}
