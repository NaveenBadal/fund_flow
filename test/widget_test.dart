import 'package:expense_manager/theme/app_theme.dart';
import 'package:expense_manager/widgets/ui/flow_ui.dart';
import 'package:expense_manager/main.dart';
import 'package:expense_manager/flow_os/primitives/loom_mark.dart';
import 'package:expense_manager/flow_os/shell/command_rail.dart';
import 'package:expense_manager/flow_os/ingestion/evidence_consent_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expressive theme renders shaped Material components', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: const Scaffold(
          body: Card(
            child: Padding(padding: EdgeInsets.all(16), child: Text('Balance')),
          ),
        ),
      ),
    );

    expect(find.text('Balance'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('active Flow Orb does not schedule continuous frames', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(null),
        home: const Scaffold(body: FlowOrb(state: FlowOrbState.thinking)),
      ),
    );
    await tester.pump();

    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
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

  testWidgets('Flow navigation remains bounded at 200% text', (tester) async {
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
            bottomNavigationBar: FlowNavigationBar(
              selectedIndex: 1,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.bySemanticsLabel('Evidence timeline'), findsOneWidget);
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
          bottomNavigationBar: FlowNavigationBar(
            selectedIndex: 1,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proof'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
