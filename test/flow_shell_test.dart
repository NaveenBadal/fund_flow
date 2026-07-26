import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/ui2/shell/flow_nav.dart';
import 'package:fund_flow/ui2/shell/flow_shell.dart';
import 'package:fund_flow/ui2/tokens/flow_theme.dart';

/// The default test window is 800px wide, which is above the shell's wide
/// breakpoint, so phone behaviour has to be asked for explicitly.
void _usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _host({
  FlowDestination destination = FlowDestination.home,
  int reviewCount = 0,
  String? hint,
  bool busy = false,
  ValueChanged<FlowDestination>? onChanged,
  VoidCallback? onOpenChat,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? FlowTheme.light(),
  home: FlowShell(
    destination: destination,
    onDestinationChanged: onChanged ?? (_) {},
    today: const Text('HOME'),
    activity: const Text('ACTIVITY'),
    review: const Text('ASK'),
    onOpenChat: onOpenChat ?? () {},
    reviewCount: reviewCount,
    composerHint: hint,
    composerBusy: busy,
  ),
);

void main() {
  testWidgets('Home, Activity and Ask are first-class destinations', (
    tester,
  ) async {
    _usePhone(tester);
    await tester.pumpWidget(_host());
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
    expect(find.bySemanticsLabel('Activity'), findsOneWidget);
    expect(find.bySemanticsLabel('Ask'), findsOneWidget);
  });

  testWidgets('destinations stay alive across switches', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(_host());
    // All three stay in the tree, offstage rather than disposed, so Activity
    // does not lose its place among hundreds of rows when Today is checked.
    expect(find.text('HOME'), findsOneWidget);
    expect(find.text('ACTIVITY', skipOffstage: false), findsOneWidget);
    expect(find.text('ASK', skipOffstage: false), findsOneWidget);
    // Only the active one is actually shown.
    expect(find.text('ACTIVITY'), findsNothing);
  });

  testWidgets('review work does not masquerade as an Ask badge', (
    tester,
  ) async {
    _usePhone(tester);
    await tester.pumpWidget(_host(reviewCount: 352));
    expect(find.text('352'), findsNothing);
  });

  testWidgets('switching destinations reports the choice', (tester) async {
    _usePhone(tester);
    FlowDestination? chosen;
    await tester.pumpWidget(_host(onChanged: (value) => chosen = value));
    await tester.tap(find.bySemanticsLabel('Ask'));
    await tester.pump();
    expect(chosen, FlowDestination.ask);
  });

  testWidgets('bounded at 200 percent text', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: FlowTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 780),
            textScaler: TextScaler.linear(2),
          ),
          child: FlowShell(
            destination: FlowDestination.home,
            onDestinationChanged: (_) {},
            today: const SizedBox(),
            activity: const SizedBox(),
            review: const SizedBox(),
            onOpenChat: () {},
            reviewCount: 12,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layouts move navigation to the side', (tester) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(reviewCount: 5));
    expect(tester.takeException(), isNull);
    // The bottom bar is replaced rather than duplicated alongside the rail.
    expect(find.byType(FlowNav), findsNothing);
    expect(find.bySemanticsLabel('Home'), findsOneWidget);
  });
}
