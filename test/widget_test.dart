import 'package:expense_manager/theme/app_theme.dart';
import 'package:expense_manager/flow_os/primitives/loom_mark.dart';
import 'package:expense_manager/flow_os/shell/command_rail.dart';
import 'package:expense_manager/flow_os/shell/command_column.dart';
import 'package:expense_manager/flow_os/ingestion/evidence_consent_sheet.dart';
import 'package:expense_manager/flow_os/agent/decision_sheet.dart';
import 'package:expense_manager/widgets/ui/flow_ui.dart';
import 'package:expense_manager/flow_os/system/system_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flow theme exposes proprietary fixed signal colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: const Scaffold(body: Text('Balance')),
      ),
    );

    expect(find.text('Balance'), findsOneWidget);
    expect(AppTheme.light(null).colorScheme.primary, const Color(0xFF5B4BFF));
    expect(AppTheme.dark(null).colorScheme.secondary, const Color(0xFF22D3EE));
  });

  testWidgets('idle Loom Mark does not schedule continuous frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(null),
        home: const Scaffold(body: LoomMark(state: LoomState.ready)),
      ),
    );
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Command Rail remains bounded at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(null),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            bottomNavigationBar: CommandRail(
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Ask Flow'), findsOneWidget);
    expect(find.bySemanticsLabel('Proof and evidence'), findsOneWidget);
    expect(find.bySemanticsLabel('System controls'), findsOneWidget);
  });

  testWidgets('Evidence consent ledger is bounded and exposes both decisions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(null),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(body: EvidenceConsentSheet()),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('OPEN SMS TO FLOW?'), findsOneWidget);
    expect(find.bySemanticsLabel('KEEP CLOSED'), findsOneWidget);
    expect(find.bySemanticsLabel('OPEN CHANNEL →'), findsOneWidget);
  });

  testWidgets('Command Column stays bounded in compact and extended modes', (
    tester,
  ) async {
    for (final extended in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(null),
          home: Scaffold(
            body: Row(
              children: [
                CommandColumn(
                  selectedIndex: 1,
                  extended: extended,
                  onSelected: (_) {},
                ),
                const Expanded(child: SizedBox()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('PROOF, Inspect evidence'), findsOneWidget);
    }
  });

  testWidgets('Agent decision report remains bounded at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(null),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: AgentDecisionSheet(
              title: 'Review Flow action',
              description: 'Flow will update matching transaction evidence.',
              confirmLabel: 'Apply',
              notice: 'The change remains undoable.',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('CANCEL'), findsOneWidget);
    expect(find.bySemanticsLabel('APPLY'), findsOneWidget);
  });

  testWidgets('Flow command rail remains bounded at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            bottomNavigationBar: CommandRail(
              selectedIndex: 1,
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Proof and evidence'), findsOneWidget);
  });

  testWidgets('selected Proof label fits the compact navigation control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(null),
        home: Scaffold(
          bottomNavigationBar: CommandRail(
            selectedIndex: 1,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PROOF'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secondary Flow workspace remains scrollable at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(null),
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: FlowScaffold(
            title: 'Import history',
            eyebrow: 'Understand every AI routing decision.',
            slivers: [
              SliverToBoxAdapter(
                child: StatePanel(
                  icon: Icons.sms_outlined,
                  title: 'No evidence yet',
                  message: 'Imported and rejected signals will appear here.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('IMPORT HISTORY'), findsOneWidget);
    expect(find.text('No evidence yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('binary rail keeps complete labels at 200% text', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(2),
          ),
          child: Scaffold(
            body: SystemNode(
              code: 'PR-03',
              title: 'Amount visibility',
              detail: 'Values visible throughout the interface',
              control: BinaryRail(
                value: true,
                offLabel: 'VEIL',
                onLabel: 'SHOW',
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('VEIL'), findsOneWidget);
    expect(find.text('SHOW'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('high contrast preserves Flow signal roles at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = AppTheme.highContrastDark(null);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(320, 720),
            textScaler: TextScaler.linear(2),
            highContrast: true,
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: SystemNode(
                code: 'AI-01',
                title: 'Flow intelligence',
                detail: 'Evidence-bound analysis and answers',
                signal: NodeSignal.attention,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(theme.colorScheme.primary, const Color(0xFF5B4BFF));
    expect(theme.colorScheme.secondary, const Color(0xFF22D3EE));
    expect(theme.colorScheme.outline, theme.colorScheme.onSurface);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion navigation settles without idle frames', (
    tester,
  ) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(null),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: CommandRail(
                selectedIndex: selected,
                onSelected: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.bySemanticsLabel('Proof and evidence'));
    await tester.pump();

    expect(selected, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}
