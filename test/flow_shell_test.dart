import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fund_flow/ui2/shell/flow_composer.dart';
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
  FlowDestination destination = FlowDestination.today,
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
    today: const Text('TODAY'),
    activity: const Text('ACTIVITY'),
    review: const Text('REVIEW'),
    onOpenChat: onOpenChat ?? () {},
    reviewCount: reviewCount,
    composerHint: hint,
    composerBusy: busy,
  ),
);

void main() {
  testWidgets('the composer is present on every destination', (tester) async {
    _usePhone(tester);
    for (final destination in FlowDestination.values) {
      await tester.pumpWidget(_host(destination: destination));
      expect(
        find.byType(FlowComposer),
        findsOneWidget,
        reason: 'chat must be reachable from $destination',
      );
    }
  });

  testWidgets('destinations stay alive across switches', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(_host());
    // All three stay in the tree, offstage rather than disposed, so Activity
    // does not lose its place among hundreds of rows when Today is checked.
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('ACTIVITY', skipOffstage: false), findsOneWidget);
    expect(find.text('REVIEW', skipOffstage: false), findsOneWidget);
    // Only the active one is actually shown.
    expect(find.text('ACTIVITY'), findsNothing);
  });

  testWidgets('a backlog is visible from every screen', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(_host(reviewCount: 352));
    expect(find.text('352'), findsOneWidget);

    await tester.pumpWidget(
      _host(destination: FlowDestination.activity, reviewCount: 352),
    );
    expect(find.text('352'), findsOneWidget);
  });

  testWidgets('a large backlog still shows its real size', (tester) async {
    _usePhone(tester);
    // The count is the job. Rounding 352 down to "99+" hides whether this is
    // an evening of work or a minute.
    await tester.pumpWidget(_host(reviewCount: 352));
    expect(find.text('352'), findsOneWidget);

    await tester.pumpWidget(_host(reviewCount: 1284));
    expect(find.text('999+'), findsOneWidget);
  });

  testWidgets('no badge when there is nothing to review', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(_host(reviewCount: 0));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('the composer names what the screen is about', (tester) async {
    _usePhone(tester);
    await tester.pumpWidget(_host(hint: 'groceries in July'));
    expect(find.text('Ask about groceries in July'), findsOneWidget);
  });

  testWidgets('tapping the composer hands off rather than taking text', (
    tester,
  ) async {
    _usePhone(tester);
    var opened = 0;
    await tester.pumpWidget(_host(onOpenChat: () => opened++));
    // No TextField: text is never typed somewhere that cannot answer it.
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(FlowComposer));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('switching destinations reports the choice', (tester) async {
    _usePhone(tester);
    FlowDestination? chosen;
    await tester.pumpWidget(_host(onChanged: (value) => chosen = value));
    await tester.tap(find.text('Review'));
    await tester.pump();
    expect(chosen, FlowDestination.review);
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
            destination: FlowDestination.today,
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
    expect(find.byType(FlowComposer), findsOneWidget);
  });
}
